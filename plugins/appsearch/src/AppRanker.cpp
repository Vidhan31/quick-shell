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

QVariantList AppRanker::rank(const QVariantList &apps, const QString &query, int maxResults) {
    const QString q = query.trimmed().toLower();
    if (q.isEmpty()) {
        int limit = std::min(maxResults, static_cast<int>(apps.size()));
        QVariantList results;
        results.reserve(limit);
        for (int i = 0; i < limit; ++i) {
            QVariantMap m = apps.at(i).toMap();
            m.insert(QStringLiteral("tier"), 0);
            m.insert(QStringLiteral("hlName"), QVariantList());
            m.insert(QStringLiteral("hlGeneric"), QVariantList());
            results.append(m);
        }
        return results;
    }

    struct Candidate {
        QVariantMap row;
        QString nameLc;
        int tier{5};
        QVariantList hlName;
        QVariantList hlGeneric;
    };

    const int qLen = static_cast<int>(q.length());
    const bool hasSpace = q.contains(QLatin1Char(' '));
    const QStringList words = hasSpace ? q.split(QLatin1Char(' '), Qt::SkipEmptyParts) : QStringList();

    std::vector<Candidate> candidates;
    candidates.reserve(apps.size());

    for (const QVariant &appVar : apps) {
        QVariantMap row = appVar.toMap();
        QString name = row.value(QStringLiteral("name")).toString();
        QString nameLc = row.value(QStringLiteral("nameLc")).toString();
        if (nameLc.isEmpty()) {
            nameLc = name.toLower();
        }
        QString genericLc = row.value(QStringLiteral("genericLc")).toString();
        if (genericLc.isEmpty()) {
            QString generic = row.value(QStringLiteral("generic")).toString();
            if (!generic.isEmpty()) genericLc = generic.toLower();
        }
        QString categoryLc = row.value(QStringLiteral("categoryLc")).toString();
        if (categoryLc.isEmpty()) {
            QString category = row.value(QStringLiteral("category")).toString();
            if (!category.isEmpty()) categoryLc = category.toLower();
        }
        QString kwLc = row.value(QStringLiteral("kwLc")).toString();

        int tier = -1;
        QVariantList hlName;
        QVariantList hlGeneric;

        if (nameLc == q) {
            tier = 1;
            hlName.append(QVariantList{0, qLen});
        } else if (nameLc.startsWith(q)) {
            tier = 2;
            hlName.append(QVariantList{0, qLen});
        } else {
            int idx = nameLc.indexOf(q);
            if (idx > 0) {
                tier = 3;
                hlName.append(QVariantList{idx, idx + qLen});
            } else if (!genericLc.isEmpty() && (genericLc.indexOf(q) >= 0)) {
                tier = 4;
                int gi = genericLc.indexOf(q);
                hlGeneric.append(QVariantList{gi, gi + qLen});
            } else if (!categoryLc.isEmpty() && (categoryLc.indexOf(q) >= 0)) {
                tier = 4;
            } else if (!kwLc.isEmpty() && kwLc.contains(q)) {
                tier = 5;
            } else if (hasSpace && !words.isEmpty()) {
                const QString haystack = nameLc + QLatin1Char(' ') + genericLc + QLatin1Char(' ') + categoryLc + QLatin1Char(' ') + kwLc;
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
            c.row = std::move(row);
            c.nameLc = std::move(nameLc);
            c.tier = tier;
            c.hlName = std::move(hlName);
            c.hlGeneric = std::move(hlGeneric);
            candidates.push_back(std::move(c));
        }
    }

    if (candidates.empty()) {
        return QVariantList();
    }

    int limit = std::min(maxResults, static_cast<int>(candidates.size()));
    std::partial_sort(candidates.begin(), candidates.begin() + limit, candidates.end(),
        [](const Candidate &a, const Candidate &b) {
            if (a.tier != b.tier) return a.tier < b.tier;
            if (a.nameLc != b.nameLc) return a.nameLc < b.nameLc;
            return a.row.value(QStringLiteral("id")).toString() < b.row.value(QStringLiteral("id")).toString();
        });

    QVariantList results;
    results.reserve(limit);
    for (int i = 0; i < limit; ++i) {
        auto &c = candidates[i];
        c.row.insert(QStringLiteral("tier"), c.tier);
        c.row.insert(QStringLiteral("hlName"), c.hlName);
        c.row.insert(QStringLiteral("hlGeneric"), c.hlGeneric);
        results.append(std::move(c.row));
    }
    return results;
}

} // namespace qs::plugins
