#include "NotificationModel.hpp"
#include "NotificationStore.hpp"

#include <QGuiApplication>
#include <QQmlEngine>
#include <QQuickItem>
#include <QTextStream>
#include <QVariantMap>

namespace {

int g_failures = 0;
void check(QTextStream &out, const char *name, bool cond) {
    out << (cond ? "PASS " : "FAIL ") << name << "\n";
    if (!cond) {
        ++g_failures;
    }
}

QVariantMap snap(const QString &app, const QString &summary, int urgency = 1, const QString &category = QString()) {
    return {
        {QStringLiteral("appName"), app},
        {QStringLiteral("appIcon"), QString()},
        {QStringLiteral("summary"), summary},
        {QStringLiteral("body"), QStringLiteral("b")},
        {QStringLiteral("image"), QString()},
        {QStringLiteral("desktopEntry"), QString()},
        {QStringLiteral("urgency"), urgency},
        {QStringLiteral("actions"), QVariantList{}},
        {QStringLiteral("resident"), false},
        {QStringLiteral("transient"), false},
        {QStringLiteral("hasInlineReply"), false},
        {QStringLiteral("inlineReplyPlaceholder"), QString()},
        {QStringLiteral("hasActionIcons"), false},
        {QStringLiteral("category"), category},
        {QStringLiteral("soundName"), QString()},
        {QStringLiteral("soundFile"), QString()},
        {QStringLiteral("suppressSound"), false},
    };
}

} // namespace

// CLI driver: exercises timeout policy, replaces-id, transient,
// DND, expiry and grouping without Quickshell, then boots an offscreen
// QQmlEngine to prove QML registration, properties and signals work.
int main(int argc, char **argv) {
    qputenv("QT_QPA_PLATFORM", QByteArrayLiteral("offscreen"));
    QGuiApplication app(argc, argv);
    QTextStream out(stdout);
    using qs::plugins::notifications::NotificationStore;
    NotificationStore store;

    store.ingestSnapshot(snap(QStringLiteral("TestApp"), QStringLiteral("Hello"), 1, QStringLiteral("im")), 1, QVariant(), false);
    store.ingestSnapshot(snap(QStringLiteral("TestApp"), QStringLiteral("Hello")), 1, QVariant(), false); // replaces-id
    QVariantMap transientSnap = snap(QStringLiteral("TestApp"), QStringLiteral("T"));
    transientSnap[QStringLiteral("transient")] = true;
    store.ingestSnapshot(transientSnap, 2, QVariant(), false);
    store.handleClosed(2, 1); // expired -> toast only
    store.setDnd(true);
    store.addTestNotification(QStringLiteral("Manual"), QStringLiteral("Body"), QStringLiteral("ManualApp"), 2);

    check(out, "total==2", store.totalCount() == 2);
    check(out, "models==lists", store.historyModel()->rowCount() == store.notifications().size()
                                   && store.toastModel()->rowCount() == store.activeToasts().size());
    check(out, "timeout_call==15000", NotificationStore::timeoutForCategory(QStringLiteral("call"), 1) == 15000);
    check(out, "timeout_im==7000", NotificationStore::timeoutForCategory(QStringLiteral("im"), 1) == 7000);
    check(out, "timeout_transfer==3500", NotificationStore::timeoutForCategory(QStringLiteral("transfer"), 1) == 3500);

    // ---- Offscreen QML integration ----
    QQmlEngine engine;
    engine.addImportPath(QCoreApplication::applicationDirPath() + QStringLiteral("/imports"));
    static const char qml[] = R"QML(
import QtQuick 2.0
import Quickshell.Plugins.Notifications
Item {
  objectName: "qmlRoot"
  NotificationStore {
    id: s
    objectName: "qmlStore"
    maxNotifications: 100
  }
  property alias store: s
  Repeater {
    objectName: "historyRepeater"
    model: s.historyModel
  }
  Repeater {
    objectName: "toastRepeater"
    model: s.toastModel
  }
}
)QML";
    QObject *rootObj = nullptr;
    {
        QQmlComponent comp(&engine);
        comp.setData(qml, QUrl());
        if (comp.isError()) {
            for (const auto &e : comp.errors()) {
                out << "QML ERROR: " << e.toString() << "\n";
            }
            return 1;
        }
        rootObj = comp.create();
        if (comp.isError()) {
            for (const auto &e : comp.errors()) {
                out << "QML CREATE ERROR: " << e.toString() << "\n";
            }
        }
        if (!rootObj) {
            out << "QML create failed\n";
            return 1;
        }
    }
    auto *qmlStore = rootObj->findChild<NotificationStore *>(QStringLiteral("qmlStore"));
    check(out, "qml store created", qmlStore != nullptr);
    if (!qmlStore) {
        out << "root class: " << rootObj->metaObject()->className() << " children: " << rootObj->children().size() << "\n";
        for (QObject *c : rootObj->children()) {
            out << "  child: " << c->metaObject()->className() << " name=" << c->objectName() << "\n";
        }
        return 1;
    }
    int dismissCount = 0;
    int expireCount = 0;
    QObject::connect(qmlStore, &NotificationStore::dismissRequested, [&](int) { ++dismissCount; });
    QObject::connect(qmlStore, &NotificationStore::expireRequested, [&](int) { ++expireCount; });

    qmlStore->ingestSnapshot(snap(QStringLiteral("QmlApp"), QStringLiteral("Hi")), 11, QVariant(), false);
    check(out, "qml ingest", qmlStore->property("totalCount").toInt() == 1 && qmlStore->property("unreadCount").toInt() == 1);
    check(out, "qml lists", qmlStore->property("notifications").toList().size() == 1
                               && qmlStore->property("activeToasts").toList().size() == 1
                               && qmlStore->property("groupedList").toList().size() == 1);
    auto *histRepeater = rootObj->findChild<QObject *>(QStringLiteral("historyRepeater"));
    // NOTE: Repeater item creation is polish-deferred (no scene graph
    // offscreen), so assert model content + model wiring instead of count.
    check(out, "qml history model wired", histRepeater && histRepeater->property("model").value<QObject *>() != nullptr);
    check(out, "qml history model content", qmlStore->historyModel()->rowCount() == 1);
    check(out, "qml toast model content", qmlStore->toastModel()->rowCount() == 1);

    bool invoked = false;
    QVariant ret;
    QMetaObject::invokeMethod(qmlStore, "sendInlineReply", Q_RETURN_ARG(QVariant, ret),
                              Q_ARG(QVariant, 11), Q_ARG(QVariant, QStringLiteral("x")));
    check(out, "qml reply rejected w/o flag", ret.toBool() == false);
    Q_UNUSED(invoked);

    qmlStore->dismissNotification(11);
    check(out, "qml dismissRequested emitted", dismissCount == 1);
    check(out, "qml dismiss clears", qmlStore->property("totalCount").toInt() == 0);

    qmlStore->ingestSnapshot(snap(QStringLiteral("QmlApp"), QStringLiteral("Tmp")), 12, QVariant(), false);
    qmlStore->dismissToast(12);
    check(out, "qml dismissToast drops toast", qmlStore->property("activeToasts").toList().isEmpty());

    out << (g_failures == 0 ? "PROBE OK\n" : "PROBE FAILURES\n");
    return g_failures == 0 ? 0 : 1;
}
