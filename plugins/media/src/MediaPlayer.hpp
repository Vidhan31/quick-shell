#pragma once

#include "MediaTypes.hpp"

#include <QDBusConnection>
#include <QDBusMessage>
#include <QDBusObjectPath>
#include <QDBusPendingCallWatcher>
#include <QDBusVariant>
#include <QObject>
#include <QString>
#include <QStringList>
#include <QVariantMap>
#include <QtQml/qqmlregistration.h>
#include <chrono>

namespace qs::plugins::media {

class MediaPlayer : public QObject {
    Q_OBJECT
    QML_ELEMENT
    QML_UNCREATABLE("MediaPlayer instances are managed by MediaManager")

    Q_PROPERTY(QString service READ service CONSTANT)
    Q_PROPERTY(QString identity READ identity NOTIFY identityChanged)
    Q_PROPERTY(int playbackState READ playbackStateInt NOTIFY playbackStateChanged)
    Q_PROPERTY(bool isPlaying READ isPlaying NOTIFY playbackStateChanged)
    Q_PROPERTY(QString trackTitle READ trackTitle NOTIFY metadataChanged)
    Q_PROPERTY(QString trackArtist READ trackArtist NOTIFY metadataChanged)
    Q_PROPERTY(QStringList trackArtists READ trackArtists NOTIFY metadataChanged)
    Q_PROPERTY(QString trackAlbum READ trackAlbum NOTIFY metadataChanged)
    Q_PROPERTY(QString trackArtUrl READ trackArtUrl NOTIFY metadataChanged)
    Q_PROPERTY(double length READ length NOTIFY metadataChanged)
    Q_PROPERTY(bool lengthSupported READ lengthSupported NOTIFY metadataChanged)
    Q_PROPERTY(double position READ position WRITE setPosition NOTIFY positionChanged)
    Q_PROPERTY(bool positionSupported READ positionSupported NOTIFY positionSupportedChanged)
    Q_PROPERTY(QString formattedPosition READ formattedPosition NOTIFY positionChanged)
    Q_PROPERTY(QString formattedLength READ formattedLength NOTIFY metadataChanged)
    Q_PROPERTY(double progress READ progress NOTIFY positionChanged)
    Q_PROPERTY(bool canControl READ canControl NOTIFY capabilitiesChanged)
    Q_PROPERTY(bool canPlay READ canPlay NOTIFY capabilitiesChanged)
    Q_PROPERTY(bool canPause READ canPause NOTIFY capabilitiesChanged)
    Q_PROPERTY(bool canTogglePlaying READ canTogglePlaying NOTIFY capabilitiesChanged)
    Q_PROPERTY(bool canGoNext READ canGoNext NOTIFY capabilitiesChanged)
    Q_PROPERTY(bool canGoPrevious READ canGoPrevious NOTIFY capabilitiesChanged)
    Q_PROPERTY(bool canSeek READ canSeek NOTIFY capabilitiesChanged)
    Q_PROPERTY(bool shuffle READ shuffle WRITE setShuffle NOTIFY shuffleChanged)
    Q_PROPERTY(bool shuffleSupported READ shuffleSupported NOTIFY shuffleSupportedChanged)
    Q_PROPERTY(int loopState READ loopStateInt WRITE setLoopState NOTIFY loopStateChanged)
    Q_PROPERTY(bool loopSupported READ loopSupported NOTIFY loopSupportedChanged)
    Q_PROPERTY(double volume READ volume WRITE setVolume NOTIFY volumeChanged)

public:
    explicit MediaPlayer(const QString &service, QObject *parent = nullptr);
    ~MediaPlayer() override;

    [[nodiscard]] QString service() const { return m_service; }
    [[nodiscard]] QString identity() const { return m_identity; }
    [[nodiscard]] PlaybackState playbackState() const { return m_playbackState; }
    [[nodiscard]] int playbackStateInt() const { return static_cast<int>(m_playbackState); }
    [[nodiscard]] bool isPlaying() const { return m_playbackState == PlaybackState::Playing; }

