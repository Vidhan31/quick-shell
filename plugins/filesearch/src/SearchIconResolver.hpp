#pragma once

#include <QString>
#include <QHash>
#include <QMimeDatabase>
#include <QReadWriteLock>

namespace qs::plugins {

class SearchIconResolver {
public:
    SearchIconResolver();
    ~SearchIconResolver() = default;

    SearchIconResolver(const SearchIconResolver &) = delete;
    SearchIconResolver &operator=(const SearchIconResolver &) = delete;

    QString resolve(const QString &filePath, bool isDir);

private:
    QMimeDatabase m_mimeDb;
    QHash<QString, QString> m_cache;
    mutable QReadWriteLock m_lock;
};

} // namespace qs::plugins
