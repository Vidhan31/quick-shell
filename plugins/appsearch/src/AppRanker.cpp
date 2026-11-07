#include "AppRanker.hpp"

#include <QStringList>
#include <QVariantMap>

#include <algorithm>
#include <vector>

namespace qs::plugins {

AppRanker::AppRanker(QObject *parent)
    : QObject(parent)
{
}

void AppRanker::setApps(const QVariantList &apps) {
    m_apps.clear();
    m_apps.reserve(apps.size());
    for (const QVariant &appVar : apps) {
        QVariantMap row = appVar.toMap();
        AppEntry entry;
        entry.id = row.value(QStringLiteral("id")).toString();
        entry.name = row.value(QStringLiteral("name")).toString();
        entry.nameLc = row.value(QStringLiteral("nameLc")).toString();
        if (entry.nameLc.isEmpty()) {
            entry.nameLc = entry.name.toLower();
        }
        entry.generic = row.value(QStringLiteral("generic")).toString();
        entry.genericLc = row.value(QStringLiteral("genericLc")).toString();
        if (entry.genericLc.isEmpty() && !entry.generic.isEmpty()) {
            entry.genericLc = entry.generic.toLower();
        }
        entry.category = row.value(QStringLiteral("category")).toString();
        entry.categoryLc = row.value(QStringLiteral("categoryLc")).toString();
        if (entry.categoryLc.isEmpty() && !entry.category.isEmpty()) {
            entry.categoryLc = entry.category.toLower();
        }
        entry.kwLc = row.value(QStringLiteral("kwLc")).toString();
        entry.rawMap = std::move(row);
        m_apps.push_back(std::move(entry));
    }
}

QVariantList AppRanker::rank(const QString &query, int maxResults) {
    const QString q = query.trimmed().toLower();
    if (q.isEmpty()) {
        int limit = (maxResults > 0) ? std::min(maxResults, static_cast<int>(m_apps.size())) : static_cast<int>(m_apps.size());
        QVariantList results;
        results.reserve(limit);
        for (int i = 0; i < limit; ++i) {
            QVariantMap m = m_apps[i].rawMap;
            m.insert(QStringLiteral("tier"), 0);
            m.insert(QStringLiteral("hlName"), QVariantList());
            m.insert(QStringLiteral("hlGeneric"), QVariantList());
            results.append(m);
        }
        return results;
    }

    struct Candidate {
        const AppEntry *app{nullptr};
        int tier{5};
        QVariantList hlName;
        QVariantList hlGeneric;
    };

    const int qLen = static_cast<int>(q.length());
    const bool hasSpace = q.contains(QLatin1Char(' '));
    const QStringList words = hasSpace ? q.split(QLatin1Char(' '), Qt::SkipEmptyParts) : QStringList();

    std::vector<Candidate> candidates;
    candidates.reserve(m_apps.size());

    for (const auto &app : m_apps) {
        int tier = -1;
        QVariantList hlName;
        QVariantList hlGeneric;

        if (app.nameLc == q) {
            tier = 1;
            hlName.append(QVariantList{0, qLen});
        } else if (app.nameLc.startsWith(q)) {
            tier = 2;
            hlName.append(QVariantList{0, qLen});
        } else {
            int idx = app.nameLc.indexOf(q);
            if (idx > 0) {
                tier = 3;
                hlName.append(QVariantList{idx, idx + qLen});
            } else if (!app.genericLc.isEmpty() && (app.genericLc.indexOf(q) >= 0)) {
                tier = 4;
                int gi = app.genericLc.indexOf(q);
                hlGeneric.append(QVariantList{gi, gi + qLen});
            } else if (!app.categoryLc.isEmpty() && (app.categoryLc.indexOf(q) >= 0)) {
                tier = 4;
            } else if (!app.kwLc.isEmpty() && app.kwLc.contains(q)) {
                tier = 5;
            } else if (hasSpace && !words.isEmpty()) {
                const QString haystack = app.nameLc + QLatin1Char(' ') + app.genericLc + QLatin1Char(' ') + app.categoryLc + QLatin1Char(' ') + app.kwLc;
                bool allMatch = true;
                for (const QString &w : words) {
                    if (!haystack.contains(w)) {
                        allMatch = false;
                        break;
                    }
                }
                if (allMatch) {
                    tier = 5;
                }
            }
        }

        if (tier >= 1) {
            Candidate c;
            c.app = &app;
            c.tier = tier;
            c.hlName = std::move(hlName);
            c.hlGeneric = std::move(hlGeneric);
            candidates.push_back(std::move(c));
        }
    }

    if (candidates.empty()) {
        return QVariantList();
    }

    int limit = (maxResults > 0) ? std::min(maxResults, static_cast<int>(candidates.size())) : static_cast<int>(candidates.size());
    if (maxResults > 0 && limit < static_cast<int>(candidates.size())) {
        std::partial_sort(candidates.begin(), candidates.begin() + limit, candidates.end(),
            [](const Candidate &a, const Candidate &b) {
                if (a.tier != b.tier) return a.tier < b.tier;
                if (a.app->nameLc != b.app->nameLc) return a.app->nameLc < b.app->nameLc;
                return a.app->id < b.app->id;
            });
    } else {
        std::sort(candidates.begin(), candidates.end(),
            [](const Candidate &a, const Candidate &b) {
                if (a.tier != b.tier) return a.tier < b.tier;
                if (a.app->nameLc != b.app->nameLc) return a.app->nameLc < b.app->nameLc;
                return a.app->id < b.app->id;
            });
    }

    QVariantList results;
    results.reserve(limit);
    for (int i = 0; i < limit; ++i) {
        auto &c = candidates[i];
        QVariantMap row = c.app->rawMap;
        row.insert(QStringLiteral("tier"), c.tier);
        row.insert(QStringLiteral("hlName"), std::move(c.hlName));
        row.insert(QStringLiteral("hlGeneric"), std::move(c.hlGeneric));
        results.append(std::move(row));
    }
    return results;
}

QVariantList AppRanker::rank(const QVariantList &apps, const QString &query, int maxResults) {
    if (m_apps.empty() || m_apps.size() != static_cast<size_t>(apps.size())) {
        setApps(apps);
    }
    return rank(query, maxResults);
}

} // namespace qs::plugins
