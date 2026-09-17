#include "MediaManager.hpp"

#include <QDBusInterface>
#include <QDBusReply>

namespace qs::plugins::media {

class MediaManagerCore : public QObject {
    Q_OBJECT
public:
    static MediaManagerCore& instance() {
        static MediaManagerCore s_instance;
        return s_instance;
    }

    [[nodiscard]] QList<QObject*> playerListObjects() const {
        QList<QObject*> list;
        list.reserve(m_players.size());
        for (auto *p : m_players) {
            list.append(p);
        }
        return list;
    }

    [[nodiscard]] int playerCount() const { return m_players.size(); }

    [[nodiscard]] QObject* activePlayerObject() const { return m_activePlayer; }
    [[nodiscard]] MediaPlayer* activePlayer() const { return m_activePlayer; }

    [[nodiscard]] QObject* manualPlayerObject() const { return m_manualPlayer; }
    void setManualPlayer(QObject *player) {
        auto *mp = qobject_cast<MediaPlayer*>(player);
        if (m_manualPlayer != mp) {
            m_manualPlayer = mp;
            emit manualPlayerChanged();
            resolveActivePlayer();
        }
    }

    void selectPlayer(QObject *player) {
        setManualPlayer(player);
    }

    [[nodiscard]] bool hasPlayer() const { return m_activePlayer != nullptr; }
    [[nodiscard]] bool isPlaying() const { return m_activePlayer && m_activePlayer->isPlaying(); }

    [[nodiscard]] QString title() const {
        if (!m_activePlayer) return QStringLiteral("Media");
        const QString t = m_activePlayer->trackTitle();
        if (!t.isEmpty()) return t;
        const QString id = m_activePlayer->identity();
        return id.isEmpty() ? QStringLiteral("Media") : id;
    }

    [[nodiscard]] QString artist() const {
        return m_activePlayer ? m_activePlayer->trackArtist() : QString();
    }

    [[nodiscard]] QString album() const {
        return m_activePlayer ? m_activePlayer->trackAlbum() : QString();
    }

    [[nodiscard]] QString artUrl() const {
        return m_activePlayer ? m_activePlayer->trackArtUrl() : QString();
    }

    [[nodiscard]] double trackLength() const {
        return m_activePlayer ? m_activePlayer->length() : 0.0;
    }

    [[nodiscard]] double trackPos() const {
        return m_activePlayer ? m_activePlayer->position() : 0.0;
    }

    void setTrackPos(double posSec) {
        if (m_activePlayer) {
            m_activePlayer->setPosition(posSec);
        }
    }

    [[nodiscard]] double progress() const {
        return m_activePlayer ? m_activePlayer->progress() : 0.0;
    }

    [[nodiscard]] QString formattedPosition() const {
        return m_activePlayer ? m_activePlayer->formattedPosition() : QStringLiteral("0:00");
    }

    [[nodiscard]] QString formattedLength() const {
        return m_activePlayer ? m_activePlayer->formattedLength() : QStringLiteral("--:--");
    }

    [[nodiscard]] bool canControl() const {
        return m_activePlayer ? m_activePlayer->canControl() : false;
    }

    [[nodiscard]] bool canTogglePlaying() const {
        return m_activePlayer ? m_activePlayer->canTogglePlaying() : false;
    }

    [[nodiscard]] bool canGoNext() const {
        return m_activePlayer ? m_activePlayer->canGoNext() : false;
    }

    [[nodiscard]] bool canGoPrevious() const {
        return m_activePlayer ? m_activePlayer->canGoPrevious() : false;
    }

    [[nodiscard]] bool canSeek() const {
        return m_activePlayer ? m_activePlayer->canSeek() : false;
    }

    [[nodiscard]] bool shuffle() const {
        return m_activePlayer ? m_activePlayer->shuffle() : false;
    }

    [[nodiscard]] bool shuffleSupported() const {
        return m_activePlayer ? m_activePlayer->shuffleSupported() : false;
    }

