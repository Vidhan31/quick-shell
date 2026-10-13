#include "SystemSettings.hpp"

#include <QCoreApplication>
#include <QDir>
#include <QElapsedTimer>
#include <QJsonObject>
#include <QLocale>
#include <QProcess>
#include <QSet>
#include <QSettings>

#include <KAuthorized>
#include <KPluginMetaData>

namespace qs::plugins {

SettingsWorker::SettingsWorker(QObject *parent)
    : QObject(parent) {}

void SettingsWorker::load() {
    struct CategoryInfo {
        QString id;
        QString parentId;
        QString name;
        QString icon;
        int weight = 100;
    };

    QMap<QString, CategoryInfo> categories;
    const QStringList categoryDirs = {
        QStringLiteral("/usr/share/systemsettings/categories"),
        QStringLiteral("/usr/share/kinfocenter/categories")
    };

    for (const auto &dirPath : categoryDirs) {
        QDir dir(dirPath);
        if (!dir.exists()) {
            continue;
        }

        const auto files = dir.entryList({QStringLiteral("*.desktop")}, QDir::Files);
        for (const auto &fileName : files) {
            QSettings s(dir.filePath(fileName), QSettings::IniFormat);
            s.beginGroup(QStringLiteral("Desktop Entry"));

            QString id = s.value(QStringLiteral("X-KDE-System-Settings-Category")).toString();
            if (id.isEmpty()) {
                id = s.value(QStringLiteral("X-KDE-KInfoCenter-Category")).toString();
            }
            if (id.isEmpty()) {
                continue;
            }

            CategoryInfo info;
            info.id = id;
            info.parentId = s.value(QStringLiteral("X-KDE-System-Settings-Parent-Category")).toString();
            if (info.parentId.isEmpty()) {
                info.parentId = s.value(QStringLiteral("X-KDE-KInfoCenter-Parent-Category")).toString();
            }
            info.name = s.value(QStringLiteral("Name")).toString();
            info.icon = s.value(QStringLiteral("Icon")).toString();
            info.weight = s.value(QStringLiteral("X-KDE-Weight"), 100).toInt();

            categories.insert(id, info);
        }
    }

    QList<SettingModule> moduleList;
    QList<KPluginMetaData> plugins;
    plugins << KPluginMetaData::findPlugins(QStringLiteral("plasma/kcms"));
    plugins << KPluginMetaData::findPlugins(QStringLiteral("plasma/kcms/systemsettings"));
    plugins << KPluginMetaData::findPlugins(QStringLiteral("plasma/kcms/systemsettings_qwidgets"));
    plugins << KPluginMetaData::findPlugins(QStringLiteral("plasma/kcms/kinfocenter"));

    QSet<QString> seenIds;

    for (const auto &meta : plugins) {
        const QString pluginId = meta.pluginId();
        if (pluginId.isEmpty() || seenIds.contains(pluginId)) {
            continue;
        }
        seenIds.insert(pluginId);

        if (meta.isHidden()) {
            continue;
        }

        if (!KAuthorized::authorizeControlModule(pluginId)) {
            continue;
        }

        bool formFactorOk = meta.formFactors().isEmpty();
        for (const auto &ff : meta.formFactors()) {
            if (ff == QLatin1String("desktop") || ff == QLatin1String("all")) {
                formFactorOk = true;
                break;
            }
        }
        if (!formFactorOk) {
            continue;
        }

        const bool isKInfo = meta.fileName().contains(QLatin1String("/kinfocenter/"));

        QString catId = meta.value(QStringLiteral("X-KDE-System-Settings-Parent-Category"));
        if (catId.isEmpty()) {
            catId = meta.value(QStringLiteral("X-KDE-System-Settings-Parent-Category-V2"));
        }
        if (catId.isEmpty() && isKInfo) {
            catId = meta.value(QStringLiteral("X-KDE-KInfoCenter-Category"));
        }

        QString catName;
        QString catPath;
        if (categories.contains(catId)) {
            const auto &ci = categories[catId];
            catName = ci.name;
            if (!ci.parentId.isEmpty() && categories.contains(ci.parentId)) {
                catPath = categories[ci.parentId].name + QStringLiteral(" › ") + ci.name;
            } else {
                catPath = ci.name;
            }
        } else {
            catName = isKInfo ? QStringLiteral("System Information") : QStringLiteral("System Settings");
            catPath = catName;
        }

        QStringList kwList;
        const QJsonObject rawData = meta.rawData();
        if (!QLocale().name().startsWith(QLatin1String("en_"))) {
            const QString enName = rawData[QStringLiteral("KPlugin")].toObject()[QStringLiteral("Name")].toString();
            if (!enName.isEmpty()) {
                kwList.append(enName);
            }
        }

        const QString rawKw = meta.value(QStringLiteral("X-KDE-Keywords"));
        if (!rawKw.isEmpty()) {
            kwList.append(rawKw.split(QLatin1Char(',')));
        }

        const QString name = meta.name();
        kwList.append(name);
        kwList.replaceInStrings(QStringLiteral("\u00AD"), QString());
        kwList.removeDuplicates();

        QStringList cleanedKws;
        cleanedKws.reserve(kwList.size());
        for (const auto &kw : kwList) {
            const QString trimmed = kw.trimmed();
            if (!trimmed.isEmpty()) {
                cleanedKws.append(trimmed);
            }
        }

        SettingModule item;
        item.id = pluginId;
        item.name = name;
        item.nameLc = name.toLower();
        item.description = meta.description();
        item.descriptionLc = item.description.toLower();
        item.category = catName;
        item.categoryLc = catName.toLower();
        item.categoryPath = catPath;
        item.iconName = meta.iconName();
        item.keywords = cleanedKws;
        item.keywordsLc = cleanedKws.join(QLatin1Char(' ')).toLower();
        item.isKInfoCenter = isKInfo;
        item.weight = meta.value(QStringLiteral("X-KDE-Weight"), 100);

        moduleList.append(item);
    }

    std::sort(moduleList.begin(), moduleList.end(), [](const SettingModule &a, const SettingModule &b) {
        if (a.categoryPath != b.categoryPath) {
            return a.categoryPath < b.categoryPath;
        }
        return a.name < b.name;
    });

    QVariantList cachedList;
    cachedList.reserve(moduleList.size());
    for (const auto &item : moduleList) {
        QVariantMap map;
        map.insert(QStringLiteral("id"), item.id);
        map.insert(QStringLiteral("name"), item.name);
        map.insert(QStringLiteral("nameLc"), item.nameLc);
        map.insert(QStringLiteral("description"), item.description);
        map.insert(QStringLiteral("descriptionLc"), item.descriptionLc);
        map.insert(QStringLiteral("category"), item.category);
        map.insert(QStringLiteral("categoryLc"), item.categoryLc);
        map.insert(QStringLiteral("categoryPath"), item.categoryPath);
        map.insert(QStringLiteral("iconName"), item.iconName);
        map.insert(QStringLiteral("keywords"), item.keywords);
        map.insert(QStringLiteral("keywordsLc"), item.keywordsLc);
        map.insert(QStringLiteral("isKInfoCenter"), item.isKInfoCenter);
        map.insert(QStringLiteral("weight"), item.weight);
        cachedList.append(map);
    }

    emit loaded(moduleList, cachedList);
}

SystemSettings::SystemSettings(QObject *parent)
    : QObject(parent) {
    qRegisterMetaType<SettingModule>();
    qRegisterMetaType<QList<SettingModule>>();
    m_worker = new SettingsWorker();
    m_worker->moveToThread(&m_thread);
    connect(&m_thread, &QThread::finished, m_worker, &QObject::deleteLater);
    connect(&m_thread, &QThread::started, m_worker, &SettingsWorker::load);
    connect(this, &SystemSettings::requestLoad, m_worker, &SettingsWorker::load);
    connect(m_worker, &SettingsWorker::loaded, this, &SystemSettings::onLoaded);
    m_loading = true;
    m_thread.start();
}

SystemSettings::~SystemSettings() {
    m_thread.quit();
    m_thread.wait();
}

void SystemSettings::onLoaded(const QList<SettingModule> &modules, const QVariantList &cachedList) {
    m_modules = modules;
    m_cachedModuleList = cachedList;
    m_loaded = true;
    m_loading = false;
    emit modulesChanged();
}

void SystemSettings::reload() {
    if (m_loading) {
        return;
    }
    m_loading = true;
    m_loaded = false;
    emit modulesChanged();
    emit requestLoad();
}

bool SystemSettings::waitForLoaded(int timeoutMs) {
    if (m_loaded) {
        return true;
    }
    QElapsedTimer timer;
    timer.start();
    while (!m_loaded && timer.elapsed() < timeoutMs) {
        QCoreApplication::processEvents(QEventLoop::AllEvents, 50);
        QThread::msleep(10);
    }
    return m_loaded;
}

bool SystemSettings::isSettingsQuery(const QString &raw) const {
    const QString trimmed = raw.trimmed();
    if (trimmed.isEmpty()) {
        return false;
    }

    if (raw.startsWith(QLatin1String("s "), Qt::CaseInsensitive) ||
        raw.startsWith(QLatin1String("s:"), Qt::CaseInsensitive) ||
        raw.startsWith(QLatin1String("settings "), Qt::CaseInsensitive) ||
        raw.startsWith(QLatin1String("settings:"), Qt::CaseInsensitive)) {
        return true;
    }

    if (trimmed.compare(QLatin1String("settings"), Qt::CaseInsensitive) == 0) {
        return true;
    }

    return false;
}

QString SystemSettings::searchTerm(const QString &raw) const {
    if (raw.startsWith(QLatin1String("settings:"), Qt::CaseInsensitive)) {
        return raw.mid(9).trimmed();
    }
    if (raw.startsWith(QLatin1String("settings "), Qt::CaseInsensitive)) {
        return raw.mid(9).trimmed();
    }
    if (raw.trimmed().compare(QLatin1String("settings"), Qt::CaseInsensitive) == 0) {
        return QString();
    }
    if (raw.startsWith(QLatin1String("s:"), Qt::CaseInsensitive)) {
        return raw.mid(2).trimmed();
    }
    if (raw.startsWith(QLatin1String("s "), Qt::CaseInsensitive)) {
        return raw.mid(2).trimmed();
    }
    return QString();
}

void SystemSettings::open(const QString &pluginId, bool standalone) const {
    if (pluginId.isEmpty()) {
        return;
    }

    bool isKInfo = false;
    for (const auto &item : m_modules) {
        if (item.id == pluginId) {
            isKInfo = item.isKInfoCenter;
            break;
        }
    }

    if (standalone) {
        QProcess::startDetached(QStringLiteral("kcmshell6"), {pluginId});
    } else if (isKInfo) {
        QProcess::startDetached(QStringLiteral("kinfocenter"), {pluginId});
    } else {
        QProcess::startDetached(QStringLiteral("systemsettings"), {pluginId});
    }
}

} // namespace qs::plugins
