pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Quickshell.Plugins.Docker
import "../theme"
import "../components"

Item {
  id: root

  property var docker: null
  property DockerMonitor monitor: (docker && docker.monitor) ? docker.monitor : docker
  readonly property DockerMonitor activeMonitor: monitor

  signal triggerRefresh()
  implicitWidth: Theme.popupWidthLg
  readonly property int preferredHeight: Math.min(700, 32 + bodyCol.height)
  property int popupHeight: 500

  function syncHeight() {
    if (bodyCol.height > 0)
      popupHeight = preferredHeight;
  }
  onPreferredHeightChanged: {
    if (bodyCol.height > 0)
      popupHeight = preferredHeight;
  }
  implicitHeight: popupHeight

  readonly property bool connected: activeMonitor ? activeMonitor.connected : false
  readonly property bool busy: activeMonitor ? activeMonitor.isBusy : false
  readonly property string busyContext: activeMonitor ? activeMonitor.busyContext : ""
  readonly property string busyLabel: activeMonitor ? activeMonitor.busyLabel : ""
  readonly property var projects: activeMonitor ? activeMonitor.projects : []
  readonly property var standalone: activeMonitor ? activeMonitor.standalone : []
  readonly property var images: activeMonitor ? activeMonitor.images : []
  readonly property var volumes: activeMonitor ? activeMonitor.volumes : []
  readonly property var cleanup: activeMonitor ? activeMonitor.cleanup : []
  readonly property string reclaimSummary: activeMonitor ? activeMonitor.reclaimSummary : ""
  readonly property string serverVersion: activeMonitor ? activeMonitor.serverVersion : ""
  readonly property string lastError: activeMonitor ? activeMonitor.lastError : ""
  readonly property int runningCount: activeMonitor ? activeMonitor.runningCount : 0
  readonly property int totalCount: activeMonitor ? activeMonitor.totalCount : 0

  property string toastMsg: ""
  property string logViewId: ""
  property string logViewName: ""
  property int logTail: 200

  function showToast(msg: string): void {
    toastMsg = msg;
    toastTimer.restart();
  }

  Timer {
    id: toastTimer
    interval: 3500
    repeat: false
    onTriggered: root.toastMsg = ""
  }

  function stateColor(state: string): color {
    const s = (state || "").toLowerCase();
    if (s === "running")
      return Theme.green;
    if (s === "paused" || s === "restarting")
      return Theme.amber;
    if (s === "dead")
      return Theme.red;
    return Theme.ink3;
  }

  function stateWord(state: string): string {
    const s = (state || "").toLowerCase();
    if (s === "running")
      return "Running";
    if (s === "paused")
      return "Paused";
    if (s === "restarting")
      return "Restarting";
    if (s === "exited")
      return "Exited";
    if (s === "created")
      return "Created";
    if (s === "dead")
      return "Dead";
    if (s === "removing")
      return "Removing";
    return state || "Unknown";
  }

  function openLogs(id: string, name: string): void {
    root.logViewId = id;
    root.logViewName = name;
    logView.visible = true;
    if (root.activeMonitor)
      root.activeMonitor.fetchLogs(id, root.logTail);
  }

  Connections {
    target: root.activeMonitor
    function onActionCompleted(ok: bool, output: string, error: string, context: string): void {
      if (ok)
        root.showToast(output.length > 0 ? output : "Done (" + context + ")");
      else
        root.showToast("Failed: " + (error.length > 0 ? error : context));
    }
    function onLogsReady(): void {
    }
  }

  PopupCard {
    anchors.fill: parent
    padding: 0
  }

  ColumnLayout {
    id: bodyCol
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.top: parent.top
    anchors.margins: Theme.cardPadding
    spacing: 0

    RowLayout {
      Layout.fillWidth: true
      Layout.preferredHeight: 36
      spacing: 8

      Column {
        Layout.fillWidth: true
        Layout.alignment: Qt.AlignVCenter
        spacing: 0
        Text {
          text: "Docker"
          font.pixelSize: Theme.fontMd
          font.weight: Font.DemiBold
          color: Theme.ink1
        }
        Text {
          text: {
            if (root.busy && root.busyLabel.length > 0)
              return root.busyLabel;
            if (!root.connected)
              return root.lastError.length > 0 ? root.lastError : "Daemon unreachable";
            const v = root.serverVersion.length > 0 ? ("v" + root.serverVersion + " · ") : "";
            return v + root.runningCount + " running / " + root.totalCount + " total";
          }
          font.pixelSize: Theme.fontXs
          color: root.busy ? Theme.accent : (root.connected ? Theme.ink3 : Theme.err)
          elide: Text.ElideRight
        }
      }

      IconBtn {
        glyph: "󰑓"
        fs: Theme.iconBase
        tooltip: "Refresh containers"
        spinning: root.busy
        onClicked: {
          if (root.activeMonitor)
            root.activeMonitor.refresh();
          root.triggerRefresh();
        }
      }
    }

    Item {
      Layout.fillWidth: true
      Layout.preferredHeight: 14
    }

    Rectangle {
      Layout.fillWidth: true
      visible: !root.connected
      radius: Theme.radiusBase
      color: Theme.surface
      Layout.preferredHeight: offlineText.height + 20
      Text {
        id: offlineText
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        anchors.leftMargin: 12
        anchors.rightMargin: 12
        wrapMode: Text.Wrap
        font.pixelSize: Theme.fontSm
        color: Theme.red
        text: "Daemon unreachable at " + (root.activeMonitor ? root.activeMonitor.socketPath : "?")
      }
    }

    Item {
      Layout.fillWidth: true
      Layout.preferredHeight: root.connected ? 0 : 14
      visible: !root.connected
    }

    Flickable {
      Layout.fillWidth: true
      Layout.preferredHeight: Math.min(460, contentCol.height)
      contentHeight: contentCol.height
      clip: true

      Column {
        id: contentCol
        width: parent.width
        spacing: 14

        Column {
          width: parent.width
          spacing: 4
          visible: root.projects.length > 0
          SectionHead {
            width: parent.width
            label: "Compose projects · " + root.projects.length
          }
          Repeater {
            model: root.projects
            delegate: ProjectGroup {
              required property var modelData
              width: parent.width
              project: modelData
              members: modelData.containers
            }
          }
        }

        Column {
          width: parent.width
          spacing: 4
          SectionHead {
            width: parent.width
            label: "Standalone · " + root.standalone.length
          }
          SectionCard {
            width: parent.width
            visible: root.standalone.length > 0
            height: standaloneList.height
            Column {
              id: standaloneList
              width: parent.width
              Repeater {
                model: root.standalone
                delegate: ContainerRow {
                  required property var modelData
                  required property int index
                  width: parent.width
                  info: modelData
                  showTopLine: index > 0
                }
              }
            }
          }
          Text {
            visible: root.standalone.length === 0
            width: parent.width
            leftPadding: 2
            font.pixelSize: Theme.fontSm
            color: Theme.ink3
            text: "No standalone containers"
          }
        }

        Column {
          width: parent.width
          spacing: 4
          SectionHead {
            width: parent.width
            label: "Images · " + root.images.length
          }
          SectionCard {
            width: parent.width
            visible: root.images.length > 0
            height: imageList.height
            Column {
              id: imageList
              width: parent.width
              Repeater {
                model: root.images
                delegate: Column {
                  id: imageRow
                  required property var modelData
                  required property int index
                  width: parent.width
                  spacing: 0
                  Hairline {
                    visible: imageRow.index > 0
                    width: parent.width
                  }
                  RowLayout {
                    width: parent.width
                    height: 40
                    spacing: 8
                  Column {
                    Layout.fillWidth: true
                    Layout.leftMargin: 12
                    spacing: 1
                    Text {
                      width: parent.width
                      text: (imageRow.modelData.repo_tags && imageRow.modelData.repo_tags.length > 0) ? imageRow.modelData.repo_tags[0] : imageRow.modelData.short_id
                      font.pixelSize: Theme.fontBase
                      font.family: Theme.mono
                      color: Theme.ink1
                      elide: Text.ElideRight
                    }
                    Text {
                      width: parent.width
                      text: imageRow.modelData.size_text
                      font.pixelSize: Theme.fontXs
                      font.family: Theme.mono
                      color: Theme.ink3
                    }
                  }
                  TextBtn {
                    Layout.rightMargin: 8
                    text: "Remove"
                    fs: Theme.fontSm
                    fg: Theme.red
                    enabledBtn: !(root.busy && (root.busyContext === "remove-image:" + ((imageRow.modelData.repo_tags && imageRow.modelData.repo_tags.length > 0) ? imageRow.modelData.repo_tags[0] : imageRow.modelData.id)))
                      onClicked: root.activeMonitor.removeImage((imageRow.modelData.repo_tags && imageRow.modelData.repo_tags.length > 0) ? imageRow.modelData.repo_tags[0] : imageRow.modelData.id, false)
                    }
                  }
                }
              }
            }
          }
          Text {
            visible: root.images.length === 0
            width: parent.width
            leftPadding: 2
            font.pixelSize: Theme.fontSm
            color: Theme.ink3
            text: "No images"
          }
        }

        Column {
          width: parent.width
          spacing: 4
          SectionHead {
            width: parent.width
            label: "Volumes · " + root.volumes.length
          }
          SectionCard {
            width: parent.width
            visible: root.volumes.length > 0
            height: volumeList.height
            Column {
              id: volumeList
              width: parent.width
              Repeater {
                model: root.volumes
                delegate: Column {
                  id: volumeRow
                  required property var modelData
                  required property int index
                  width: parent.width
                  spacing: 0
                  Hairline {
                    visible: volumeRow.index > 0
                    width: parent.width
                  }
                  RowLayout {
                    width: parent.width
                    height: 40
                    spacing: 8
                  Column {
                    Layout.fillWidth: true
                    Layout.leftMargin: 12
                    spacing: 1
                    Text {
                      width: parent.width
                      text: volumeRow.modelData.name
                      font.pixelSize: Theme.fontBase
                      font.family: Theme.mono
                      color: Theme.ink1
                      elide: Text.ElideRight
                    }
                    Text {
                      width: parent.width
                      visible: (volumeRow.modelData.driver || "").length > 0
                      text: volumeRow.modelData.driver
                      font.pixelSize: Theme.fontXs
                      color: Theme.ink3
                    }
                  }
                  TextBtn {
                    Layout.rightMargin: 8
                    text: "Remove"
                    fs: Theme.fontSm
                    fg: Theme.red
                    enabledBtn: !(root.busy && root.busyContext === "remove-volume:" + volumeRow.modelData.name)
                      onClicked: root.activeMonitor.removeVolume(volumeRow.modelData.name, false)
                    }
                  }
                }
              }
            }
          }
          Text {
            visible: root.volumes.length === 0
            width: parent.width
            leftPadding: 2
            font.pixelSize: Theme.fontSm
            color: Theme.ink3
            text: "No volumes"
          }
        }

        Column {
          width: parent.width
          spacing: 4
          SectionHead {
            width: parent.width
            label: "Cleanup unused" + (root.reclaimSummary.length > 0 ? " · " + root.reclaimSummary : "")
          }
          SectionCard {
            width: parent.width
            height: cleanupList.height
            Column {
              id: cleanupList
              width: parent.width
              Repeater {
                model: root.cleanup
                delegate: Column {
                  id: cleanupRow
                  required property var modelData
                  required property int index
                  width: parent.width
                  spacing: 0
                  Hairline {
                    visible: cleanupRow.index > 0
                    width: parent.width
                  }
                  RowLayout {
                    width: parent.width
                    height: 40
                    spacing: 8
                    Text {
                      Layout.fillWidth: true
                      Layout.leftMargin: 12
                      text: cleanupRow.modelData.label
                      font.pixelSize: Theme.fontBase
                      color: Theme.ink1
                    }
                    Text {
                      text: cleanupRow.modelData.detail
                      font.pixelSize: Theme.fontSm
                      font.family: Theme.mono
                      color: Theme.ink3
                    }
                    TextBtn {
                      Layout.rightMargin: 8
                      text: root.busyContext === "prune:" + cleanupRow.modelData.kind ? "Pruning…" : "Prune"
                      fs: Theme.fontSm
                      enabledBtn: !root.busy
                      onClicked: {
                        if (root.activeMonitor)
                          root.activeMonitor.prune(cleanupRow.modelData.kind);
                      }
                    }
                  }
                }
              }
            }
          }
        }
      }
    }

    Item {
      Layout.fillWidth: true
      Layout.preferredHeight: 10
    }

    Text {
      visible: root.toastMsg.length > 0
      Layout.fillWidth: true
      Layout.leftMargin: 2
      wrapMode: Text.Wrap
      font.pixelSize: Theme.fontSm
      color: Theme.amber
      text: root.toastMsg
    }
  }

  Rectangle {
    id: logView
    visible: false
    anchors.fill: parent
    radius: Theme.radiusCard
    color: Theme.inset
    border.color: Theme.cardBorder
    border.width: 1

    ColumnLayout {
      anchors.fill: parent
      anchors.margins: 14
      spacing: 8
      RowLayout {
        Layout.fillWidth: true
        Text {
          text: "Logs · " + root.logViewName
          font.pixelSize: Theme.fontBase
          font.weight: Font.DemiBold
          color: Theme.ink1
          Layout.fillWidth: true
          elide: Text.ElideRight
        }
        TextBtn {
          text: "tail " + root.logTail
          fs: Theme.fontSm
          onClicked: {
            root.logTail = root.logTail >= 500 ? 100 : root.logTail + 200;
            if (root.activeMonitor)
              root.activeMonitor.fetchLogs(root.logViewId, root.logTail);
          }
        }
        TextBtn {
          text: "Refresh"
          fs: Theme.fontSm
          onClicked: {
            if (root.activeMonitor)
              root.activeMonitor.fetchLogs(root.logViewId, root.logTail);
          }
        }
        TextBtn {
          text: "Close"
          fs: Theme.fontSm
          onClicked: logView.visible = false
        }
      }
      Hairline {
        Layout.fillWidth: true
      }
      Flickable {
        Layout.fillWidth: true
        Layout.fillHeight: true
        contentHeight: logText.height
        clip: true
          Text {
            id: logText
            width: parent.width
            wrapMode: Text.Wrap
            font.pixelSize: Theme.fontSm
            font.family: Theme.mono
            color: Theme.ink1
            text: {
              if (!root.activeMonitor)
                return "";
              if (root.busyContext === "logs:" + root.logViewId)
                return "Loading…";
              if (root.activeMonitor.logError.length > 0)
                return "Error: " + root.activeMonitor.logError;
              const t = root.activeMonitor.logText;
              return t.length > 0 ? t : "(no output)";
            }
          }
      }
    }
  }

  component ProjectGroup: SectionCard {
    id: group
    property var project: ({})
    property var members: []
    readonly property bool groupBusy: root.busy && (root.busyContext === "start-project:" + (group.project.name || "") || root.busyContext === "stop-project:" + (group.project.name || ""))
    height: groupCol.height

    Column {
      id: groupCol
      width: parent.width

      Column {
        width: parent.width
        topPadding: 10
        bottomPadding: 8
        leftPadding: 12
        rightPadding: 8
        spacing: 4
        RowLayout {
          width: parent.width - 20
          spacing: 8
          Text {
            Layout.fillWidth: true
            text: group.project.name || ""
            font.pixelSize: Theme.fontBase
            font.weight: Font.DemiBold
            color: Theme.ink1
            elide: Text.ElideRight
          }
          Text {
            text: (group.project.running || 0) + "/" + (group.project.total || 0) + " up"
            font.pixelSize: Theme.fontSm
            font.family: Theme.mono
            color: (group.project.running || 0) > 0 ? Theme.green : Theme.ink3
          }
        }
        Text {
          visible: (group.project.config_files || "").length > 0
          width: parent.width - 20
          text: group.project.config_files
          font.pixelSize: Theme.fontXs
          font.family: Theme.mono
          color: Theme.ink3
          elide: Text.ElideMiddle
        }
        RowLayout {
          width: parent.width - 20
          spacing: 2
          Item {
            Layout.fillWidth: true
          }
          TextBtn {
            visible: (group.project.working_dir || "").length > 0
            text: "Open folder"
            fs: Theme.fontSm
            fg: Theme.accent
            onClicked: {
              if (root.activeMonitor)
                root.activeMonitor.openPath(group.project.working_dir);
            }
          }
          TextBtn {
            visible: !group.groupBusy
            text: "Start all"
            fs: Theme.fontSm
            fg: Theme.green
            enabledBtn: !root.busy
            onClicked: {
              if (root.activeMonitor)
                root.activeMonitor.startProject(group.project.name);
            }
          }
          TextBtn {
            visible: !group.groupBusy
            text: "Stop all"
            fs: Theme.fontSm
            enabledBtn: !root.busy
            onClicked: {
              if (root.activeMonitor)
                root.activeMonitor.stopProject(group.project.name, 10);
            }
          }
          Text {
            visible: group.groupBusy
            text: "Working…"
            font.pixelSize: Theme.fontSm
            color: Theme.accent
          }
        }
      }

      Repeater {
        model: group.members
        delegate: ContainerRow {
          required property var modelData
          width: parent.width
          info: modelData
          showTopLine: true
        }
      }
    }
  }

  component ContainerRow: Column {
    id: row
    property var info: ({})
    property bool showTopLine: false
    // Busy when any operation targets this container (action, remove, logs).
    readonly property bool rowBusy: root.busy && (row.info.id || "").length > 0 && root.busyContext.endsWith(":" + row.info.id)
    spacing: 0

    Hairline {
      visible: row.showTopLine
      width: parent.width
    }

    Column {
      width: parent.width
      topPadding: 8
      bottomPadding: 8
      leftPadding: 12
      rightPadding: 8
      spacing: 5

      RowLayout {
        width: parent.width - 20
        spacing: 8
        Rectangle {
          Layout.preferredWidth: 8
          Layout.preferredHeight: 8
          Layout.alignment: Qt.AlignVCenter
          radius: 4
          color: root.stateColor(row.info.state)
        }
        Text {
          Layout.fillWidth: true
          text: row.info.name || ""
          font.pixelSize: Theme.fontBase
          font.weight: Font.DemiBold
          color: Theme.ink1
          elide: Text.ElideRight
        }
        Text {
          text: root.stateWord(row.info.state)
          font.pixelSize: Theme.fontSm
          color: root.stateColor(row.info.state)
        }
      }

      Text {
        width: parent.width - 20
        leftPadding: 16
        text: (row.info.image || "") + " · " + (row.info.status || "")
        font.pixelSize: Theme.fontXs
        font.family: Theme.mono
        color: Theme.ink3
        elide: Text.ElideRight
      }

      RowLayout {
        width: parent.width - 20
        spacing: 2
        Item {
          Layout.preferredWidth: 16
          Layout.preferredHeight: 1
        }
        Text {
          visible: row.rowBusy
          text: "Working…"
          font.pixelSize: Theme.fontSm
          color: Theme.accent
        }
        Row {
          visible: !row.rowBusy
          spacing: 2
          IconBtn {
            visible: !(row.info.is_running || false)
            glyph: "󰐊"
            btnSize: 26
            fs: Theme.iconSm
            fg: Theme.ok
            tooltip: "Start container"
            dimmed: root.busy
            onClicked: root.activeMonitor.startContainer(row.info.id)
          }
          IconBtn {
            visible: (row.info.is_running || false)
            glyph: "󰏤"
            btnSize: 26
            fs: Theme.iconSm
            fg: Theme.warn
            tooltip: "Stop container"
            dimmed: root.busy
            onClicked: root.activeMonitor.stopContainer(row.info.id, 10)
          }
          IconBtn {
            glyph: "󰌱"
            btnSize: 26
            fs: Theme.iconSm
            fg: Theme.ink2
            tooltip: "View logs"
            dimmed: root.busy
            onClicked: root.openLogs(row.info.id, row.info.name)
          }
          IconBtn {
            glyph: "󰑓"
            btnSize: 26
            fs: Theme.iconSm
            fg: Theme.accent
            tooltip: "Restart container"
            dimmed: root.busy
            onClicked: root.activeMonitor.restartContainer(row.info.id, 10)
          }
          IconBtn {
            glyph: "󰆴"
            btnSize: 26
            fs: Theme.iconSm
            fg: Theme.err
            tooltip: "Remove container"
            dimmed: root.busy
            onClicked: root.activeMonitor.removeContainer(row.info.id, false)
          }
        }
      }
    }
  }
}