    [[nodiscard]] int loopState() const {
        return m_activePlayer ? m_activePlayer->loopStateInt() : 0;
    }

    [[nodiscard]] bool loopSupported() const {
        return m_activePlayer ? m_activePlayer->loopSupported() : false;
    }

    void playPause() {
        if (m_activePlayer) m_activePlayer->togglePlaying();
    }

    void togglePlaying() {
        if (m_activePlayer) m_activePlayer->togglePlaying();
    }

    void play() {
        if (m_activePlayer) m_activePlayer->play();
    }

    void pause() {
        if (m_activePlayer) m_activePlayer->pause();
    }

    void next() {
        if (m_activePlayer) m_activePlayer->next();
    }

    void previous() {
        if (m_activePlayer) m_activePlayer->previous();
    }

    void stop() {
        if (m_activePlayer) m_activePlayer->stop();
    }

    void seek(double offsetSec) {
        if (m_activePlayer) m_activePlayer->seek(offsetSec);
    }

    void setShuffle(bool enable) {
        if (m_activePlayer) m_activePlayer->setShuffle(enable);
    }

    void setLoopState(int state) {
        if (m_activePlayer) m_activePlayer->setLoopState(state);
    }

    void addTrackingSubscriber() {
        ++m_trackingSubscribers;
        updateClockTimer();
    }

    void removeTrackingSubscriber() {
        --m_trackingSubscribers;
        if (m_trackingSubscribers < 0) {
            m_trackingSubscribers = 0;
        }
        updateClockTimer();
    }

signals:
    void playersChanged();
    void activePlayerChanged();
    void manualPlayerChanged();
    void activeStateChanged();
    void trackChanged();
    void positionTick();
    void capabilitiesChanged();
    void shuffleChanged();
    void loopStateChanged();

private slots:
    void onServiceRegistered(const QString &service) {
        if (service.startsWith(QLatin1String("org.mpris.MediaPlayer2."))) {
            addPlayer(service);
        }
    }

    void onServiceUnregistered(const QString &service) {
        if (service.startsWith(QLatin1String("org.mpris.MediaPlayer2."))) {
            removePlayer(service);
        }
    }

    void onServiceOwnerChanged(const QString &service, const QString &oldOwner, const QString &newOwner) {
        if (!service.startsWith(QLatin1String("org.mpris.MediaPlayer2."))) {
            return;
        }

        if (newOwner.isEmpty()) {
            removePlayer(service);
        } else if (oldOwner.isEmpty()) {
            addPlayer(service);
        } else {
            removePlayer(service);
            addPlayer(service);
        }
    }

    void onPlayerPlaybackStateChanged() {
        resolveActivePlayer();
        auto *senderPlayer = qobject_cast<MediaPlayer*>(sender());
        if (senderPlayer == m_activePlayer) {
            emit activeStateChanged();
            emit capabilitiesChanged();
            updateClockTimer();
        }
    }

    void onPlayerMetadataChanged() {
        auto *senderPlayer = qobject_cast<MediaPlayer*>(sender());
        if (senderPlayer == m_activePlayer) {
            emit trackChanged();
            emit positionTick();
        }
    }

    void onPlayerIdentityChanged() {
        emit playersChanged();
        if (sender() == m_activePlayer) {
            emit trackChanged();
        }
    }

    void onPlayerCapabilitiesChanged() {
        if (sender() == m_activePlayer) {
            emit capabilitiesChanged();
        }
    }

    void onPlayerPositionChanged() {
        if (sender() == m_activePlayer) {
            emit positionTick();
        }
    }

