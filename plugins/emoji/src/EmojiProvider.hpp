#pragma once

#include <QObject>
#include <QString>
#include <QStringList>
#include <QVariantList>
#include <QVariantMap>
#include <QtQml/qqmlregistration.h>

#include <atomic>
#include <vector>

namespace qs::plugins {

struct EmojiItem {
    QString glyph;
    QString name;
    QString nameLc;
    QString codePoints;
    QString group;
    QString subgroup;
    QString subgroupLc;
};

struct CategoryGroup {
    QString name;
    QString icon;
    std::vector<EmojiItem> emojis;
};

class EmojiProvider : public QObject {
    Q_OBJECT
    QML_ELEMENT

    Q_PROPERTY(bool isLoaded READ isLoaded NOTIFY loadedChanged)
    Q_PROPERTY(int totalCount READ totalCount NOTIFY loadedChanged)

public:
    explicit EmojiProvider(QObject *parent = nullptr);
    ~EmojiProvider() override = default;

    bool isLoaded() const { return m_loaded; }
    int totalCount() const { return m_totalCount; }

    Q_INVOKABLE bool isEmojiQuery(const QString &raw) const;
    Q_INVOKABLE QString searchTerm(const QString &raw) const;
    Q_INVOKABLE QVariantList getCategories(const QString &filter, int columns = 11);
    Q_INVOKABLE QVariantList getRows(const QString &filter, int columns = 11);
    Q_INVOKABLE void selectEmoji(const QString &glyph, const QString &name, const QString &code);

    Q_INVOKABLE void copyEmoji(const QString &glyph);
    Q_INVOKABLE void pasteEmoji(const QString &glyph, bool shift = false);

signals:
    void loadedChanged();
    void emojiSelected(const QString &glyph, const QString &name, const QString &code);

private:
    void ensureLoaded();
    void parseFile(const QString &filePath);
    void executePaste(bool shift, int delayMs);

    bool m_loaded = false;
    int m_totalCount = 0;
    std::atomic<bool> m_isPasting{false};
    std::vector<CategoryGroup> m_categories;
};

} // namespace qs::plugins
