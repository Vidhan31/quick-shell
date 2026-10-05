#pragma once

#include <QtQml/qqmlregistration.h>

#include <QObject>
#include <QString>
#include <QStringList>
#include <QVariantMap>

namespace qs::plugins {

class PathProbe : public QObject {
    Q_OBJECT
    QML_ELEMENT

public:
    explicit PathProbe(QObject *parent = nullptr);
    ~PathProbe() override;

    // Classifies raw launcher input as a filesystem path. Returns
    //   pathShape  looks like a path at all (leading /, ./, ../ or ~)
    //   abs        ~ expanded and cleaned; only meaningful when pathShape
    //   exists     resolves to something on disk
    //   isDir      directory; QFileInfo follows symlinks, so a link to a
    //              directory reports true
    //   isFile     regular file; the launcher reveals it in its parent
    //   iconName   freedesktop icon name, empty when nothing applies
    // Safe to call per keystroke from the GUI thread: no network, one stat().
    [[nodiscard]] Q_INVOKABLE QVariantMap classify(const QString &text) const;

    // Opens a directory in the running file manager, or reveals a file inside
    // its parent. Returns immediately: the D-Bus call is async, so a wedged
    // file manager cannot stall the shell, and failure falls back to the
    // dolphin CLI.
    Q_INVOKABLE void reveal(const QString &absPath, bool isDir);

    Q_INVOKABLE bool copyFile(const QString &absPath);

    Q_INVOKABLE bool openWith(const QString &absPath);

private:
    void _fallbackToCli(const QString &absPath, bool isDir) const;
};

} // namespace qs::plugins
