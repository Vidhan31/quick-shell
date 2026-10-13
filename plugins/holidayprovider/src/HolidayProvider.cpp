#include "HolidayProvider.hpp"

#include <QDate>
#include <QDateTime>
#include <QFile>
#include <QFileInfo>
#include <QThreadPool>

namespace qs::plugins {

namespace {

QString dateToKey(const QVariant &val) {
    if (val.userType() == QMetaType::QDate) {
        return val.toDate().toString(QStringLiteral("yyyy-MM-dd"));
    }
    if (val.userType() == QMetaType::QDateTime) {
        return val.toDateTime().date().toString(QStringLiteral("yyyy-MM-dd"));
    }
    if (val.canConvert<QDateTime>()) {
        const QDateTime dt = val.toDateTime();
        if (dt.isValid()) {
            return dt.date().toString(QStringLiteral("yyyy-MM-dd"));
        }
    }
    if (val.canConvert<QDate>()) {
        const QDate d = val.toDate();
        if (d.isValid()) {
            return d.toString(QStringLiteral("yyyy-MM-dd"));
        }
    }
    const QString s = val.toString().trimmed();
    if (s.size() == 10 && s[4] == u'-' && s[7] == u'-') {
        return s;
    }
    const QDate d = QDate::fromString(s, Qt::ISODate);
    if (d.isValid()) {
        return d.toString(QStringLiteral("yyyy-MM-dd"));
    }
    return QString();
}

QVariantMap parseIcsContent(const QString &text) {
    QVariantMap map;
    QString unfolded = text;
    unfolded.replace(QStringLiteral("\r\n "), QString());
    unfolded.replace(QStringLiteral("\r\n\t"), QString());
    unfolded.replace(QStringLiteral("\n "), QString());
    unfolded.replace(QStringLiteral("\n\t"), QString());

    const QStringList lines = unfolded.split(u'\n');
    bool inEvent = false;
    QString startDate;
    QString summary;

    for (const QString &rawLine : lines) {
        const QString line = rawLine.trimmed();
        if (line == QLatin1String("BEGIN:VEVENT")) {
            inEvent = true;
            startDate.clear();
            summary.clear();
        } else if (line == QLatin1String("END:VEVENT")) {
            if (inEvent && !startDate.isEmpty() && !summary.isEmpty()) {
                QVariantList list = map.value(startDate).toList();
                list.append(summary);
                map.insert(startDate, list);
            }
            inEvent = false;
        } else if (inEvent) {
            if (line.startsWith(QLatin1String("DTSTART"))) {
                const int colon = line.indexOf(u':');
                if (colon != -1) {
                    const QString raw = line.mid(colon + 1).trimmed();
                    if (raw.size() >= 8) {
                        const QString y = raw.mid(0, 4);
                        const QString m = raw.mid(4, 2);
                        const QString d = raw.mid(6, 2);
                        startDate = y + u'-' + m + u'-' + d;
                    }
                }
            } else if (line.startsWith(QLatin1String("SUMMARY"))) {
                const int colon = line.indexOf(u':');
                if (colon != -1) {
                    QString raw = line.mid(colon + 1);
                    raw.replace(QStringLiteral("\\,"), QStringLiteral(","));
                    raw.replace(QStringLiteral("\\;"), QStringLiteral(";"));
                    raw.replace(QStringLiteral("\\n"), QStringLiteral(" "));
                    raw.replace(QStringLiteral("\\\\"), QStringLiteral("\\"));
                    summary = raw.trimmed();
                }
            }
        }
    }
    return map;
}

} // namespace

HolidayProvider::HolidayProvider(QObject *parent)
    : QObject(parent) {
    connect(&m_watcher, &QFileSystemWatcher::fileChanged, this, [this](const QString &path) {
        if (path == m_icsPath) {
            triggerLoad();
        }
    });
}

void HolidayProvider::setIcsPath(const QString &path) {
    if (m_icsPath == path) {
        return;
    }
    if (!m_icsPath.isEmpty() && m_watcher.files().contains(m_icsPath)) {
        m_watcher.removePath(m_icsPath);
    }
    m_icsPath = path;
    emit icsPathChanged();

    if (!m_icsPath.isEmpty() && QFile::exists(m_icsPath)) {
        m_watcher.addPath(m_icsPath);
    }
    triggerLoad();
}

QVariantList HolidayProvider::eventsForDate(const QVariant &dateVal) const {
    const QString key = dateToKey(dateVal);
    if (key.isEmpty()) {
        return {};
    }
    return m_eventsByDate.value(key).toList();
}

bool HolidayProvider::hasEvents(const QVariant &dateVal) const {
    const QString key = dateToKey(dateVal);
    if (key.isEmpty()) {
        return false;
    }
    return m_eventsByDate.contains(key) && !m_eventsByDate.value(key).toList().isEmpty();
}

void HolidayProvider::loadEvents() {
    triggerLoad();
}

void HolidayProvider::reload() {
    triggerLoad();
}

void HolidayProvider::triggerLoad() {
    if (m_icsPath.isEmpty()) {
        return;
    }
    const QString filePath = m_icsPath;
    const quint64 id = ++m_requestId;

    QThreadPool::globalInstance()->start([this, filePath, id]() {
        QFile file(filePath);
        QVariantMap parsed;
        bool ok = false;
        if (file.open(QIODevice::ReadOnly | QIODevice::Text)) {
            const QString content = QString::fromUtf8(file.readAll());
            parsed = parseIcsContent(content);
            ok = true;
        }

        QMetaObject::invokeMethod(this, [this, id, parsed, ok]() {
            if (id != m_requestId) {
                return;
            }
            m_eventsByDate = parsed;
            m_loaded = ok;
            emit eventsChanged();
            emit loadedChanged();
        }, Qt::QueuedConnection);
    });
}

} // namespace qs::plugins
