#include "MediaManager.hpp"
#include "MediaPlayer.hpp"
#include "MediaTypes.hpp"

#include <QCoreApplication>
#include <QDBusConnection>
#include <QDBusInterface>
#include <QDBusReply>
#include <QDebug>
#include <QTimer>
#include <iostream>

using namespace qs::plugins::media;

int main(int argc, char *argv[]) {
    QCoreApplication app(argc, argv);

    auto bus = QDBusConnection::sessionBus();
    if (!bus.isConnected()) {
        std::cerr << "Error: Cannot connect to session D-Bus bus at "
                  << qPrintable(qgetenv("DBUS_SESSION_BUS_ADDRESS")) << std::endl;
        return 1;
    }

    std::cout << "=== MPRIS MEDIA PROBE (Native Qt6 DBus) ===" << std::endl;

    QDBusInterface dbusIface(
        QStringLiteral("org.freedesktop.DBus"),
        QStringLiteral("/org/freedesktop/DBus"),
        QStringLiteral("org.freedesktop.DBus"),
        bus
    );

    QDBusReply<QStringList> reply = dbusIface.call(QStringLiteral("ListNames"));
    if (!reply.isValid()) {
        std::cerr << "Failed to list D-Bus names: " << qPrintable(reply.error().message()) << std::endl;
        return 1;
    }

    QStringList mprisServices;
    for (const QString &name : reply.value()) {
        if (name.startsWith(QLatin1String("org.mpris.MediaPlayer2."))) {
            mprisServices.append(name);
        }
    }

    std::cout << "Discovered " << mprisServices.size() << " active MPRIS player(s) on session bus.\n" << std::endl;

    if (mprisServices.isEmpty()) {
        std::cout << "No active media players found. Start Brave, Spotify, MPV, or VLC to test." << std::endl;
        return 0;
    }

    for (const QString &service : mprisServices) {
        std::cout << "--------------------------------------------------" << std::endl;
        std::cout << "Service:  " << qPrintable(service) << std::endl;

        MediaPlayer player(service);

        // Wait brief event loop turn to process async GetAll replies
        QTimer timer;
        timer.setSingleShot(true);
        QEventLoop loop;
        QObject::connect(&timer, &QTimer::timeout, &loop, &QEventLoop::quit);
        timer.start(50); // 50ms is plenty for local Unix socket
        loop.exec();

        std::cout << "Identity: " << qPrintable(player.identity()) << std::endl;
        std::cout << "Status:   " << (player.playbackState() == PlaybackState::Playing ? "Playing"
                                    : player.playbackState() == PlaybackState::Paused ? "Paused" : "Stopped") << std::endl;
        std::cout << "Title:    " << qPrintable(player.trackTitle()) << std::endl;
        std::cout << "Artist:   " << qPrintable(player.trackArtist()) << std::endl;
        std::cout << "Album:    " << qPrintable(player.trackAlbum()) << std::endl;
        std::cout << "Art URL:  " << qPrintable(player.trackArtUrl()) << std::endl;
        std::cout << "Length:   " << qPrintable(player.formattedLength()) << " (" << player.length() << "s)" << std::endl;
        std::cout << "Position: " << qPrintable(player.formattedPosition()) << " (" << player.position() << "s)" << std::endl;
        std::cout << "Progress: " << (player.progress() * 100.0) << "%" << std::endl;
        std::cout << "Volume:   " << (player.volume() * 100.0) << "%" << std::endl;
        std::cout << "Shuffle:  " << (player.shuffle() ? "true" : "false") << std::endl;
        std::cout << "Loop:     " << (player.loopState() == LoopState::Track ? "Track"
                                    : player.loopState() == LoopState::Playlist ? "Playlist" : "None") << std::endl;
        std::cout << "CanPlay:  " << (player.canPlay() ? "yes" : "no")
                  << " | CanPause: " << (player.canPause() ? "yes" : "no")
                  << " | CanSeek: " << (player.canSeek() ? "yes" : "no")
                  << " | CanNext: " << (player.canGoNext() ? "yes" : "no")
                  << " | CanPrev: " << (player.canGoPrevious() ? "yes" : "no") << std::endl;
    }
    std::cout << "--------------------------------------------------" << std::endl;

    return 0;
}
