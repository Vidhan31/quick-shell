#include "EmojiProvider.hpp"

#include <chrono>
#include <thread>
#include <poll.h>
#include <unistd.h>
#include <linux/input-event-codes.h>

#include <QClipboard>
#include <QDBusConnection>
#include <QDBusMessage>
#include <QDBusUnixFileDescriptor>
#include <QDebug>
#include <QFile>
#include <QGuiApplication>
#include <QTextStream>
#include <QThread>

#include <algorithm>

#include "libei.h"

namespace qs::plugins {

namespace {

QString iconForGroup(const QString &group) {
    if (group == QLatin1String("Smileys & Emotion")) return QStringLiteral("😀");
    if (group == QLatin1String("People & Body")) return QStringLiteral("👋");
    if (group == QLatin1String("Animals & Nature")) return QStringLiteral("🐻");
    if (group == QLatin1String("Food & Drink")) return QStringLiteral("🍔");
    if (group == QLatin1String("Travel & Places")) return QStringLiteral("✈️");
    if (group == QLatin1String("Activities")) return QStringLiteral("⚽");
    if (group == QLatin1String("Objects")) return QStringLiteral("💡");
    if (group == QLatin1String("Symbols")) return QStringLiteral("🔣");
    if (group == QLatin1String("Flags")) return QStringLiteral("🚩");
    return QStringLiteral("✨");
}

} // namespace

EmojiProvider::EmojiProvider(QObject *parent)
    : QObject(parent)
{
}

bool EmojiProvider::isEmojiQuery(const QString &raw) const {
    const QString trimmed = raw.trimmed();
    if (trimmed.isEmpty()) return false;

    if (raw.startsWith(QLatin1String("e "), Qt::CaseInsensitive) ||
        raw.startsWith(QLatin1String("emoji "), Qt::CaseInsensitive) ||
        raw.startsWith(QLatin1Char(':'))) {
        return true;
    }

    if (trimmed.compare(QLatin1String("emoji"), Qt::CaseInsensitive) == 0) {
        return true;
    }

    return false;
}

QString EmojiProvider::searchTerm(const QString &raw) const {
    if (raw.startsWith(QLatin1String("e "), Qt::CaseInsensitive)) {
        return raw.mid(2).trimmed();
    }
    if (raw.startsWith(QLatin1String("emoji "), Qt::CaseInsensitive)) {
        return raw.mid(6).trimmed();
    }
    if (raw.startsWith(QLatin1Char(':'))) {
        QString s = raw.mid(1);
        if (s.endsWith(QLatin1Char(':'))) {
            s.chop(1);
        }
        return s.trimmed();
    }
    if (raw.trimmed().compare(QLatin1String("emoji"), Qt::CaseInsensitive) == 0) {
        return QString();
    }
    return raw.trimmed();
}

void EmojiProvider::ensureLoaded() {
    if (m_loaded) return;
    parseFile(QStringLiteral("/usr/share/unicode/emoji/emoji-test.txt"));
    m_loaded = true;
    emit loadedChanged();
}

void EmojiProvider::parseFile(const QString &filePath) {
    QFile file(filePath);
    if (!file.open(QIODevice::ReadOnly | QIODevice::Text)) {
        return;
    }

    QTextStream in(&file);
    QString currentGroup;
    QString currentSubgroup;
    CategoryGroup *currentCategoryGroup = nullptr;

    while (!in.atEnd()) {
        const QString line = in.readLine().trimmed();
        if (line.isEmpty()) continue;

        if (line.startsWith(QLatin1String("# group:"))) {
            currentGroup = line.mid(8).trimmed();
            if (!currentGroup.isEmpty()) {
                auto it = std::find_if(m_categories.begin(), m_categories.end(), [&](const CategoryGroup &cg) {
                    return cg.name == currentGroup;
                });
                if (it != m_categories.end()) {
                    currentCategoryGroup = &(*it);
                } else {
                    CategoryGroup cg;
                    cg.name = currentGroup;
                    cg.icon = iconForGroup(currentGroup);
                    m_categories.push_back(std::move(cg));
                    currentCategoryGroup = &m_categories.back();
                }
            }
            continue;
        }

        if (line.startsWith(QLatin1String("# subgroup:"))) {
            currentSubgroup = line.mid(11).trimmed();
            continue;
        }

        if (line.startsWith(QLatin1Char('#'))) continue;

        const int semiIdx = line.indexOf(QLatin1Char(';'));
        if (semiIdx == -1) continue;

        const QString rawCodes = line.left(semiIdx).trimmed();
        const int hashIdx = line.indexOf(QLatin1Char('#'), semiIdx + 1);
        if (hashIdx == -1) continue;

        const QString status = line.mid(semiIdx + 1, hashIdx - semiIdx - 1).trimmed();
        if (status != QLatin1String("fully-qualified")) continue;

        const QString comment = line.mid(hashIdx + 1).trimmed();
        const int firstSpace = comment.indexOf(QLatin1Char(' '));
        if (firstSpace == -1) continue;

        const QString glyph = comment.left(firstSpace).trimmed();
        const QString afterGlyph = comment.mid(firstSpace + 1).trimmed();
        const int secondSpace = afterGlyph.indexOf(QLatin1Char(' '));
        if (secondSpace == -1) continue;

        const QString name = afterGlyph.mid(secondSpace + 1).trimmed();
        if (name.isEmpty() || glyph.isEmpty()) continue;

        const QStringList parts = rawCodes.split(QLatin1Char(' '), Qt::SkipEmptyParts);
        QStringList formattedCodes;
        formattedCodes.reserve(parts.size());
        for (const QString &p : parts) {
            formattedCodes.append(QStringLiteral("U+") + p);
        }
        const QString codePoints = formattedCodes.join(QLatin1Char(' '));

        if (!currentCategoryGroup) {
            CategoryGroup cg;
            cg.name = currentGroup.isEmpty() ? QStringLiteral("Other") : currentGroup;
            cg.icon = iconForGroup(cg.name);
            m_categories.push_back(std::move(cg));
            currentCategoryGroup = &m_categories.back();
        }

        EmojiItem item;
        item.glyph = glyph;
        item.name = name;
        item.nameLc = name.toLower();
        item.codePoints = codePoints;
        item.group = currentGroup;
        item.subgroup = currentSubgroup;
        item.subgroupLc = currentSubgroup.toLower();

        currentCategoryGroup->emojis.push_back(std::move(item));
        m_totalCount++;
    }

    m_categories.erase(
        std::remove_if(m_categories.begin(), m_categories.end(), [](const CategoryGroup &cg) {
            return cg.emojis.empty();
        }),
        m_categories.end()
    );
}

QVariantList EmojiProvider::getRows(const QString &filter, int columns) {
    ensureLoaded();
    if (columns <= 0) columns = 11;

    const QString q = filter.trimmed().toLower();
    const QStringList terms = q.isEmpty() ? QStringList() : q.split(QLatin1Char(' '), Qt::SkipEmptyParts);

    QVariantList result;
    int catIdx = 0;

    for (const auto &cat : m_categories) {
        std::vector<const EmojiItem*> matching;
        if (terms.isEmpty()) {
            matching.reserve(cat.emojis.size());
            for (const auto &e : cat.emojis) {
                matching.push_back(&e);
            }
        } else {
            for (const auto &e : cat.emojis) {
                bool ok = true;
                for (const auto &t : terms) {
                    if (!e.nameLc.contains(t) && !e.subgroupLc.contains(t)) {
                        ok = false;
                        break;
                    }
                }
                if (ok) {
                    matching.push_back(&e);
                }
            }
        }

        if (matching.empty()) {
            catIdx++;
            continue;
        }

        QVariantMap header;
        header.insert(QStringLiteral("isHeader"), true);
        header.insert(QStringLiteral("category"), cat.name);
        header.insert(QStringLiteral("icon"), cat.icon);
        header.insert(QStringLiteral("count"), static_cast<int>(matching.size()));
        header.insert(QStringLiteral("categoryIndex"), catIdx);
        result.append(header);

        const int total = static_cast<int>(matching.size());
        for (int i = 0; i < total; i += columns) {
            QVariantMap row;
            row.insert(QStringLiteral("isHeader"), false);
            row.insert(QStringLiteral("category"), cat.name);

            QVariantList emojis;
            const int count = std::min(columns, total - i);
            emojis.reserve(count);
            for (int j = 0; j < count; ++j) {
                const EmojiItem *item = matching[i + j];
                QVariantMap m;
                m.insert(QStringLiteral("glyph"), item->glyph);
                m.insert(QStringLiteral("name"), item->name);
                m.insert(QStringLiteral("code"), item->codePoints);
                m.insert(QStringLiteral("group"), item->group);
                m.insert(QStringLiteral("subgroup"), item->subgroup);
                emojis.append(m);
            }
            row.insert(QStringLiteral("emojis"), emojis);
            result.append(row);
        }

        catIdx++;
    }

    return result;
}

QVariantList EmojiProvider::getCategories(const QString &filter, int columns) {
    ensureLoaded();
    if (columns <= 0) columns = 11;

    const QString q = filter.trimmed().toLower();
    const QStringList terms = q.isEmpty() ? QStringList() : q.split(QLatin1Char(' '), Qt::SkipEmptyParts);

    QVariantList result;
    int currentRowIndex = 0;

    for (int catIdx = 0; catIdx < static_cast<int>(m_categories.size()); ++catIdx) {
        const auto &cat = m_categories[catIdx];
        int count = 0;
        if (terms.isEmpty()) {
            count = static_cast<int>(cat.emojis.size());
        } else {
            for (const auto &e : cat.emojis) {
                bool ok = true;
                for (const auto &t : terms) {
                    if (!e.nameLc.contains(t) && !e.subgroupLc.contains(t)) {
                        ok = false;
                        break;
                    }
                }
                if (ok) {
                    count++;
                }
            }
        }

        if (count > 0) {
            QVariantMap c;
            c.insert(QStringLiteral("name"), cat.name);
            c.insert(QStringLiteral("icon"), cat.icon);
            c.insert(QStringLiteral("count"), count);
            c.insert(QStringLiteral("rowIndex"), currentRowIndex);
            c.insert(QStringLiteral("categoryIndex"), catIdx);
            result.append(c);

            int rows = 1 + (count + columns - 1) / columns;
            currentRowIndex += rows;
        }
    }

    return result;
}

void EmojiProvider::selectEmoji(const QString &glyph, const QString &name, const QString &code) {
    emit emojiSelected(glyph, name, code);
}

void EmojiProvider::copyEmoji(const QString &glyph) {
    if (glyph.isEmpty()) return;
    if (auto *cb = QGuiApplication::clipboard()) {
        cb->setText(glyph);
    }
}

void EmojiProvider::pasteEmoji(const QString &glyph, bool shift) {
    if (glyph.isEmpty()) return;
    copyEmoji(glyph);
    executePaste(shift, 100);
}

void EmojiProvider::executePaste(bool shift, int delayMs) {
    if (m_isPasting.exchange(true)) {
        return;
    }

    auto *thread = QThread::create([this, shift, delayMs]() {
        struct PasteStateGuard {
            std::atomic<bool> &flag;
            ~PasteStateGuard() {
                flag = false;
            }
        } pasteGuard{m_isPasting};

        struct EisCleanupGuard {
            int cookie = 0;
            ~EisCleanupGuard() {
                if (cookie != 0) {
                    auto disconnectMsg = QDBusMessage::createMethodCall(
                        QStringLiteral("org.kde.KWin"),
                        QStringLiteral("/org/kde/KWin/EIS/RemoteDesktop"),
                        QStringLiteral("org.kde.KWin.EIS.RemoteDesktop"),
                        QStringLiteral("disconnect")
                    );
                    disconnectMsg << cookie;
                    QDBusConnection::sessionBus().send(disconnectMsg);
                }
            }
        } eisGuard;

        if (delayMs > 0) {
            std::this_thread::sleep_for(std::chrono::milliseconds(delayMs));
        }

        auto msg = QDBusMessage::createMethodCall(
            QStringLiteral("org.kde.KWin"),
            QStringLiteral("/org/kde/KWin/EIS/RemoteDesktop"),
            QStringLiteral("org.kde.KWin.EIS.RemoteDesktop"),
            QStringLiteral("connectToEIS")
        );
        msg << 1; // capabilities = 1 (keyboard)

        QDBusMessage reply = QDBusConnection::sessionBus().call(msg);
        if (reply.type() == QDBusMessage::ErrorMessage) {
            qWarning() << "KWin connectToEIS failed:" << reply.errorMessage();
            return;
        }

        const QList<QVariant> args = reply.arguments();
        if (args.count() < 2) {
            qWarning() << "connectToEIS returned unexpected argument count:" << args.count();
            return;
        }

        auto fdWrapper = qvariant_cast<QDBusUnixFileDescriptor>(args.at(0));
        eisGuard.cookie = args.at(1).toInt();

        if (!fdWrapper.isValid()) {
            qWarning() << "connectToEIS returned invalid file descriptor";
            return;
        }

        int rawFd = fdWrapper.fileDescriptor();
        int fd = ::dup(rawFd);
        if (fd < 0) {
            qWarning() << "Failed to dup KWin EIS socket fd:" << strerror(errno);
            return;
        }

        struct ei *ei = ei_new_sender(nullptr);
        if (!ei) {
            qWarning() << "Failed to create libei sender context";
            ::close(fd);
            return;
        }

        ei_configure_name(ei, "quickshell-emoji-paste");
        int ret = ei_setup_backend_fd(ei, fd);
        if (ret < 0) {
            qWarning() << "ei_setup_backend_fd failed:" << strerror(-ret);
            ei_unref(ei);
            ::close(fd);
            return;
        }

        std::vector<uint32_t> modKeys;
        uint32_t pasteKey = KEY_V;

        if (shift) {
            modKeys = {KEY_LEFTCTRL, KEY_LEFTSHIFT};
        } else {
            modKeys = {KEY_LEFTCTRL};
        }

        bool done = false;
        struct ei_device *kbdDev = nullptr;
        struct ei_ping *ping = nullptr;
        const auto startTime = std::chrono::steady_clock::now();

        while (!done) {
            ei_dispatch(ei);
            struct ei_event *event;
            while ((event = ei_get_event(ei))) {
                const auto type = ei_event_get_type(event);
                if (type == EI_EVENT_SEAT_ADDED) {
                    struct ei_seat *seat = ei_event_get_seat(event);
                    ei_seat_bind_capabilities(seat, EI_DEVICE_CAP_KEYBOARD, NULL);
                } else if (type == EI_EVENT_DEVICE_ADDED) {
                    struct ei_device *dev = ei_event_get_device(event);
                    if (ei_device_has_capability(dev, EI_DEVICE_CAP_KEYBOARD)) {
                        kbdDev = dev;
                    }
                } else if (type == EI_EVENT_DEVICE_RESUMED) {
                    struct ei_device *dev = ei_event_get_device(event);
                    if (kbdDev && dev == kbdDev && !ping) {
                        ei_device_start_emulating(dev, 1);
                        for (uint32_t mod : modKeys) {
                            ei_device_keyboard_key(dev, mod, true);
                        }
                        ei_device_frame(dev, ei_now(ei));

                        ei_device_keyboard_key(dev, pasteKey, true);
                        ei_device_frame(dev, ei_now(ei));
                        ei_device_keyboard_key(dev, pasteKey, false);
                        ei_device_frame(dev, ei_now(ei));

                        for (auto it = modKeys.rbegin(); it != modKeys.rend(); ++it) {
                            ei_device_keyboard_key(dev, *it, false);
                        }
                        ei_device_frame(dev, ei_now(ei));
                        ei_device_stop_emulating(dev);

                        ping = ei_new_ping(ei);
                        ei_ping(ping);
                    }
                } else if (type == EI_EVENT_PONG) {
                    done = true;
                } else if (type == EI_EVENT_DISCONNECT) {
                    done = true;
                }
                ei_event_unref(event);
            }

            if (!done) {
                auto elapsed = std::chrono::duration_cast<std::chrono::milliseconds>(std::chrono::steady_clock::now() - startTime).count();
                if (elapsed > 1000) {
                    break;
                }
                struct pollfd pfd = { ei_get_fd(ei), POLLIN, 0 };
                poll(&pfd, 1, 50);
            }
        }

        if (ping) {
            ei_ping_unref(ping);
        }
        ei_unref(ei);
        ::close(fd);
    });

    connect(thread, &QThread::finished, thread, &QObject::deleteLater);
    thread->start();
}

} // namespace qs::plugins