    void onClockTick() {
        if (m_activePlayer && m_activePlayer->isPlaying()) {
            emit positionTick();
        }
    }

private:
    MediaManagerCore() {
        m_clockTimer = new QTimer(this);
        m_clockTimer->setInterval(100);
        connect(m_clockTimer, &QTimer::timeout, this, &MediaManagerCore::onClockTick);

        auto bus = QDBusConnection::sessionBus();
        if (bus.isConnected()) {
            m_watcher = new QDBusServiceWatcher(this);
            m_watcher->setConnection(bus);
            m_watcher->setWatchMode(QDBusServiceWatcher::WatchForOwnerChange);
            m_watcher->addWatchedService(QStringLiteral("org.mpris.MediaPlayer2.*"));

            connect(m_watcher, &QDBusServiceWatcher::serviceRegistered, this, &MediaManagerCore::onServiceRegistered);
            connect(m_watcher, &QDBusServiceWatcher::serviceUnregistered, this, &MediaManagerCore::onServiceUnregistered);
            connect(m_watcher, &QDBusServiceWatcher::serviceOwnerChanged, this, &MediaManagerCore::onServiceOwnerChanged);

            discoverInitialServices();
        }
    }

    ~MediaManagerCore() override {
        if (m_clockTimer) {
            m_clockTimer->stop();
        }
    }

    void discoverInitialServices() {
        auto bus = QDBusConnection::sessionBus();
        if (!bus.isConnected()) {
            return;
        }

        QDBusInterface dbusIface(
            QStringLiteral("org.freedesktop.DBus"),
            QStringLiteral("/org/freedesktop/DBus"),
            QStringLiteral("org.freedesktop.DBus"),
            bus
        );

        QDBusReply<QStringList> reply = dbusIface.call(QStringLiteral("ListNames"));
        if (reply.isValid()) {
            const auto names = reply.value();
            for (const QString &name : names) {
                if (name.startsWith(QLatin1String("org.mpris.MediaPlayer2."))) {
                    addPlayer(name);
                }
            }
        }

        resolveActivePlayer();
    }

    void addPlayer(const QString &service) {
        for (const auto *p : m_players) {
            if (p->service() == service) {
                return;
            }
        }

        auto *player = new MediaPlayer(service, this);
        connect(player, &MediaPlayer::playbackStateChanged, this, &MediaManagerCore::onPlayerPlaybackStateChanged);
        connect(player, &MediaPlayer::metadataChanged, this, &MediaManagerCore::onPlayerMetadataChanged);
        connect(player, &MediaPlayer::identityChanged, this, &MediaManagerCore::onPlayerIdentityChanged);
        connect(player, &MediaPlayer::capabilitiesChanged, this, &MediaManagerCore::onPlayerCapabilitiesChanged);
        connect(player, &MediaPlayer::positionChangedSignal, this, &MediaManagerCore::onPlayerPositionChanged);
        connect(player, &MediaPlayer::shuffleChanged, this, &MediaManagerCore::shuffleChanged);
        connect(player, &MediaPlayer::loopStateChanged, this, &MediaManagerCore::loopStateChanged);

        m_players.append(player);
        emit playersChanged();
        resolveActivePlayer();
    }

    void removePlayer(const QString &service) {
        for (int i = 0; i < m_players.size(); ++i) {
            if (m_players[i]->service() == service) {
                MediaPlayer *p = m_players.takeAt(i);
                if (m_manualPlayer == p) {
                    m_manualPlayer = nullptr;
                    emit manualPlayerChanged();
                }
                if (m_activePlayer == p) {
                    m_activePlayer = nullptr;
                }
                p->deleteLater();
                emit playersChanged();
                resolveActivePlayer();
                return;
            }
        }
    }

