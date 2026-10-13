#pragma once

#include <QtQml/qqmlregistration.h>

#include <QList>
#include <QMap>
#include <QObject>
#include <QString>
#include <QStringList>
#include <QThread>
#include <QVariantList>
#include <QVariantMap>

namespace qs::plugins {

struct SettingModule {
    QString id;
    QString name;
    QString nameLc;
    QString description;
    QString descriptionLc;
    QString category;
    QString categoryLc;
    QString categoryPath;
    QString iconName;
    QStringList keywords;
    QString keywordsLc;
    bool isKInfoCenter = false;
    int weight = 100;
};

class SettingsWorker : public QObject {
    Q_OBJECT

public:
    explicit SettingsWorker(QObject *parent = nullptr);

public slots:
    void load();

signals:
    void loaded(const QList<SettingModule> &modules, const QVariantList &cachedList);
};

class SystemSettings : public QObject {
    Q_OBJECT
    QML_ELEMENT

    Q_PROPERTY(QVariantList modules READ modules NOTIFY modulesChanged)
    Q_PROPERTY(int count READ count NOTIFY modulesChanged)
    Q_PROPERTY(bool loaded READ loaded NOTIFY modulesChanged)

public:
    explicit SystemSettings(QObject *parent = nullptr);
    ~SystemSettings() override;

    [[nodiscard]] QVariantList modules() const { return m_cachedModuleList; }
    [[nodiscard]] int count() const { return static_cast<int>(m_cachedModuleList.size()); }
    [[nodiscard]] bool loaded() const { return m_loaded; }

    Q_INVOKABLE bool isSettingsQuery(const QString &raw) const;
    Q_INVOKABLE QString searchTerm(const QString &raw) const;
    Q_INVOKABLE void open(const QString &pluginId, bool standalone = false) const;
    Q_INVOKABLE void reload();

    bool waitForLoaded(int timeoutMs = 5000);

signals:
    void modulesChanged();
    void requestLoad();

private slots:
    void onLoaded(const QList<SettingModule> &modules, const QVariantList &cachedList);

private:
    QThread m_thread;
    SettingsWorker *m_worker{nullptr};

    QList<SettingModule> m_modules;
    QVariantList m_cachedModuleList;
    bool m_loaded = false;
    bool m_loading = false;
};

} // namespace qs::plugins

Q_DECLARE_METATYPE(qs::plugins::SettingModule)
Q_DECLARE_METATYPE(QList<qs::plugins::SettingModule>)
