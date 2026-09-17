#include "MediaPlayer.hpp"

#include <QDBusArgument>
#include <QDBusInterface>
#include <QDBusReply>
#include <algorithm>

namespace qs::plugins::media {

MediaPlayer::MediaPlayer(const QString &service, QObject *parent)
    : QObject(parent)
    , m_service(service)
{
    // Derive sensible fallback identity from D-Bus service name
    // e.g. "org.mpris.MediaPlayer2.brave.instance79615" -> "Brave"
    QString name = service;
    if (name.startsWith(QLatin1String("org.mpris.MediaPlayer2."))) {
        name.remove(0, 23);
    }
    const int dotIdx = name.indexOf(QLatin1Char('.'));
    if (dotIdx > 0) {
        name = name.left(dotIdx);
    }
    if (!name.isEmpty()) {
        name[0] = name[0].toUpper();
    }
    m_identity = name.isEmpty() ? QStringLiteral("Player") : name;
    m_lastPositionTime = std::chrono::steady_clock::now();

    auto bus = QDBusConnection::sessionBus();
    if (bus.isConnected()) {
        bus.connect(m_service,
                    QStringLiteral("/org/mpris/MediaPlayer2"),
                    QStringLiteral("org.freedesktop.DBus.Properties"),
                    QStringLiteral("PropertiesChanged"),
                    this,
                    SLOT(onPropertiesChanged(QString,QVariantMap,QStringList)));

        bus.connect(m_service,
                    QStringLiteral("/org/mpris/MediaPlayer2"),
                    QStringLiteral("org.mpris.MediaPlayer2.Player"),
                    QStringLiteral("Seeked"),
                    this,
                    SLOT(onSeeked(qint64)));
    }

    initProperties();
}

MediaPlayer::~MediaPlayer() {
    auto bus = QDBusConnection::sessionBus();
    if (bus.isConnected()) {
        bus.disconnect(m_service,
                       QStringLiteral("/org/mpris/MediaPlayer2"),
                       QStringLiteral("org.freedesktop.DBus.Properties"),
                       QStringLiteral("PropertiesChanged"),
                       this,
                       SLOT(onPropertiesChanged(QString,QVariantMap,QStringList)));

        bus.disconnect(m_service,
                       QStringLiteral("/org/mpris/MediaPlayer2"),
                       QStringLiteral("org.mpris.MediaPlayer2.Player"),
                       QStringLiteral("Seeked"),
                       this,
                       SLOT(onSeeked(qint64)));
    }
}

void MediaPlayer::initProperties() {
    auto bus = QDBusConnection::sessionBus();
    if (!bus.isConnected()) {
        return;
    }

    // 1. Root interface properties (Identity, etc.)
    QDBusMessage msgRoot = QDBusMessage::createMethodCall(
        m_service,
        QStringLiteral("/org/mpris/MediaPlayer2"),
        QStringLiteral("org.freedesktop.DBus.Properties"),
        QStringLiteral("GetAll")
    );
    msgRoot << QStringLiteral("org.mpris.MediaPlayer2");
    auto asyncRoot = bus.asyncCall(msgRoot);
    auto *rootWatcher = new QDBusPendingCallWatcher(asyncRoot, this);
    connect(rootWatcher, &QDBusPendingCallWatcher::finished, this, &MediaPlayer::onGetAllRootFinished);

    // 2. Player interface properties (PlaybackStatus, Metadata, etc.)
    QDBusMessage msgPlayer = QDBusMessage::createMethodCall(
        m_service,
        QStringLiteral("/org/mpris/MediaPlayer2"),
        QStringLiteral("org.freedesktop.DBus.Properties"),
        QStringLiteral("GetAll")
    );
    msgPlayer << QStringLiteral("org.mpris.MediaPlayer2.Player");
    auto asyncPlayer = bus.asyncCall(msgPlayer);
    auto *playerWatcher = new QDBusPendingCallWatcher(asyncPlayer, this);
    connect(playerWatcher, &QDBusPendingCallWatcher::finished, this, &MediaPlayer::onGetAllPlayerFinished);
}

void MediaPlayer::onGetAllRootFinished(QDBusPendingCallWatcher *watcher) {
    watcher->deleteLater();
    QDBusPendingReply<QVariantMap> reply = *watcher;
    if (!reply.isValid()) {
        return;
    }

    const QVariantMap props = reply.value();
    if (props.contains(QStringLiteral("Identity"))) {
        const QString ident = props.value(QStringLiteral("Identity")).toString();
        if (!ident.isEmpty() && ident != m_identity) {
            m_identity = ident;
            emit identityChanged();
        }
    }
}

void MediaPlayer::onGetAllPlayerFinished(QDBusPendingCallWatcher *watcher) {
    watcher->deleteLater();
    QDBusPendingReply<QVariantMap> reply = *watcher;
    if (!reply.isValid()) {
        return;
    }

    const QVariantMap props = reply.value();
    if (props.contains(QStringLiteral("PlaybackStatus"))) {
        parsePlaybackStatus(props.value(QStringLiteral("PlaybackStatus")).toString());
    }

    if (props.contains(QStringLiteral("Rate"))) {
        m_rate = props.value(QStringLiteral("Rate")).toDouble();
        if (m_rate <= 0.0) m_rate = 1.0;
    }

    if (props.contains(QStringLiteral("Metadata"))) {
        const QVariant metaVar = props.value(QStringLiteral("Metadata"));
        if (metaVar.canConvert<QDBusArgument>()) {
            QDBusArgument arg = metaVar.value<QDBusArgument>();
            QVariantMap metaMap;
            arg >> metaMap;
            applyMetadata(metaMap);
        } else if (metaVar.canConvert<QVariantMap>()) {
            applyMetadata(metaVar.toMap());
        }
    }

    if (props.contains(QStringLiteral("Position"))) {
        const qint64 posUs = props.value(QStringLiteral("Position")).toLongLong();
        m_basePosition = static_cast<double>(posUs) / 1'000'000.0;
        m_lastPositionTime = std::chrono::steady_clock::now();
        emit positionChanged();
    }

    if (props.contains(QStringLiteral("Volume"))) {
        m_volume = props.value(QStringLiteral("Volume")).toDouble();
        emit volumeChanged();
    }

    if (props.contains(QStringLiteral("Shuffle"))) {
        m_shuffle = props.value(QStringLiteral("Shuffle")).toBool();
        m_shuffleSupported = true;
        emit shuffleChanged();
        emit shuffleSupportedChanged();
    }

    if (props.contains(QStringLiteral("LoopStatus"))) {
        parseLoopStatus(props.value(QStringLiteral("LoopStatus")).toString());
        m_loopSupported = true;
        emit loopSupportedChanged();
    }

    bool capChanged = false;
    if (props.contains(QStringLiteral("CanControl"))) {
        m_canControl = props.value(QStringLiteral("CanControl")).toBool();
        capChanged = true;
    }
    if (props.contains(QStringLiteral("CanPlay"))) {
        m_canPlay = props.value(QStringLiteral("CanPlay")).toBool();
        capChanged = true;
    }
    if (props.contains(QStringLiteral("CanPause"))) {
        m_canPause = props.value(QStringLiteral("CanPause")).toBool();
        capChanged = true;
    }
    if (props.contains(QStringLiteral("CanGoNext"))) {
        m_canGoNext = props.value(QStringLiteral("CanGoNext")).toBool();
        capChanged = true;
    }
    if (props.contains(QStringLiteral("CanGoPrevious"))) {
        m_canGoPrevious = props.value(QStringLiteral("CanGoPrevious")).toBool();
        capChanged = true;
    }
    if (props.contains(QStringLiteral("CanSeek"))) {
        m_canSeek = props.value(QStringLiteral("CanSeek")).toBool();
        capChanged = true;
    }

    if (capChanged) {
        emit capabilitiesChanged();
    }
}

void MediaPlayer::onPropertiesChanged(const QString &interfaceName, const QVariantMap &changedProps, const QStringList &/*invalidatedProps*/) {
    if (interfaceName == QStringLiteral("org.mpris.MediaPlayer2")) {
        if (changedProps.contains(QStringLiteral("Identity"))) {
            const QString ident = changedProps.value(QStringLiteral("Identity")).toString();
            if (!ident.isEmpty() && ident != m_identity) {
                m_identity = ident;
                emit identityChanged();
            }
        }
        return;
    }

    if (interfaceName != QStringLiteral("org.mpris.MediaPlayer2.Player")) {
        return;
    }

    bool capChanged = false;

    if (changedProps.contains(QStringLiteral("Rate"))) {
        m_rate = changedProps.value(QStringLiteral("Rate")).toDouble();
        if (m_rate <= 0.0) m_rate = 1.0;
    }

    if (changedProps.contains(QStringLiteral("PlaybackStatus"))) {
        parsePlaybackStatus(changedProps.value(QStringLiteral("PlaybackStatus")).toString());
    }

    if (changedProps.contains(QStringLiteral("Metadata"))) {
        const QVariant metaVar = changedProps.value(QStringLiteral("Metadata"));
        if (metaVar.canConvert<QDBusArgument>()) {
            QDBusArgument arg = metaVar.value<QDBusArgument>();
            QVariantMap metaMap;
            arg >> metaMap;
            applyMetadata(metaMap);
        } else if (metaVar.canConvert<QVariantMap>()) {
            applyMetadata(metaVar.toMap());
        }
    }

    if (changedProps.contains(QStringLiteral("Position"))) {
        const qint64 posUs = changedProps.value(QStringLiteral("Position")).toLongLong();
        m_basePosition = static_cast<double>(posUs) / 1'000'000.0;
        m_lastPositionTime = std::chrono::steady_clock::now();
        emit positionChanged();
    }

    if (changedProps.contains(QStringLiteral("Volume"))) {
        m_volume = changedProps.value(QStringLiteral("Volume")).toDouble();
        emit volumeChanged();
    }

    if (changedProps.contains(QStringLiteral("Shuffle"))) {
        m_shuffle = changedProps.value(QStringLiteral("Shuffle")).toBool();
        m_shuffleSupported = true;
        emit shuffleChanged();
        emit shuffleSupportedChanged();
    }

    if (changedProps.contains(QStringLiteral("LoopStatus"))) {
        parseLoopStatus(changedProps.value(QStringLiteral("LoopStatus")).toString());
        m_loopSupported = true;
        emit loopSupportedChanged();
    }

    if (changedProps.contains(QStringLiteral("CanControl"))) {
        m_canControl = changedProps.value(QStringLiteral("CanControl")).toBool();
        capChanged = true;
    }
    if (changedProps.contains(QStringLiteral("CanPlay"))) {
        m_canPlay = changedProps.value(QStringLiteral("CanPlay")).toBool();
        capChanged = true;
    }
    if (changedProps.contains(QStringLiteral("CanPause"))) {
        m_canPause = changedProps.value(QStringLiteral("CanPause")).toBool();
        capChanged = true;
    }
    if (changedProps.contains(QStringLiteral("CanGoNext"))) {
        m_canGoNext = changedProps.value(QStringLiteral("CanGoNext")).toBool();
        capChanged = true;
    }
    if (changedProps.contains(QStringLiteral("CanGoPrevious"))) {
        m_canGoPrevious = changedProps.value(QStringLiteral("CanGoPrevious")).toBool();
        capChanged = true;
    }
    if (changedProps.contains(QStringLiteral("CanSeek"))) {
        m_canSeek = changedProps.value(QStringLiteral("CanSeek")).toBool();
        capChanged = true;
    }

    if (capChanged) {
        emit capabilitiesChanged();
    }
}

void MediaPlayer::onSeeked(qint64 positionUs) {
    m_basePosition = static_cast<double>(positionUs) / 1'000'000.0;
    m_lastPositionTime = std::chrono::steady_clock::now();
    emit positionChanged();
}

void MediaPlayer::parsePlaybackStatus(const QString &status) {
    PlaybackState newState = PlaybackState::Stopped;
    if (status == QStringLiteral("Playing")) {
        newState = PlaybackState::Playing;
    } else if (status == QStringLiteral("Paused")) {
        newState = PlaybackState::Paused;
    }

    // Freeze base position at transition
    if (m_playbackState == PlaybackState::Playing && newState != PlaybackState::Playing) {
        m_basePosition = position();
    }
    m_lastPositionTime = std::chrono::steady_clock::now();

    if (m_playbackState != newState) {
        m_playbackState = newState;
        emit playbackStateChanged();
        emit positionChanged();
    }
}

void MediaPlayer::parseLoopStatus(const QString &status) {
    LoopState newLoop = LoopState::None;
    if (status == QStringLiteral("Track")) {
        newLoop = LoopState::Track;
    } else if (status == QStringLiteral("Playlist")) {
        newLoop = LoopState::Playlist;
    }
    if (m_loopState != newLoop) {
        m_loopState = newLoop;
        emit loopStateChanged();
    }
}

void MediaPlayer::applyMetadata(const QVariantMap &meta) {
    if (meta.contains(QStringLiteral("mpris:trackid"))) {
        const QVariant tidVar = meta.value(QStringLiteral("mpris:trackid"));
        if (tidVar.canConvert<QDBusObjectPath>()) {
            m_trackId = tidVar.value<QDBusObjectPath>().path();
        } else {
            m_trackId = tidVar.toString();
        }
    }

    m_trackTitle = meta.value(QStringLiteral("xesam:title")).toString();
    m_trackAlbum = meta.value(QStringLiteral("xesam:album")).toString();

    // Artists can be QStringList, QVariantList, or single QString
    m_trackArtists.clear();
    const QVariant artistVar = meta.value(QStringLiteral("xesam:artist"));
    if (artistVar.userType() == QMetaType::QStringList) {
        m_trackArtists = artistVar.toStringList();
    } else if (artistVar.canConvert<QVariantList>()) {
        const QVariantList list = artistVar.toList();
        for (const auto &item : list) {
            const QString a = item.toString().trimmed();
            if (!a.isEmpty()) {
                m_trackArtists.append(a);
            }
        }
    } else {
        const QString a = artistVar.toString().trimmed();
        if (!a.isEmpty()) {
            m_trackArtists.append(a);
        }
    }
    m_trackArtist = m_trackArtists.join(QStringLiteral(", "));

    // Length is in microseconds in MPRIS
    if (meta.contains(QStringLiteral("mpris:length"))) {
        const qint64 lengthUs = meta.value(QStringLiteral("mpris:length")).toLongLong();
        m_length = static_cast<double>(lengthUs) / 1'000'000.0;
        if (m_length < 0.0) m_length = 0.0;
    } else {
        m_length = 0.0;
    }

    // Art URL
    const QString rawArt = meta.value(QStringLiteral("mpris:artUrl")).toString();
    m_trackArtUrl = formatArtUrl(rawArt);

    // Reset base position on new track
    m_basePosition = 0.0;
    m_lastPositionTime = std::chrono::steady_clock::now();

    emit metadataChanged();
    emit positionChanged();
}

double MediaPlayer::position() const {
    if (m_playbackState == PlaybackState::Playing) {
        const auto now = std::chrono::steady_clock::now();
        const double elapsed = std::chrono::duration<double>(now - m_lastPositionTime).count();
        double pos = m_basePosition + (elapsed * m_rate);
        if (m_length > 0.0 && pos > m_length) {
            pos = m_length;
        }
        return pos >= 0.0 ? pos : 0.0;
    }
    return m_basePosition >= 0.0 ? m_basePosition : 0.0;
}

QString MediaPlayer::formattedPosition() const {
    return formatSeconds(position());
}

QString MediaPlayer::formattedLength() const {
    return formatSeconds(m_length);
}

double MediaPlayer::progress() const {
    if (m_length <= 0.0) return 0.0;
    const double pos = position();
    return std::clamp(pos / m_length, 0.0, 1.0);
}

void MediaPlayer::updateInterpolatedPosition() {
    emit positionChanged();
}

void MediaPlayer::positionChanged() {
    emit positionChangedSignal();
}

void MediaPlayer::play() {
    auto msg = QDBusMessage::createMethodCall(
        m_service,
        QStringLiteral("/org/mpris/MediaPlayer2"),
        QStringLiteral("org.mpris.MediaPlayer2.Player"),
        QStringLiteral("Play")
    );
    QDBusConnection::sessionBus().asyncCall(msg);
}

void MediaPlayer::pause() {
    auto msg = QDBusMessage::createMethodCall(
        m_service,
        QStringLiteral("/org/mpris/MediaPlayer2"),
        QStringLiteral("org.mpris.MediaPlayer2.Player"),
        QStringLiteral("Pause")
    );
    QDBusConnection::sessionBus().asyncCall(msg);
}

void MediaPlayer::togglePlaying() {
    auto msg = QDBusMessage::createMethodCall(
        m_service,
        QStringLiteral("/org/mpris/MediaPlayer2"),
        QStringLiteral("org.mpris.MediaPlayer2.Player"),
        QStringLiteral("PlayPause")
    );
    QDBusConnection::sessionBus().asyncCall(msg);
}

void MediaPlayer::next() {
    auto msg = QDBusMessage::createMethodCall(
        m_service,
        QStringLiteral("/org/mpris/MediaPlayer2"),
        QStringLiteral("org.mpris.MediaPlayer2.Player"),
        QStringLiteral("Next")
    );
    QDBusConnection::sessionBus().asyncCall(msg);
}

void MediaPlayer::previous() {
    auto msg = QDBusMessage::createMethodCall(
        m_service,
        QStringLiteral("/org/mpris/MediaPlayer2"),
        QStringLiteral("org.mpris.MediaPlayer2.Player"),
        QStringLiteral("Previous")
    );
    QDBusConnection::sessionBus().asyncCall(msg);
}

void MediaPlayer::stop() {
    auto msg = QDBusMessage::createMethodCall(
        m_service,
        QStringLiteral("/org/mpris/MediaPlayer2"),
        QStringLiteral("org.mpris.MediaPlayer2.Player"),
        QStringLiteral("Stop")
    );
    QDBusConnection::sessionBus().asyncCall(msg);
}

void MediaPlayer::seek(double offsetSeconds) {
    const qint64 offsetUs = static_cast<qint64>(offsetSeconds * 1'000'000.0);
    auto msg = QDBusMessage::createMethodCall(
        m_service,
        QStringLiteral("/org/mpris/MediaPlayer2"),
        QStringLiteral("org.mpris.MediaPlayer2.Player"),
        QStringLiteral("Seek")
    );
    msg << offsetUs;
    QDBusConnection::sessionBus().asyncCall(msg);

    m_basePosition = std::clamp(position() + offsetSeconds, 0.0, m_length > 0.0 ? m_length : 1e9);
    m_lastPositionTime = std::chrono::steady_clock::now();
    emit positionChanged();
}

void MediaPlayer::setPosition(double posSeconds) {
    if (!m_canSeek) return;

    const qint64 posUs = static_cast<qint64>(posSeconds * 1'000'000.0);
    if (!m_trackId.isEmpty() && m_trackId != QStringLiteral("/org/mpris/MediaPlayer2/TrackList/NoTrack")) {
        auto msg = QDBusMessage::createMethodCall(
            m_service,
            QStringLiteral("/org/mpris/MediaPlayer2"),
            QStringLiteral("org.mpris.MediaPlayer2.Player"),
            QStringLiteral("SetPosition")
        );
        msg << QDBusObjectPath(m_trackId) << posUs;
        QDBusConnection::sessionBus().asyncCall(msg);
    } else {
        // Fallback to Seek relative delta
        const double delta = posSeconds - position();
        seek(delta);
    }

    m_basePosition = posSeconds;
    m_lastPositionTime = std::chrono::steady_clock::now();
    emit positionChanged();
}

void MediaPlayer::setShuffle(bool enable) {
    auto msg = QDBusMessage::createMethodCall(
        m_service,
        QStringLiteral("/org/mpris/MediaPlayer2"),
        QStringLiteral("org.freedesktop.DBus.Properties"),
        QStringLiteral("Set")
    );
    msg << QStringLiteral("org.mpris.MediaPlayer2.Player")
        << QStringLiteral("Shuffle")
        << QVariant::fromValue(QDBusVariant(enable));
    QDBusConnection::sessionBus().asyncCall(msg);
}

void MediaPlayer::setLoopState(int state) {
    QString str = QStringLiteral("None");
    if (state == static_cast<int>(LoopState::Track)) {
        str = QStringLiteral("Track");
    } else if (state == static_cast<int>(LoopState::Playlist)) {
        str = QStringLiteral("Playlist");
    }

    auto msg = QDBusMessage::createMethodCall(
        m_service,
        QStringLiteral("/org/mpris/MediaPlayer2"),
        QStringLiteral("org.freedesktop.DBus.Properties"),
        QStringLiteral("Set")
    );
    msg << QStringLiteral("org.mpris.MediaPlayer2.Player")
        << QStringLiteral("LoopStatus")
        << QVariant::fromValue(QDBusVariant(str));
    QDBusConnection::sessionBus().asyncCall(msg);
}

void MediaPlayer::setVolume(double vol) {
    m_volume = std::clamp(vol, 0.0, 1.0);
    auto msg = QDBusMessage::createMethodCall(
        m_service,
        QStringLiteral("/org/mpris/MediaPlayer2"),
        QStringLiteral("org.freedesktop.DBus.Properties"),
        QStringLiteral("Set")
    );
    msg << QStringLiteral("org.mpris.MediaPlayer2.Player")
        << QStringLiteral("Volume")
        << QVariant::fromValue(QDBusVariant(m_volume));
    QDBusConnection::sessionBus().asyncCall(msg);
    emit volumeChanged();
}

} // namespace qs::plugins::media
