#pragma once

#include <QList>
#include <QString>
#include <QVariantList>
#include <QVariantMap>

namespace qs::plugins {

inline QString formatBytes(qint64 bytes)
{
    if (bytes < 0) {
        return QString();
    }
    if (bytes < 1024) {
        return QStringLiteral("%1 B").arg(bytes);
    }
    if (bytes < 1024 * 1024) {
        return QStringLiteral("%1 KB").arg(bytes / 1024.0, 0, 'f', 1);
    }
    if (bytes < 1024 * 1024 * 1024) {
        return QStringLiteral("%1 MB").arg(bytes / 1024.0 / 1024.0, 0, 'f', 1);
    }
    return QStringLiteral("%1 GB").arg(bytes / 1024.0 / 1024.0 / 1024.0, 0, 'f', 2);
}

struct DockerContainer {
    QString id;
    QString shortId;
    QString name; // first entry of Names, leading '/' stripped
    QString image;
    QString command;
    qint64 created{0};
    QString state;  // running, exited, paused, created, dead ...
    QString status; // human string e.g. "Up 3 hours"
    QString health; // healthy/unhealthy/starting/none (v1.52+ only)
    QVariantMap labels;

    // Compose grouping (empty when standalone)
    QString project;
    QString service;
    QString workingDir;
    QString configFiles;
    qint64 containerNumber{0};

    bool operator==(const DockerContainer &) const = default;

    [[nodiscard]] bool isRunning() const { return state == QStringLiteral("running"); }
    [[nodiscard]] bool isStandalone() const { return project.isEmpty(); }

    [[nodiscard]] QVariantMap toMap() const {
        QVariantMap m;
        m[QStringLiteral("id")] = id;
        m[QStringLiteral("short_id")] = shortId;
        m[QStringLiteral("name")] = name;
        m[QStringLiteral("image")] = image;
        m[QStringLiteral("command")] = command;
        m[QStringLiteral("created")] = created;
        m[QStringLiteral("state")] = state;
        m[QStringLiteral("status")] = status;
        m[QStringLiteral("health")] = health;
        m[QStringLiteral("labels")] = labels;
        m[QStringLiteral("project")] = project;
        m[QStringLiteral("service")] = service;
        m[QStringLiteral("working_dir")] = workingDir;
        m[QStringLiteral("config_files")] = configFiles;
        m[QStringLiteral("container_number")] = containerNumber;
        m[QStringLiteral("is_running")] = isRunning();
        m[QStringLiteral("is_standalone")] = isStandalone();
        return m;
    }
};

struct DockerProject {
    QString name;
    QString workingDir;
    QString configFiles;
    int running{0};
    int total{0};
    QList<DockerContainer> members; // grouped in C++ — QML just displays

    bool operator==(const DockerProject &) const = default;

    [[nodiscard]] QVariantMap toMap() const {
        QVariantMap m;
        m[QStringLiteral("name")] = name;
        m[QStringLiteral("working_dir")] = workingDir;
        m[QStringLiteral("config_files")] = configFiles;
        m[QStringLiteral("running")] = running;
        m[QStringLiteral("total")] = total;
        QVariantList ml;
        ml.reserve(members.size());
        for (const auto &c : members) {
            ml.append(c.toMap());
        }
        m[QStringLiteral("containers")] = ml;
        return m;
    }
};

struct DockerImage {
    QString id;
    QString shortId;
    QVariantList repoTags;
    qint64 size{0};
    qint64 created{0};

    bool operator==(const DockerImage &) const = default;

    [[nodiscard]] QVariantMap toMap() const {
        QVariantMap m;
        m[QStringLiteral("id")] = id;
        m[QStringLiteral("short_id")] = shortId;
        m[QStringLiteral("repo_tags")] = repoTags;
        m[QStringLiteral("size")] = size;
        m[QStringLiteral("size_text")] = formatBytes(size);
        m[QStringLiteral("created")] = created;
        return m;
    }
};

struct DockerVolume {
    QString name;
    QString driver;
    QString mountpoint;
    QString scope;

    bool operator==(const DockerVolume &) const = default;

    [[nodiscard]] QVariantMap toMap() const {
        QVariantMap m;
        m[QStringLiteral("name")] = name;
        m[QStringLiteral("driver")] = driver;
        m[QStringLiteral("mountpoint")] = mountpoint;
        m[QStringLiteral("scope")] = scope;
        return m;
    }
};

struct DockerState {
    bool ok{false};
    bool connected{false};
    QString serverVersion;
    QString apiVersion;
    QString socketPath;
    QString error;

    int running{0};
    int paused{0};
    int stopped{0};
    int imagesCount{0};

    QList<DockerContainer> containers;
    QList<DockerProject> projects;
    QList<DockerContainer> standalone;
    QList<DockerImage> images;
    QList<DockerVolume> volumes;

    QVariantMap df; // raw /system/df object (ActiveCount/TotalSize/...)
    QVariantList cleanup; // C++-computed rows: {kind,label,detail}
    QString reclaimSummary; // e.g. "5.10 GB reclaimable", empty when nothing

    bool operator==(const DockerState &) const = default;

    [[nodiscard]] QVariantMap toMap() const {
        QVariantMap m;
        m[QStringLiteral("ok")] = ok;
        m[QStringLiteral("connected")] = connected;
        m[QStringLiteral("server_version")] = serverVersion;
        m[QStringLiteral("api_version")] = apiVersion;
        m[QStringLiteral("socket_path")] = socketPath;
        m[QStringLiteral("error")] = error;
        m[QStringLiteral("running")] = running;
        m[QStringLiteral("paused")] = paused;
        m[QStringLiteral("stopped")] = stopped;
        m[QStringLiteral("images_count")] = imagesCount;

        QVariantList cl;
        cl.reserve(containers.size());
        for (const auto &c : containers) {
            cl.append(c.toMap());
        }
        m[QStringLiteral("containers")] = cl;

        QVariantList pl;
        pl.reserve(projects.size());
        for (const auto &p : projects) {
            pl.append(p.toMap());
        }
        m[QStringLiteral("projects")] = pl;

        QVariantList sl;
        sl.reserve(standalone.size());
        for (const auto &c : standalone) {
            sl.append(c.toMap());
        }
        m[QStringLiteral("standalone")] = sl;

        QVariantList il;
        il.reserve(images.size());
        for (const auto &i : images) {
            il.append(i.toMap());
        }
        m[QStringLiteral("images")] = il;

        QVariantList vl;
        vl.reserve(volumes.size());
        for (const auto &v : volumes) {
            vl.append(v.toMap());
        }
        m[QStringLiteral("volumes")] = vl;

        m[QStringLiteral("df")] = df;
        m[QStringLiteral("cleanup")] = cleanup;
        m[QStringLiteral("reclaim_summary")] = reclaimSummary;
        return m;
    }
};

} // namespace qs::plugins
