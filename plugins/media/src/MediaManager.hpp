#pragma once

#include "MediaPlayer.hpp"

#include <QDBusServiceWatcher>
#include <QList>
#include <QObject>
#include <QString>
#include <QTimer>
#include <QtQml/qqmlregistration.h>

namespace qs::plugins::media {

class MediaManager : public QObject {
    Q_OBJECT
    QML_ELEMENT
    QML_NAMED_ELEMENT(MediaManager)

    // Player collections
    Q_PROPERTY(QList<QObject*> playerList READ playerListObjects NOTIFY playersChanged)
    Q_PROPERTY(QList<QObject*> players READ playerListObjects NOTIFY playersChanged)
    Q_PROPERTY(int playerCount READ playerCount NOTIFY playersChanged)

    // Active player selection
    Q_PROPERTY(QObject* activePlayer READ activePlayerObject NOTIFY activePlayerChanged)
    Q_PROPERTY(QObject* player READ activePlayerObject NOTIFY activePlayerChanged)
    Q_PROPERTY(QObject* manualPlayer READ manualPlayerObject WRITE setManualPlayer NOTIFY manualPlayerChanged)
    Q_PROPERTY(bool hasPlayer READ hasPlayer NOTIFY activePlayerChanged)
    Q_PROPERTY(bool isPlaying READ isPlaying NOTIFY activeStateChanged)

    // Direct active track properties
    Q_PROPERTY(QString title READ title NOTIFY trackChanged)
    Q_PROPERTY(QString artist READ artist NOTIFY trackChanged)
    Q_PROPERTY(QString trackTitle READ title NOTIFY trackChanged)
    Q_PROPERTY(QString trackArtist READ artist NOTIFY trackChanged)
    Q_PROPERTY(QString trackAlbum READ album NOTIFY trackChanged)
    Q_PROPERTY(QString trackArtUrl READ artUrl NOTIFY trackChanged)
    Q_PROPERTY(double trackLength READ trackLength NOTIFY trackChanged)
    Q_PROPERTY(double length READ trackLength NOTIFY trackChanged)
    Q_PROPERTY(double trackPos READ trackPos WRITE setTrackPos NOTIFY positionTick)
    Q_PROPERTY(double position READ trackPos WRITE setTrackPos NOTIFY positionTick)
    Q_PROPERTY(double progress READ progress NOTIFY positionTick)
    Q_PROPERTY(QString formattedPosition READ formattedPosition NOTIFY positionTick)
    Q_PROPERTY(QString formattedLength READ formattedLength NOTIFY trackChanged)

    // Playback control capabilities
    Q_PROPERTY(bool canControl READ canControl NOTIFY capabilitiesChanged)
    Q_PROPERTY(bool canTogglePlaying READ canTogglePlaying NOTIFY capabilitiesChanged)
    Q_PROPERTY(bool canGoNext READ canGoNext NOTIFY capabilitiesChanged)
    Q_PROPERTY(bool canGoPrevious READ canGoPrevious NOTIFY capabilitiesChanged)
    Q_PROPERTY(bool canSeek READ canSeek NOTIFY capabilitiesChanged)
    Q_PROPERTY(bool shuffle READ shuffle WRITE setShuffle NOTIFY shuffleChanged)
    Q_PROPERTY(bool shuffleSupported READ shuffleSupported NOTIFY shuffleChanged)
    Q_PROPERTY(int loopState READ loopState WRITE setLoopState NOTIFY loopStateChanged)
    Q_PROPERTY(bool loopSupported READ loopSupported NOTIFY loopStateChanged)

public:
    explicit MediaManager(QObject *parent = nullptr);
    ~MediaManager() override;

    [[nodiscard]] QList<QObject*> playerListObjects() const;
    [[nodiscard]] int playerCount() const { return m_players.size(); }

    [[nodiscard]] QObject* activePlayerObject() const { return m_activePlayer; }
    [[nodiscard]] MediaPlayer* activePlayer() const { return m_activePlayer; }

    [[nodiscard]] QObject* manualPlayerObject() const { return m_manualPlayer; }
    void setManualPlayer(QObject *player);

    [[nodiscard]] bool hasPlayer() const { return m_activePlayer != nullptr; }
    [[nodiscard]] bool isPlaying() const { return m_activePlayer && m_activePlayer->isPlaying(); }

    [[nodiscard]] QString title() const;
    [[nodiscard]] QString artist() const;
    [[nodiscard]] QString album() const;
    [[nodiscard]] QString artUrl() const;
    [[nodiscard]] double trackLength() const;
    [[nodiscard]] double trackPos() const;
    void setTrackPos(double posSec);
    [[nodiscard]] double progress() const;
    [[nodiscard]] QString formattedPosition() const;
    [[nodiscard]] QString formattedLength() const;

    [[nodiscard]] bool canControl() const;
    [[nodiscard]] bool canTogglePlaying() const;
    [[nodiscard]] bool canGoNext() const;
    [[nodiscard]] bool canGoPrevious() const;
    [[nodiscard]] bool canSeek() const;
    [[nodiscard]] bool shuffle() const;
    [[nodiscard]] bool shuffleSupported() const;
    [[nodiscard]] int loopState() const;
    [[nodiscard]] bool loopSupported() const;

public slots:
    void selectPlayer(QObject *player);
    void playPause();
    void togglePlaying();
    void play();
    void pause();
    void next();
    void previous();
    void stop();
    void seek(double offsetSec);
    void setShuffle(bool enable);
    void setLoopState(int state);

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
    void onServiceRegistered(const QString &service);
    void onServiceUnregistered(const QString &service);
    void onServiceOwnerChanged(const QString &service, const QString &oldOwner, const QString &newOwner);

    void onPlayerPlaybackStateChanged();
    void onPlayerMetadataChanged();
    void onPlayerIdentityChanged();
    void onPlayerCapabilitiesChanged();
    void onPlayerPositionChanged();

    void onClockTick();

private:
    void discoverInitialServices();
    void addPlayer(const QString &service);
    void removePlayer(const QString &service);
    void resolveActivePlayer();
    void updateClockTimer();

    QList<MediaPlayer*> m_players;
    MediaPlayer *m_activePlayer{nullptr};
    MediaPlayer *m_manualPlayer{nullptr};

    QDBusServiceWatcher *m_watcher{nullptr};
    QTimer *m_clockTimer{nullptr};
};

} // namespace qs::plugins::media
