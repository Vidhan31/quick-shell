#include "PrivacyProbe.hpp"

#include <QByteArray>
#include <QHash>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QProcess>
#include <QRegularExpression>

#include <dirent.h>
#include <fcntl.h>
#include <limits.h>
#include <sys/stat.h>
#include <unistd.h>
#include <vector>

namespace qs::plugins {

bool PrivacyProbe::isPipeWireRunning() {
    const char *runtimeDir = getenv("XDG_RUNTIME_DIR");
    if (runtimeDir && *runtimeDir) {
        char socketPath[PATH_MAX];
        snprintf(socketPath, sizeof(socketPath), "%s/pipewire-0", runtimeDir);
        if (access(socketPath, F_OK) == 0) {
            return true;
        }
    }
    char fallbackPath[PATH_MAX];
    snprintf(fallbackPath, sizeof(fallbackPath), "/run/user/%u/pipewire-0", getuid());
    return access(fallbackPath, F_OK) == 0;
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
                        break;
                    }
                }
            }
        }
        closedir(cardDir);
        if (activeFound) break;
    }
    closedir(asoundDir);

    if (!activeFound) {
        return false;
    }

    // PipeWire manages ALSA capture when it is running, so only flag
    // direct capture for processes other than pipewire/wireplumber. Otherwise
    // suspend timeouts, loopbacks and noise filters read as false positives.
    if (isPipeWireRunning()) {
        DIR *procDir = opendir("/proc");
        if (!procDir) return false;

        const uid_t myUid = getuid();
        const int procFd = dirfd(procDir);
        struct dirent *procEntry;
        bool nonPwFound = false;

        while ((procEntry = readdir(procDir)) != nullptr) {
            if (procEntry->d_name[0] < '0' || procEntry->d_name[0] > '9') continue;

            struct stat st;
            if (fstatat(procFd, procEntry->d_name, &st, AT_SYMLINK_NOFOLLOW) != 0) continue;
            if (st.st_uid != myUid) continue;

            const int pid = atoi(procEntry->d_name);
            char fdPath[64];
            snprintf(fdPath, sizeof(fdPath), "/proc/%d/fd", pid);
            DIR *d = opendir(fdPath);
            if (!d) continue;

            const int dfd = dirfd(d);
            struct dirent *fe;
            char target[PATH_MAX];

            while ((fe = readdir(d)) != nullptr) {
                if (fe->d_name[0] == '.') continue;
                const ssize_t len = readlinkat(dfd, fe->d_name, target, sizeof(target) - 1);
                if (len > 12 && strncmp(target, "/dev/snd/pcm", 12) == 0 && target[len - 1] == 'c') {
                    target[len] = '\0';

                    char commPath[64];
                    snprintf(commPath, sizeof(commPath), "/proc/%d/comm", pid);
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
                    }

                    if (strcmp(commBuf, "pipewire") == 0 || strcmp(commBuf, "wireplumber") == 0) {
                        continue;
                    }

                    const QString appName = (commBuf[0] != '\0') ? QString::fromUtf8(commBuf) : QStringLiteral("ALSA App");
                    if (!state.micApps.contains(appName)) {
                        state.micApps.append(appName);
                    }
                    if (!state.micDevices.contains(QStringLiteral("Direct ALSA Capture"))) {
                        state.micDevices.append(QStringLiteral("Direct ALSA Capture"));
                    }
                    state.micActive = true;
                    nonPwFound = true;
                }
            }
            closedir(d);
        }
        closedir(procDir);
        return nonPwFound;
    }

    state.micActive = true;
    if (state.micDevices.isEmpty()) {
        state.micDevices.append(QStringLiteral("Microphone"));
    }
    return true;
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
        QJsonObject item = val.toObject();
        const QString type = item.value(QStringLiteral("type")).toString();
        if (type == QLatin1String("PipeWire:Interface:Node")) {
            const int id = item.value(QStringLiteral("id")).toInt();
            QJsonObject info = item.value(QStringLiteral("info")).toObject();
            if (info.contains(QStringLiteral("params"))) {
                info.remove(QStringLiteral("params"));
                item[QStringLiteral("info")] = info;
            }
            nodes.insert(id, item);
        } else if (type == QLatin1String("PipeWire:Interface:Link")) {
            links.push_back(item);
        }
    }

    for (const auto &link : links) {
        const QJsonObject info = link.value(QStringLiteral("info")).toObject();
        const QString linkState = info.value(QStringLiteral("state")).toString();
        const QJsonObject props = info.value(QStringLiteral("props")).toObject();

        int outId = props.value(QStringLiteral("link.output.node")).toInt();
        if (outId <= 0) outId = info.value(QStringLiteral("output-node-id")).toInt();

        int inId = props.value(QStringLiteral("link.input.node")).toInt();
        if (inId <= 0) inId = info.value(QStringLiteral("input-node-id")).toInt();

        const auto outIt = nodes.constFind(outId);
        const auto inIt = nodes.constFind(inId);
        if (outIt == nodes.constEnd() || inIt == nodes.constEnd()) {
            continue;
        }

        const QJsonObject outNode = *outIt;
        const QJsonObject inNode = *inIt;
        const QJsonObject outInfo = outNode.value(QStringLiteral("info")).toObject();
        const QJsonObject inInfo = inNode.value(QStringLiteral("info")).toObject();

        const QJsonObject outProps = outInfo.value(QStringLiteral("props")).toObject();
        const QJsonObject inProps = inInfo.value(QStringLiteral("props")).toObject();

        const QString outClass = outProps.value(QStringLiteral("media.class")).toString();
        const QString inClass = inProps.value(QStringLiteral("media.class")).toString();
        const QString inNodeState = inInfo.value(QStringLiteral("state")).toString();

        const bool linkIsActive = (linkState == QLatin1String("active"));
        const bool inIsRunning = (inNodeState == QLatin1String("running"));

        if (outClass == QLatin1String("Audio/Source") &&
            (inClass.startsWith(QLatin1String("Stream/Input/Audio")) || inClass == QLatin1String("Stream/Input"))) {

            const bool isMonitor = (outProps.value(QStringLiteral("device.class")).toString() == QLatin1String("monitor")) ||
                                   outProps.value(QStringLiteral("node.name")).toString().endsWith(QLatin1String(".monitor")) ||
                                   inProps.value(QStringLiteral("stream.is-monitor")).toBool() ||
                                   inProps.value(QStringLiteral("node.name")).toString().endsWith(QLatin1String(".monitor"));

            if (isMonitor) continue;

            const bool isActiveCapture = linkIsActive && (inIsRunning || inNodeState.isEmpty()) &&
                                         (inNodeState != QLatin1String("paused")) &&
                                         (inNodeState != QLatin1String("suspended"));

            if (!isActiveCapture) continue;

            QString appName = inProps.value(QStringLiteral("application.name")).toString();
            if (appName.isEmpty()) appName = inProps.value(QStringLiteral("pipewire.access.portal.app_id")).toString();
            if (appName.isEmpty()) appName = inProps.value(QStringLiteral("application.process.binary")).toString();
            if (appName.isEmpty()) appName = inProps.value(QStringLiteral("node.name")).toString();
            if (appName.isEmpty()) appName = inNode.value(QStringLiteral("info")).toObject().value(QStringLiteral("name")).toString();
            if (appName.isEmpty()) appName = QStringLiteral("Recording App");

            static const QStringList ignoredApps = {
                QStringLiteral("pavucontrol"),
                QStringLiteral("plasma-pa"),
                QStringLiteral("systemsettings"),
                QStringLiteral("gnome-control-center")
            };
            bool ignoreApp = false;
            for (const auto &ign : ignoredApps) {
                if (appName.compare(ign, Qt::CaseInsensitive) == 0) {
                    ignoreApp = true;
                    break;
                }
            }
            if (ignoreApp) continue;

            state.micActive = true;

            QString sourceDesc = outProps.value(QStringLiteral("node.description")).toString();
            if (sourceDesc.isEmpty()) sourceDesc = outProps.value(QStringLiteral("node.nick")).toString();
            if (sourceDesc.isEmpty()) sourceDesc = QStringLiteral("Microphone");

            if (!state.micApps.contains(appName)) state.micApps.append(appName);
            if (!state.micDevices.contains(sourceDesc)) state.micDevices.append(sourceDesc);
        }

        // Plasma task-manager hover previews create transient KWin screencast
        // PipeWire streams (Stream/Input/Video consumed by plasmashell) which
        // must NOT be treated as camera use.
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
                static const QStringList ignoredApps = {
                    QStringLiteral("pavucontrol"),
                    QStringLiteral("plasma-pa"),
                    QStringLiteral("systemsettings"),
                    QStringLiteral("gnome-control-center")
                };
                bool ignoreApp = false;
                for (const auto &ign : ignoredApps) {
                    if (currApp.compare(ign, Qt::CaseInsensitive) == 0) {
                        ignoreApp = true;
                        break;
                    }
                }
                if (ignoreApp) continue;

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

    const bool pwRunning = isPipeWireRunning();
    if (pwRunning || forceDeepQuery) {
        resolvePipeWireMetadata(state);
    }

    if (!state.micActive) {
        checkAlsaCapture(state);
    }

    return state;
}

} // namespace qs::plugins
