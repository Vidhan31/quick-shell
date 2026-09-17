#include "MediaManager.hpp"

#include <QDBusInterface>
#include <QDBusReply>

namespace qs::plugins::media {

MediaManager::MediaManager(QObject *parent)
    : QObject(parent)
{
    m_clockTimer = new QTimer(this);
    m_clockTimer->setInterval(100);
    connect(m_clockTimer, &QTimer::timeout, this, &MediaManager::onClockTick);

    auto bus = QDBusConnection::sessionBus();
    if (bus.isConnected()) {
        m_watcher = new QDBusServiceWatcher(this);
        m_watcher->setConnection(bus);
        m_watcher->setWatchMode(QDBusServiceWatcher::WatchForOwnerChange);
        m_watcher->addWatchedService(QStringLiteral("org.mpris.MediaPlayer2.*"));

        connect(m_watcher, &QDBusServiceWatcher::serviceRegistered, this, &MediaManager::onServiceRegistered);
        connect(m_watcher, &QDBusServiceWatcher::serviceUnregistered, this, &MediaManager::onServiceUnregistered);
        connect(m_watcher, &QDBusServiceWatcher::serviceOwnerChanged, this, &MediaManager::onServiceOwnerChanged);

        discoverInitialServices();
    }
}

MediaManager::~MediaManager() {
    if (m_clockTimer) {
        m_clockTimer->stop();
    }
}

void MediaManager::discoverInitialServices() {
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

void MediaManager::addPlayer(const QString &service) {
    for (const auto *p : m_players) {
        if (p->service() == service) {
            return;
        }
    }

    auto *player = new MediaPlayer(service, this);
    connect(player, &MediaPlayer::playbackStateChanged, this, &MediaManager::onPlayerPlaybackStateChanged);
    connect(player, &MediaPlayer::metadataChanged, this, &MediaManager::onPlayerMetadataChanged);
    connect(player, &MediaPlayer::identityChanged, this, &MediaManager::onPlayerIdentityChanged);
    connect(player, &MediaPlayer::capabilitiesChanged, this, &MediaManager::onPlayerCapabilitiesChanged);
    connect(player, &MediaPlayer::positionChangedSignal, this, &MediaManager::onPlayerPositionChanged);
    connect(player, &MediaPlayer::shuffleChanged, this, &MediaManager::shuffleChanged);
    connect(player, &MediaPlayer::loopStateChanged, this, &MediaManager::loopStateChanged);

    m_players.append(player);
    emit playersChanged();
    resolveActivePlayer();
}

void MediaManager::removePlayer(const QString &service) {
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

void MediaManager::onServiceRegistered(const QString &service) {
    if (service.startsWith(QLatin1String("org.mpris.MediaPlayer2."))) {
        addPlayer(service);
    }
}

void MediaManager::onServiceUnregistered(const QString &service) {
    if (service.startsWith(QLatin1String("org.mpris.MediaPlayer2."))) {
        removePlayer(service);
    }
}

void MediaManager::onServiceOwnerChanged(const QString &service, const QString &oldOwner, const QString &newOwner) {
    if (!service.startsWith(QLatin1String("org.mpris.MediaPlayer2."))) {
        return;
    }

    if (newOwner.isEmpty()) {
        removePlayer(service);
    } else if (oldOwner.isEmpty()) {
        addPlayer(service);
    } else {
        // Owner changed, re-create player
        removePlayer(service);
        addPlayer(service);
    }
}

void MediaManager::resolveActivePlayer() {
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

void MediaManager::updateClockTimer() {
    if (m_activePlayer && m_activePlayer->isPlaying()) {
        if (!m_clockTimer->isActive()) {
            m_clockTimer->start();
        }
    } else {
        if (m_clockTimer->isActive()) {
            m_clockTimer->stop();
        }
    }
}

void MediaManager::onClockTick() {
    if (m_activePlayer && m_activePlayer->isPlaying()) {
        emit positionTick();
    }
}

void MediaManager::onPlayerPlaybackStateChanged() {
    resolveActivePlayer();
    auto *senderPlayer = qobject_cast<MediaPlayer*>(sender());
    if (senderPlayer == m_activePlayer) {
        emit activeStateChanged();
        emit capabilitiesChanged();
        updateClockTimer();
    }
}

void MediaManager::onPlayerMetadataChanged() {
    auto *senderPlayer = qobject_cast<MediaPlayer*>(sender());
    if (senderPlayer == m_activePlayer) {
        emit trackChanged();
        emit positionTick();
    }
}

void MediaManager::onPlayerIdentityChanged() {
    emit playersChanged();
    if (sender() == m_activePlayer) {
        emit trackChanged();
    }
}

void MediaManager::onPlayerCapabilitiesChanged() {
    if (sender() == m_activePlayer) {
        emit capabilitiesChanged();
    }
}

void MediaManager::onPlayerPositionChanged() {
    if (sender() == m_activePlayer) {
        emit positionTick();
    }
}

QList<QObject*> MediaManager::playerListObjects() const {
    QList<QObject*> list;
    list.reserve(m_players.size());
    for (auto *p : m_players) {
        list.append(p);
    }
    return list;
}

void MediaManager::setManualPlayer(QObject *player) {
    auto *mp = qobject_cast<MediaPlayer*>(player);
    if (m_manualPlayer != mp) {
        m_manualPlayer = mp;
        emit manualPlayerChanged();
        resolveActivePlayer();
    }
}

void MediaManager::selectPlayer(QObject *player) {
    setManualPlayer(player);
}

QString MediaManager::title() const {
    if (!m_activePlayer) return QStringLiteral("Media");
    const QString t = m_activePlayer->trackTitle();
    if (!t.isEmpty()) return t;
    const QString id = m_activePlayer->identity();
    return id.isEmpty() ? QStringLiteral("Media") : id;
}

QString MediaManager::artist() const {
    return m_activePlayer ? m_activePlayer->trackArtist() : QString();
}

QString MediaManager::album() const {
    return m_activePlayer ? m_activePlayer->trackAlbum() : QString();
}

QString MediaManager::artUrl() const {
    return m_activePlayer ? m_activePlayer->trackArtUrl() : QString();
}

double MediaManager::trackLength() const {
    return m_activePlayer ? m_activePlayer->length() : 0.0;
}

double MediaManager::trackPos() const {
    return m_activePlayer ? m_activePlayer->position() : 0.0;
}

void MediaManager::setTrackPos(double posSec) {
    if (m_activePlayer) {
        m_activePlayer->setPosition(posSec);
    }
}

double MediaManager::progress() const {
    return m_activePlayer ? m_activePlayer->progress() : 0.0;
}

QString MediaManager::formattedPosition() const {
    return m_activePlayer ? m_activePlayer->formattedPosition() : QStringLiteral("0:00");
}

QString MediaManager::formattedLength() const {
    return m_activePlayer ? m_activePlayer->formattedLength() : QStringLiteral("--:--");
}

bool MediaManager::canControl() const {
    return m_activePlayer ? m_activePlayer->canControl() : false;
}

bool MediaManager::canTogglePlaying() const {
    return m_activePlayer ? m_activePlayer->canTogglePlaying() : false;
}

bool MediaManager::canGoNext() const {
    return m_activePlayer ? m_activePlayer->canGoNext() : false;
}

bool MediaManager::canGoPrevious() const {
    return m_activePlayer ? m_activePlayer->canGoPrevious() : false;
}

bool MediaManager::canSeek() const {
    return m_activePlayer ? m_activePlayer->canSeek() : false;
}

bool MediaManager::shuffle() const {
    return m_activePlayer ? m_activePlayer->shuffle() : false;
}

bool MediaManager::shuffleSupported() const {
    return m_activePlayer ? m_activePlayer->shuffleSupported() : false;
}

int MediaManager::loopState() const {
    return m_activePlayer ? m_activePlayer->loopStateInt() : 0;
}

bool MediaManager::loopSupported() const {
    return m_activePlayer ? m_activePlayer->loopSupported() : false;
}

void MediaManager::playPause() {
    if (m_activePlayer) m_activePlayer->togglePlaying();
}

void MediaManager::togglePlaying() {
    if (m_activePlayer) m_activePlayer->togglePlaying();
}

void MediaManager::play() {
    if (m_activePlayer) m_activePlayer->play();
}

void MediaManager::pause() {
    if (m_activePlayer) m_activePlayer->pause();
}

void MediaManager::next() {
    if (m_activePlayer) m_activePlayer->next();
}

void MediaManager::previous() {
    if (m_activePlayer) m_activePlayer->previous();
}

void MediaManager::stop() {
    if (m_activePlayer) m_activePlayer->stop();
}

void MediaManager::seek(double offsetSec) {
    if (m_activePlayer) m_activePlayer->seek(offsetSec);
}

void MediaManager::setShuffle(bool enable) {
    if (m_activePlayer) m_activePlayer->setShuffle(enable);
}

void MediaManager::setLoopState(int state) {
    if (m_activePlayer) m_activePlayer->setLoopState(state);
}

} // namespace qs::plugins::media
