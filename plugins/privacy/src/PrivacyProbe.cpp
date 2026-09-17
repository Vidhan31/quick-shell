#include "PrivacyProbe.hpp"

#include <QByteArray>
#include <QFile>
#include <QHash>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QProcess>
#include <QRegularExpression>

#include <dirent.h>
#include <fcntl.h>
#include <limits.h>
#include <mutex>
#include <sys/stat.h>
#include <thread>
#include <unistd.h>
#include <vector>

namespace qs::plugins {

QString PrivacyProbe::getV4LDeviceName(const QString &vname) {
    const QString sysPath = QStringLiteral("/sys/class/video4linux/") + vname + QStringLiteral("/name");
    QFile file(sysPath);
    if (file.open(QIODevice::ReadOnly | QIODevice::Text)) {
        const QString raw = QString::fromUtf8(file.readAll()).trimmed();
        const int colonIdx = raw.indexOf(QLatin1Char(':'));
        QString clean = (colonIdx != -1) ? raw.left(colonIdx).trimmed() : raw;
        clean = clean.remove(QStringLiteral(" Audio")).trimmed();
        if (!clean.isEmpty()) {
            return clean;
        }
        if (!raw.isEmpty()) {
            return raw;
        }
    }
    return QStringLiteral("Camera (") + vname + QStringLiteral(")");
}

bool PrivacyProbe::checkAlsaCapture(PrivacyState &state) {
    DIR *asoundDir = opendir("/proc/asound");
    if (!asoundDir) {
        return false;
    }

    bool activeFound = false;
    struct dirent *cardEntry;

    while ((cardEntry = readdir(asoundDir)) != nullptr) {
        if (strncmp(cardEntry->d_name, "card", 4) != 0) continue;
        if (cardEntry->d_name[4] < '0' || cardEntry->d_name[4] > '9') continue;

        char cardPath[PATH_MAX];
        snprintf(cardPath, sizeof(cardPath), "/proc/asound/%s", cardEntry->d_name);
        DIR *cardDir = opendir(cardPath);
        if (!cardDir) continue;

        struct dirent *pcmEntry;
        while ((pcmEntry = readdir(cardDir)) != nullptr) {
            const size_t len = strlen(pcmEntry->d_name);
            if (len < 4 || strncmp(pcmEntry->d_name, "pcm", 3) != 0 || pcmEntry->d_name[len - 1] != 'c') {
                continue;
            }

            char statusPath[PATH_MAX];
            snprintf(statusPath, sizeof(statusPath), "/proc/asound/%s/%s/sub0/status",
                     cardEntry->d_name, pcmEntry->d_name);

            const int sfd = open(statusPath, O_RDONLY);
            if (sfd >= 0) {
                char sbuf[128];
                const ssize_t sn = read(sfd, sbuf, sizeof(sbuf) - 1);
                close(sfd);
                if (sn > 0) {
                    sbuf[sn] = '\0';
                    if (strstr(sbuf, "RUNNING") != nullptr) {
                        activeFound = true;
                        state.micActive = true;

                        char idPath[PATH_MAX];
                        snprintf(idPath, sizeof(idPath), "/proc/asound/%s/id", cardEntry->d_name);
                        const int ifd = open(idPath, O_RDONLY);
                        QString cardName = QStringLiteral("Microphone");
                        if (ifd >= 0) {
                            char ibuf[64] = {0};
                            ssize_t in = read(ifd, ibuf, sizeof(ibuf) - 1);
                            close(ifd);
                            if (in > 0) {
                                while (in > 0 && (ibuf[in - 1] == '\n' || ibuf[in - 1] == '\r')) {
                                    ibuf[--in] = '\0';
                                }
                                cardName = QString::fromUtf8(ibuf);
                            }
                        }
                        if (!state.micDevices.contains(cardName)) {
                            state.micDevices.append(cardName);
                        }
                    }
                }
            }
        }
        closedir(cardDir);
    }
    closedir(asoundDir);
    return activeFound;
}

bool PrivacyProbe::checkV4L2Fast(PrivacyState &state) {
    DIR *procDir = opendir("/proc");
    if (!procDir) {
        return false;
    }

    const uid_t myUid = getuid();
    const int procFd = dirfd(procDir);
    struct dirent *procEntry;
    std::vector<int> pids;
    pids.reserve(128);

    while ((procEntry = readdir(procDir)) != nullptr) {
        if (procEntry->d_name[0] < '0' || procEntry->d_name[0] > '9') {
            continue;
        }

        struct stat st;
        if (fstatat(procFd, procEntry->d_name, &st, AT_SYMLINK_NOFOLLOW) != 0) {
            continue;
        }
        if (st.st_uid != myUid) {
            continue;
        }

        pids.push_back(atoi(procEntry->d_name));
    }
    closedir(procDir);

    if (pids.empty()) {
        return false;
    }

    struct FoundVideo {
        QString appName;
        QString devName;
    };

    std::mutex foundMutex;
    std::vector<FoundVideo> foundList;
    std::atomic<bool> anyFound{false};

    const size_t numThreads = std::min(static_cast<size_t>(6), std::max(static_cast<size_t>(1), pids.size() / 8));
    std::vector<std::thread> workers;
    workers.reserve(numThreads);

    for (size_t t = 0; t < numThreads; ++t) {
        workers.emplace_back([&, t] {
            char target[PATH_MAX];
            for (size_t i = t; i < pids.size(); i += numThreads) {
                char fdPath[64];
                snprintf(fdPath, sizeof(fdPath), "/proc/%d/fd", pids[i]);
                DIR *d = opendir(fdPath);
                if (!d) continue;

                const int dfd = dirfd(d);
                struct dirent *fe;
                while ((fe = readdir(d)) != nullptr) {
                    if (fe->d_name[0] == '.') continue;
                    const ssize_t len = readlinkat(dfd, fe->d_name, target, sizeof(target) - 1);
                    if (len > 10 && strncmp(target, "/dev/video", 10) == 0) {
                        target[len] = '\0';

                        char commPath[64];
                        snprintf(commPath, sizeof(commPath), "/proc/%d/comm", pids[i]);
                        char commBuf[64] = {0};
                        const int cfd = open(commPath, O_RDONLY);
                        if (cfd >= 0) {
                            ssize_t clen = read(cfd, commBuf, sizeof(commBuf) - 1);
                            close(cfd);
                            if (clen > 0) {
                                while (clen > 0 && (commBuf[clen - 1] == '\n' || commBuf[clen - 1] == '\r')) {
                                    commBuf[--clen] = '\0';
                                }
                            }
                        } else {
                            snprintf(commBuf, sizeof(commBuf), "PID %d", pids[i]);
                        }

                        if (strcmp(commBuf, "wireplumber") == 0 || strcmp(commBuf, "pipewire") == 0) {
                            continue;
                        }

                        const char *slash = strrchr(target, '/');
                        const char *vname = slash ? slash + 1 : target;
                        const QString devName = getV4LDeviceName(QString::fromLatin1(vname));
                        const QString appName = QString::fromUtf8(commBuf);

                        std::lock_guard<std::mutex> lock(foundMutex);
                        foundList.push_back({appName, devName});
                        anyFound.store(true, std::memory_order_relaxed);
                    }
                }
                closedir(d);
            }
        });
    }

    for (auto &w : workers) {
        w.join();
    }

    for (const auto &item : foundList) {
        if (!state.cameraDevices.contains(item.devName)) {
            state.cameraDevices.append(item.devName);
        }
        if (!state.cameraApps.contains(item.appName)) {
            state.cameraApps.append(item.appName);
        }
        state.cameraActive = true;
    }

    return anyFound.load(std::memory_order_relaxed);
}

void PrivacyProbe::resolvePipeWireMetadata(PrivacyState &state) {
    QProcess proc;
    proc.start(QStringLiteral("pw-dump"), QStringList());
    if (!proc.waitForFinished(1500) || proc.exitStatus() != QProcess::NormalExit || proc.exitCode() != 0) {
        return;
    }

    const QByteArray output = proc.readAllStandardOutput();
    if (output.isEmpty()) {
        return;
    }

    QJsonParseError parseError;
    const QJsonDocument doc = QJsonDocument::fromJson(output, &parseError);
    if (!doc.isArray()) {
        return;
    }

    const QJsonArray arr = doc.array();
    QHash<int, QJsonObject> nodes;
    std::vector<QJsonObject> links;

    for (const QJsonValue &val : arr) {
        if (!val.isObject()) continue;
        const QJsonObject item = val.toObject();
        const QString type = item.value(QStringLiteral("type")).toString();
        if (type == QLatin1String("PipeWire:Interface:Node")) {
            const int id = item.value(QStringLiteral("id")).toInt();
            nodes.insert(id, item);
        } else if (type == QLatin1String("PipeWire:Interface:Link")) {
            links.push_back(item);
        }
    }

    for (const auto &link : links) {
        const QJsonObject info = link.value(QStringLiteral("info")).toObject();
        const QJsonObject props = info.value(QStringLiteral("props")).toObject();
        const int outId = props.value(QStringLiteral("link.output.node")).toInt();
        const int inId = props.value(QStringLiteral("link.input.node")).toInt();

        const auto outIt = nodes.constFind(outId);
        const auto inIt = nodes.constFind(inId);
        if (outIt == nodes.constEnd() || inIt == nodes.constEnd()) {
            continue;
        }

        const QJsonObject outNode = *outIt;
        const QJsonObject inNode = *inIt;
        const QJsonObject outProps = outNode.value(QStringLiteral("info")).toObject().value(QStringLiteral("props")).toObject();
        const QJsonObject inProps = inNode.value(QStringLiteral("info")).toObject().value(QStringLiteral("props")).toObject();

        const QString outClass = outProps.value(QStringLiteral("media.class")).toString();
        const QString inClass = inProps.value(QStringLiteral("media.class")).toString();

        // 1. Microphone recording link
        if (outClass == QLatin1String("Audio/Source") && inClass == QLatin1String("Stream/Input/Audio")) {
            state.micActive = true;

            QString appName = inProps.value(QStringLiteral("application.name")).toString();
            if (appName.isEmpty()) appName = inProps.value(QStringLiteral("node.name")).toString();
            if (appName.isEmpty()) appName = inNode.value(QStringLiteral("info")).toObject().value(QStringLiteral("name")).toString();
            if (appName.isEmpty()) appName = QStringLiteral("Recording App");

            QString sourceDesc = outProps.value(QStringLiteral("node.description")).toString();
            if (sourceDesc.isEmpty()) sourceDesc = outProps.value(QStringLiteral("node.nick")).toString();
            if (sourceDesc.isEmpty()) sourceDesc = QStringLiteral("Microphone");

            if (!state.micApps.contains(appName)) state.micApps.append(appName);
            if (!state.micDevices.contains(sourceDesc)) state.micDevices.append(sourceDesc);
        }

        // 2. Video capture link
        if (outClass == QLatin1String("Video/Source")) {
            state.cameraActive = true;

            QString appName = inProps.value(QStringLiteral("application.name")).toString();
            if (appName.isEmpty()) appName = inProps.value(QStringLiteral("node.name")).toString();
            if (appName.isEmpty()) appName = inNode.value(QStringLiteral("info")).toObject().value(QStringLiteral("name")).toString();
            if (appName.isEmpty()) appName = QStringLiteral("Camera App");

            QString camDesc = outProps.value(QStringLiteral("node.description")).toString();
            if (camDesc.isEmpty()) camDesc = outProps.value(QStringLiteral("node.nick")).toString();
            if (camDesc.isEmpty()) camDesc = QStringLiteral("Webcam");

            if (!state.cameraApps.contains(appName)) state.cameraApps.append(appName);
            if (!state.cameraDevices.contains(camDesc)) state.cameraDevices.append(camDesc);
        }
    }

    if (!state.micActive) {
        checkWpctl(state);
    }
}

void PrivacyProbe::checkWpctl(PrivacyState &state) {
    QProcess wpProc;
    wpProc.start(QStringLiteral("wpctl"), QStringList{QStringLiteral("status")});
    if (!wpProc.waitForFinished(1000) || wpProc.exitStatus() != QProcess::NormalExit || wpProc.exitCode() != 0) {
        return;
    }

    const QByteArray out = wpProc.readAllStandardOutput();
    const QList<QByteArray> lines = out.split('\n');
    enum Section { None, Audio, Video, Settings } section = None;
    QString currApp;
    static const QRegularExpression appRegex(QStringLiteral(R"(^\s*([0-9]+)\.\s+([^\s].*?)\s*$)"));

    for (const QByteArray &rawLine : lines) {
        const QString line = QString::fromUtf8(rawLine);
        const QString stripped = line.trimmed();
        if (stripped.startsWith(QLatin1String("Audio"))) {
            section = Audio;
            continue;
        } else if (stripped.startsWith(QLatin1String("Video"))) {
            section = Video;
            continue;
        } else if (stripped.startsWith(QLatin1String("Settings"))) {
            section = Settings;
            continue;
        }

        if (section == Audio) {
            const auto match = appRegex.match(line);
            if (match.hasMatch()) {
                currApp = match.captured(2).trimmed();
            }
            if (line.contains(QLatin1Char('<')) && line.contains(QLatin1String("[active]"))) {
                state.micActive = true;
                if (!currApp.isEmpty() && !state.micApps.contains(currApp)) {
                    state.micApps.append(currApp);
                }
                if (state.micDevices.isEmpty()) {
                    state.micDevices.append(QStringLiteral("Microphone"));
                }
            }
        }
    }
}

PrivacyState PrivacyProbe::probe(bool forceDeepQuery) {
    PrivacyState state;

    const bool alsaActive = checkAlsaCapture(state);
    const bool v4lActive = checkV4L2Fast(state);

    if (forceDeepQuery || alsaActive || v4lActive) {
        resolvePipeWireMetadata(state);
    }

    return state;
}

} // namespace qs::plugins