    void resolveActivePlayer() {
        MediaPlayer *best = nullptr;

        // 1. Manual selection if still valid
        if (m_manualPlayer && m_players.contains(m_manualPlayer)) {
            best = m_manualPlayer;
        }

        // 2. First playing player
        if (!best) {
            for (auto *p : m_players) {
                if (p->playbackState() == PlaybackState::Playing) {
                    best = p;
                    break;
                }
            }
        }

        // 3. First paused player
        if (!best) {
            for (auto *p : m_players) {
                if (p->playbackState() == PlaybackState::Paused) {
                    best = p;
                    break;
                }
            }
        }

        // 4. First player in list
        if (!best && !m_players.isEmpty()) {
            best = m_players.first();
        }

        if (best != m_activePlayer) {
            m_activePlayer = best;
            emit activePlayerChanged();
            emit activeStateChanged();
            emit trackChanged();
            emit capabilitiesChanged();
            emit positionTick();
            emit shuffleChanged();
            emit loopStateChanged();
            updateClockTimer();
        }
    }

    void updateClockTimer() {
        if (m_trackingSubscribers > 0 && m_activePlayer && m_activePlayer->isPlaying()) {
            if (!m_clockTimer->isActive()) {
                m_clockTimer->start();
            }
        } else {
            if (m_clockTimer->isActive()) {
                m_clockTimer->stop();
            }
        }
    }

    QList<MediaPlayer*> m_players;
    MediaPlayer *m_activePlayer{nullptr};
    MediaPlayer *m_manualPlayer{nullptr};