    [[nodiscard]] QString trackTitle() const { return m_trackTitle; }
    [[nodiscard]] QString trackArtist() const { return m_trackArtist; }
    [[nodiscard]] QStringList trackArtists() const { return m_trackArtists; }
    [[nodiscard]] QString trackAlbum() const { return m_trackAlbum; }
    [[nodiscard]] QString trackArtUrl() const { return m_trackArtUrl; }
    [[nodiscard]] double length() const { return m_length; }
    [[nodiscard]] bool lengthSupported() const { return m_length > 0.0; }

    [[nodiscard]] double position() const;
    [[nodiscard]] bool positionSupported() const { return m_positionSupported; }
    [[nodiscard]] QString formattedPosition() const;
    [[nodiscard]] QString formattedLength() const;
    [[nodiscard]] double progress() const;

    [[nodiscard]] bool canControl() const { return m_canControl; }
    [[nodiscard]] bool canPlay() const { return m_canPlay; }
    [[nodiscard]] bool canPause() const { return m_canPause; }
    [[nodiscard]] bool canTogglePlaying() const { return m_canControl && (m_canPlay || m_canPause); }
    [[nodiscard]] bool canGoNext() const { return m_canGoNext; }
    [[nodiscard]] bool canGoPrevious() const { return m_canGoPrevious; }
    [[nodiscard]] bool canSeek() const { return m_canSeek; }

    [[nodiscard]] bool shuffle() const { return m_shuffle; }
    [[nodiscard]] bool shuffleSupported() const { return m_shuffleSupported; }
    [[nodiscard]] LoopState loopState() const { return m_loopState; }
    [[nodiscard]] int loopStateInt() const { return static_cast<int>(m_loopState); }
    [[nodiscard]] bool loopSupported() const { return m_loopSupported; }
    [[nodiscard]] double volume() const { return m_volume; }

    void updateInterpolatedPosition();

public slots:
    void play();
    void pause();
    void togglePlaying();
    void next();
    void previous();
    void stop();
    void seek(double offsetSeconds);
    void setPosition(double posSeconds);
    void setShuffle(bool enable);
    void setLoopState(int state);
    void setVolume(double vol);

signals:
    void identityChanged();
    void playbackStateChanged();
    void metadataChanged();
    void positionChanged();
    void positionSupportedChanged();
    void capabilitiesChanged();
    void shuffleChanged();
    void shuffleSupportedChanged();
    void loopStateChanged();
    void loopSupportedChanged();
    void volumeChanged();

private slots:
    void onPropertiesChanged(const QString &interfaceName, const QVariantMap &changedProps, const QStringList &invalidatedProps);
    void onSeeked(qint64 positionUs);
    void onGetAllRootFinished(QDBusPendingCallWatcher *watcher);
    void onGetAllPlayerFinished(QDBusPendingCallWatcher *watcher);

private:
    void initProperties();
    void applyMetadata(const QVariantMap &meta);
    void parsePlaybackStatus(const QString &status);
    void parseLoopStatus(const QString &status);

    QString m_service;
    QString m_identity;
    PlaybackState m_playbackState{PlaybackState::Stopped};

    QString m_trackId;
    QString m_trackTitle;
    QString m_trackArtist;
    QStringList m_trackArtists;
    QString m_trackAlbum;
    QString m_trackArtUrl;
    double m_length{0.0};

    double m_basePosition{0.0};
    std::chrono::steady_clock::time_point m_lastPositionTime;
    double m_rate{1.0};
    bool m_positionSupported{true};

    bool m_canControl{true};
    bool m_canPlay{true};
    bool m_canPause{true};
    bool m_canGoNext{true};
    bool m_canGoPrevious{true};
    bool m_canSeek{true};

    bool m_shuffle{false};
    bool m_shuffleSupported{false};
    LoopState m_loopState{LoopState::None};
    bool m_loopSupported{false};
    double m_volume{1.0};
};

} // namespace qs::plugins::media