    QDBusServiceWatcher *m_watcher{nullptr};
    QTimer *m_clockTimer{nullptr};
    int m_trackingSubscribers{0};
};

// --- MediaManager ---

MediaManager::MediaManager(QObject *parent)
    : QObject(parent)
{
    auto &core = MediaManagerCore::instance();
    connect(&core, &MediaManagerCore::playersChanged, this, &MediaManager::playersChanged);
    connect(&core, &MediaManagerCore::activePlayerChanged, this, &MediaManager::activePlayerChanged);
    connect(&core, &MediaManagerCore::manualPlayerChanged, this, &MediaManager::manualPlayerChanged);
    connect(&core, &MediaManagerCore::activeStateChanged, this, &MediaManager::activeStateChanged);
    connect(&core, &MediaManagerCore::trackChanged, this, &MediaManager::trackChanged);
    connect(&core, &MediaManagerCore::positionTick, this, &MediaManager::positionTick);
    connect(&core, &MediaManagerCore::capabilitiesChanged, this, &MediaManager::capabilitiesChanged);
    connect(&core, &MediaManagerCore::shuffleChanged, this, &MediaManager::shuffleChanged);
    connect(&core, &MediaManagerCore::loopStateChanged, this, &MediaManager::loopStateChanged);
}

MediaManager::~MediaManager() {
    if (m_positionTracking) {
        MediaManagerCore::instance().removeTrackingSubscriber();
    }
}

void MediaManager::setRunning(bool running) {
    if (m_running != running) {
        m_running = running;
        if (!m_running && m_positionTracking) {
            setPositionTracking(false);
        }
        emit runningChanged();
    }
}

void MediaManager::setPositionTracking(bool tracking) {
    if (m_positionTracking != tracking) {
        m_positionTracking = tracking;
        auto &core = MediaManagerCore::instance();
        if (m_positionTracking) {
            core.addTrackingSubscriber();
            emit positionTick();
        } else {
            core.removeTrackingSubscriber();
        }
        emit positionTrackingChanged();
    }
}

QList<QObject*> MediaManager::playerListObjects() const {
    return m_running ? MediaManagerCore::instance().playerListObjects() : QList<QObject*>{};
}

int MediaManager::playerCount() const {
    return m_running ? MediaManagerCore::instance().playerCount() : 0;
}

QObject* MediaManager::activePlayerObject() const {
    return m_running ? MediaManagerCore::instance().activePlayerObject() : nullptr;
}

MediaPlayer* MediaManager::activePlayer() const {
    return m_running ? MediaManagerCore::instance().activePlayer() : nullptr;
}

QObject* MediaManager::manualPlayerObject() const {
    return m_running ? MediaManagerCore::instance().manualPlayerObject() : nullptr;
}

void MediaManager::setManualPlayer(QObject *player) {
    if (m_running) {
        MediaManagerCore::instance().setManualPlayer(player);
    }
}

void MediaManager::selectPlayer(QObject *player) {
    if (m_running) {
        MediaManagerCore::instance().selectPlayer(player);
    }
}

bool MediaManager::hasPlayer() const {
    return m_running && MediaManagerCore::instance().hasPlayer();
}

bool MediaManager::isPlaying() const {
    return m_running && MediaManagerCore::instance().isPlaying();
}

QString MediaManager::title() const {
    return m_running ? MediaManagerCore::instance().title() : QStringLiteral("Media");
}

QString MediaManager::artist() const {
    return m_running ? MediaManagerCore::instance().artist() : QString();
}

QString MediaManager::album() const {
    return m_running ? MediaManagerCore::instance().album() : QString();
}

QString MediaManager::artUrl() const {
    return m_running ? MediaManagerCore::instance().artUrl() : QString();
}

double MediaManager::trackLength() const {
    return m_running ? MediaManagerCore::instance().trackLength() : 0.0;
}

double MediaManager::trackPos() const {
    return m_running ? MediaManagerCore::instance().trackPos() : 0.0;
}

void MediaManager::setTrackPos(double posSec) {
    if (m_running) {
        MediaManagerCore::instance().setTrackPos(posSec);
    }
}

double MediaManager::progress() const {
    return m_running ? MediaManagerCore::instance().progress() : 0.0;
}

QString MediaManager::formattedPosition() const {
    return m_running ? MediaManagerCore::instance().formattedPosition() : QStringLiteral("0:00");
}

QString MediaManager::formattedLength() const {
    return m_running ? MediaManagerCore::instance().formattedLength() : QStringLiteral("--:--");
}

bool MediaManager::canControl() const {
    return m_running && MediaManagerCore::instance().canControl();
}

bool MediaManager::canTogglePlaying() const {
    return m_running && MediaManagerCore::instance().canTogglePlaying();
}

bool MediaManager::canGoNext() const {
    return m_running && MediaManagerCore::instance().canGoNext();
}

bool MediaManager::canGoPrevious() const {
    return m_running && MediaManagerCore::instance().canGoPrevious();
}

bool MediaManager::canSeek() const {
    return m_running && MediaManagerCore::instance().canSeek();
}

bool MediaManager::shuffle() const {
    return m_running && MediaManagerCore::instance().shuffle();
}

bool MediaManager::shuffleSupported() const {
    return m_running && MediaManagerCore::instance().shuffleSupported();
}

int MediaManager::loopState() const {
    return m_running ? MediaManagerCore::instance().loopState() : 0;
}

bool MediaManager::loopSupported() const {
    return m_running && MediaManagerCore::instance().loopSupported();
}

void MediaManager::playPause() {
    if (m_running) MediaManagerCore::instance().playPause();
}

void MediaManager::togglePlaying() {
    if (m_running) MediaManagerCore::instance().togglePlaying();
}

void MediaManager::play() {
    if (m_running) MediaManagerCore::instance().play();
}

void MediaManager::pause() {
    if (m_running) MediaManagerCore::instance().pause();
}

void MediaManager::next() {
    if (m_running) MediaManagerCore::instance().next();
}

void MediaManager::previous() {
    if (m_running) MediaManagerCore::instance().previous();
}

void MediaManager::stop() {
    if (m_running) MediaManagerCore::instance().stop();
}

void MediaManager::seek(double offsetSec) {
    if (m_running) MediaManagerCore::instance().seek(offsetSec);
}

void MediaManager::setShuffle(bool enable) {
    if (m_running) MediaManagerCore::instance().setShuffle(enable);
}

void MediaManager::setLoopState(int state) {
    if (m_running) MediaManagerCore::instance().setLoopState(state);
}

} // namespace qs::plugins::media

#include "MediaManager.moc"
