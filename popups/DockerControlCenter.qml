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
  implicitHeight: 600

  function syncHeight(): void {}

  readonly property bool connected: activeMonitor ? activeMonitor.connected : false
  readonly property bool busy: activeMonitor ? activeMonitor.isBusy : false
  readonly property string busyContext: activeMonitor ? activeMonitor.busyContext : ""
  readonly property string busyLabel: activeMonitor ? activeMonitor.busyLabel : ""
  readonly property bool isServiceStarting: busy && busyContext === "service:start"
  readonly property bool isServiceStopping: busy && busyContext === "service:stop"

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

  property bool confirmStopPrompt: false
  property int currentTab: 0

  onConnectedChanged: {
    if (!root.connected)
      root.confirmStopPrompt = false;
  }

  function startService(): void {
    if (root.activeMonitor)
      root.activeMonitor.startService();
  }

  function requestStopService(): void {
    if (root.busy)
      return;
    if (root.runningCount > 0) {
      root.confirmStopPrompt = true;
    } else {
      executeStopService();
    }
  }

  function executeStopService(): void {
    root.confirmStopPrompt = false;
    if (root.activeMonitor)
      root.activeMonitor.stopService();
  }

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
      if (ok) {
        if (output.length > 0 && output !== "No Content")
          root.showToast(output);
      } else {
        root.showToast("Failed: " + (error.length > 0 ? error : context));
      }
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
    anchors.fill: parent
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
          font.family: Theme.displayFont
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
          font.family: Theme.textFont
          font.pixelSize: Theme.fontXs
          color: root.busy ? Theme.accent : (root.connected ? Theme.ink3 : Theme.err)
          elide: Text.ElideRight
        }
      }

      IconButton {
        glyph: "󰑓"
        fs: Theme.iconBase
        tooltip: "Refresh containers"
        spinning: root.busy && !root.isServiceStopping
        dimmed: root.busy
        onClicked: {
          if (root.activeMonitor)
            root.activeMonitor.refresh();
          root.triggerRefresh();
        }
      }

      IconButton {
        visible: root.connected
        glyph: "󰐥"
        fs: Theme.iconBase
        fg: Theme.red
        tooltip: "Stop Docker service"
        tooltipSub: root.runningCount > 0 ? (root.runningCount + " running") : "Safe shutdown"
        dimmed: root.busy
        spinning: root.isServiceStopping
        onClicked: root.requestStopService()
      }
    }

    Item {
      Layout.fillWidth: true
      Layout.preferredHeight: 10
    }

    RowLayout {
      Layout.fillWidth: true
      Layout.fillHeight: false
      Layout.preferredHeight: 54
      Layout.minimumHeight: 54
      Layout.maximumHeight: 54
      spacing: 1
      visible: root.connected

      Repeater {
        model: [
          { label: "Containers", value: root.runningCount + "/" + root.totalCount, tone: Theme.green },
          { label: "Projects", value: root.projects.length, tone: Theme.accent },
          { label: "Images", value: root.images.length, tone: Theme.teal },
          { label: "Volumes", value: root.volumes.length, tone: Theme.violet }
        ]

        delegate: Rectangle {
          id: metricCell
          required property var modelData
          Layout.fillWidth: true
          color: Theme.inset

          Rectangle {
            width: 2
            anchors.left: parent.left
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            color: metricCell.modelData.tone
          }

          Column {
            anchors.left: parent.left
            anchors.leftMargin: 10
            anchors.verticalCenter: parent.verticalCenter
            spacing: 2
            Text {
              text: metricCell.modelData.value
              font.family: Theme.displayFont
              font.pixelSize: Theme.fontXl
              font.weight: Font.DemiBold
              color: Theme.ink1
            }
            Text {
              text: metricCell.modelData.label
              font.family: Theme.textFont
              font.pixelSize: Theme.fontXs
              color: Theme.ink3
            }
          }
        }
      }
    }

    Item {
      Layout.fillWidth: true
      Layout.preferredHeight: 10
      visible: root.connected
    }

    SegmentedControl {
      Layout.fillWidth: true
      visible: root.connected
      items: [
        { icon: "󰘬", label: "Operations", count: root.totalCount },
        { icon: "󰆧", label: "Storage", count: root.images.length + root.volumes.length }
      ]
      current: root.currentTab
      onSelected: function(index) { root.currentTab = index; }
    }

    Rectangle {
      Layout.fillWidth: true
      visible: root.confirmStopPrompt
      radius: Theme.radiusSection
      color: Theme.surface
      border.color: Theme.amber
      border.width: 1
      Layout.preferredHeight: confirmStopCol.implicitHeight + 24

      ColumnLayout {
        id: confirmStopCol
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        anchors.margins: 12
        spacing: 10

        RowLayout {
          Layout.fillWidth: true
          spacing: 8

          Text {
            text: "󰀦"
            font.family: Theme.mono
            font.pixelSize: Theme.iconMd
            color: Theme.amber
          }

          ColumnLayout {
            Layout.fillWidth: true
            spacing: 2

            Text {
              Layout.fillWidth: true
              text: "Active containers running"
              font.family: Theme.textFont
              font.pixelSize: Theme.fontBase
              font.weight: Font.DemiBold
              color: Theme.ink1
            }

            Text {
              Layout.fillWidth: true
              text: root.runningCount + (root.runningCount === 1 ? " container is" : " containers are") + " currently active. Stopping Docker will shut them down."
              font.family: Theme.textFont
              font.pixelSize: Theme.fontXs
              color: Theme.ink3
              wrapMode: Text.Wrap
            }
          }
        }

        RowLayout {
          Layout.fillWidth: true
          spacing: 8

          Item {
            Layout.fillWidth: true
          }

          TextButton {
            text: "Cancel"
            fs: Theme.fontSm
            fg: Theme.ink2
            onClicked: root.confirmStopPrompt = false
          }

          PrimaryButton {
            text: "Stop Service"
            glyph: "󰐥"
            fill: Theme.red
            ink: Theme.darkInk
            enabledBtn: !root.busy
            onClicked: root.executeStopService()
          }
        }
      }
    }

    Item {
      Layout.fillWidth: true
      Layout.preferredHeight: root.confirmStopPrompt ? 14 : 0
      visible: root.confirmStopPrompt
    }

    Rectangle {
      Layout.fillWidth: true
      visible: !root.connected
      radius: Theme.radiusSection
      color: Theme.surface
      border.color: Theme.lineMuted
      border.width: 1
      Layout.preferredHeight: offlineCol.implicitHeight + 28

      ColumnLayout {
        id: offlineCol
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        anchors.margins: 14
        spacing: 12

        RowLayout {
          Layout.fillWidth: true
          spacing: 10

          Text {
            text: root.isServiceStarting ? "󰑓" : "󰅚"
            font.family: Theme.mono
            font.pixelSize: Theme.iconMd
            color: root.isServiceStarting ? Theme.accent : Theme.red
            NumberAnimation on rotation {
              running: root.isServiceStarting
              from: 0
              to: 360
              loops: Animation.Infinite
              duration: 800
            }
          }

          ColumnLayout {
            Layout.fillWidth: true
            spacing: 2

            Text {
              Layout.fillWidth: true
              text: root.isServiceStarting ? "Starting Docker service…" : "Docker service is inactive"
              font.family: Theme.textFont
              font.pixelSize: Theme.fontBase
              font.weight: Font.DemiBold
              color: Theme.ink1
            }

            Text {
              Layout.fillWidth: true
              wrapMode: Text.Wrap
              font.family: Theme.textFont
              font.pixelSize: Theme.fontXs
              color: Theme.ink3
              text: root.isServiceStarting
                ? "Connecting to daemon via user systemd D-Bus…"
                : "Daemon unreachable at " + (root.activeMonitor ? root.activeMonitor.socketPath : "socket")
            }
          }
        }

        RowLayout {
          Layout.fillWidth: true

          Item {
            Layout.fillWidth: true
          }

          PrimaryButton {
            text: root.isServiceStarting ? "Starting…" : "Start Docker Service"
            glyph: "󰐊"
            enabledBtn: !root.busy
            onClicked: root.startService()
          }
        }
      }
    }

    Flickable {
      Layout.fillWidth: true
      Layout.fillHeight: true
      visible: root.connected
      contentHeight: contentCol.height
      boundsBehavior: Flickable.StopAtBounds
      clip: true

      Column {
        id: contentCol
        width: parent.width
        spacing: 14

        Column {
          id: composeSectionCol
          width: parent.width
          spacing: 4
          visible: root.currentTab === 0 && root.projects.length > 0
          SectionHeader {
            width: composeSectionCol.width
            label: "Compose projects · " + root.projects.length
          }
          Repeater {
            model: root.projects
            delegate: ProjectGroup {
              required property var modelData
              width: composeSectionCol.width
              project: modelData
              members: modelData.containers
            }
          }
        }

        Column {
          width: parent.width
          spacing: 4
          visible: root.currentTab === 0
          SectionHeader {
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
                  width: standaloneList.width
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
            font.family: Theme.textFont
            font.pixelSize: Theme.fontSm
            color: Theme.ink3
            text: "No standalone containers"
          }
        }

        Column {
          width: parent.width
          spacing: 4
          visible: root.currentTab === 1
          SectionHeader {
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
                  width: imageList.width
                  spacing: 0
                  Hairline {
                    visible: imageRow.index > 0
                    width: imageRow.width
                  }
                  RowLayout {
                    width: imageRow.width
                    height: 54
                    spacing: 10

                    Rectangle {
                      Layout.preferredWidth: 3
                      Layout.fillHeight: true
                      color: Theme.teal
                    }

                    ColumnLayout {
                      Layout.fillWidth: true
                      Layout.leftMargin: 2
                      spacing: 3

                      Text {
                        Layout.fillWidth: true
                        text: (imageRow.modelData.repo_tags && imageRow.modelData.repo_tags.length > 0) ? imageRow.modelData.repo_tags[0] : imageRow.modelData.short_id
                        font.pixelSize: Theme.fontBase
                        font.family: Theme.mono
                        color: Theme.ink1
                        elide: Text.ElideRight
                      }
                      Text {
                        Layout.fillWidth: true
                        text: imageRow.modelData.size_text
                        font.pixelSize: Theme.fontXs
                        font.family: Theme.mono
                        color: Theme.ink3
                        elide: Text.ElideRight
                      }
                    }

                    Rectangle {
                      Layout.preferredWidth: imageActions.implicitWidth + 4
                      Layout.preferredHeight: 30
                      Layout.rightMargin: 8
                      radius: 3
                      color: Theme.inset
                      border.color: Theme.lineMuted
                      border.width: 1

                      Row {
                        id: imageActions
                        anchors.centerIn: parent
                        IconButton {
                          glyph: "󰆴"
                          btnSize: 28
                          fs: Theme.iconSm
                          fg: Theme.red
                          tooltip: "Remove image"
                          dimmed: root.busy && root.busyContext === "remove-image:" + ((imageRow.modelData.repo_tags && imageRow.modelData.repo_tags.length > 0) ? imageRow.modelData.repo_tags[0] : imageRow.modelData.id)
                          onClicked: root.activeMonitor.removeImage((imageRow.modelData.repo_tags && imageRow.modelData.repo_tags.length > 0) ? imageRow.modelData.repo_tags[0] : imageRow.modelData.id, false)
                        }
                      }
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
            font.family: Theme.textFont
            font.pixelSize: Theme.fontSm
            color: Theme.ink3
            text: "No images"
          }
        }

        Column {
          width: parent.width
          spacing: 4
          visible: root.currentTab === 1
          SectionHeader {
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
                  width: volumeList.width
                  spacing: 0
                  Hairline {
                    visible: volumeRow.index > 0
                    width: volumeRow.width
                  }
                  RowLayout {
                    width: volumeRow.width
                    height: 54
                    spacing: 10

                    Rectangle {
                      Layout.preferredWidth: 3
                      Layout.fillHeight: true
                      color: Theme.violet
                    }

                    ColumnLayout {
                      Layout.fillWidth: true
                      Layout.leftMargin: 2
                      spacing: 3

                      Text {
                        Layout.fillWidth: true
                        text: volumeRow.modelData.name
                        font.pixelSize: Theme.fontBase
                        font.family: Theme.mono
                        color: Theme.ink1
                        elide: Text.ElideRight
                      }
                      Text {
                        Layout.fillWidth: true
                        visible: (volumeRow.modelData.driver || "").length > 0
                        text: volumeRow.modelData.driver
                        font.family: Theme.textFont
                        font.pixelSize: Theme.fontXs
                        color: Theme.ink3
                      }
                    }

                    Rectangle {
                      Layout.preferredWidth: volumeActions.implicitWidth + 4
                      Layout.preferredHeight: 30
                      Layout.rightMargin: 8
                      radius: 3
                      color: Theme.inset
                      border.color: Theme.lineMuted
                      border.width: 1

                      Row {
                        id: volumeActions
                        anchors.centerIn: parent
                        IconButton {
                          glyph: "󰆴"
                          btnSize: 28
                          fs: Theme.iconSm
                          fg: Theme.red
                          tooltip: "Remove volume"
                          dimmed: root.busy && root.busyContext === "remove-volume:" + volumeRow.modelData.name
                          onClicked: root.activeMonitor.removeVolume(volumeRow.modelData.name, false)
                        }
                      }
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
            font.family: Theme.textFont
            font.pixelSize: Theme.fontSm
            color: Theme.ink3
            text: "No volumes"
          }
        }

        Column {
          width: parent.width
          spacing: 4
          visible: root.currentTab === 1
          SectionHeader {
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
                  width: cleanupList.width
                  spacing: 0
                  Hairline {
                    visible: cleanupRow.index > 0
                    width: cleanupRow.width
                  }
                  RowLayout {
                    width: cleanupRow.width
                    height: 54
                    spacing: 10

                    Rectangle {
                      Layout.preferredWidth: 3
                      Layout.fillHeight: true
                      color: Theme.amber
                    }

                    ColumnLayout {
                      Layout.fillWidth: true
                      Layout.leftMargin: 2
                      spacing: 3

                      Text {
                        Layout.fillWidth: true
                        text: cleanupRow.modelData.label
                        font.family: Theme.textFont
                        font.pixelSize: Theme.fontBase
                        color: Theme.ink1
                      }
                      Text {
                        Layout.fillWidth: true
                        text: cleanupRow.modelData.detail
                        font.pixelSize: Theme.fontXs
                        font.family: Theme.mono
                        color: Theme.ink3
                        elide: Text.ElideRight
                      }
                    }

                    Rectangle {
                      Layout.preferredWidth: cleanupActions.implicitWidth + 4
                      Layout.preferredHeight: 30
                      Layout.rightMargin: 8
                      radius: 3
                      color: Theme.inset
                      border.color: Theme.lineMuted
                      border.width: 1

                      Row {
                        id: cleanupActions
                        anchors.centerIn: parent
                        IconButton {
                          glyph: "󰃢"
                          btnSize: 28
                          fs: Theme.iconSm
                          fg: Theme.amber
                          tooltip: root.busyContext === "prune:" + cleanupRow.modelData.kind ? "Pruning" : "Prune " + cleanupRow.modelData.label
                          dimmed: root.busy
                          spinning: root.busyContext === "prune:" + cleanupRow.modelData.kind
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
      }
    }

    Item {
      Layout.fillWidth: true
      Layout.fillHeight: true
      visible: !root.connected
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
      font.family: Theme.textFont
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
          font.family: Theme.displayFont
          font.pixelSize: Theme.fontBase
          font.weight: Font.DemiBold
          color: Theme.ink1
          Layout.fillWidth: true
          elide: Text.ElideRight
        }
        TextButton {
          text: "tail " + root.logTail
          fs: Theme.fontSm
          onClicked: {
            root.logTail = root.logTail >= 500 ? 100 : root.logTail + 200;
            if (root.activeMonitor)
              root.activeMonitor.fetchLogs(root.logViewId, root.logTail);
          }
        }
        TextButton {
          text: "Refresh"
          fs: Theme.fontSm
          onClicked: {
            if (root.activeMonitor)
              root.activeMonitor.fetchLogs(root.logViewId, root.logTail);
          }
        }
        TextButton {
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
      width: group.width

      RowLayout {
        width: groupCol.width
        height: 58
        spacing: 10

        Rectangle {
          Layout.preferredWidth: 3
          Layout.fillHeight: true
          color: (group.project.running || 0) > 0 ? Theme.green : Theme.ink3
        }

        ColumnLayout {
          Layout.fillWidth: true
          Layout.leftMargin: 2
          spacing: 3

          RowLayout {
            Layout.fillWidth: true
            spacing: 8

            Text {
              text: "󰘬"
              font.family: Theme.mono
              font.pixelSize: Theme.iconSm
              color: Theme.accent
            }

            Text {
              Layout.fillWidth: true
              text: group.project.name || ""
              font.family: Theme.displayFont
              font.pixelSize: Theme.fontBase
              font.weight: Font.DemiBold
              color: Theme.ink1
              elide: Text.ElideRight
            }

            Rectangle {
              radius: 3
              color: (group.project.running || 0) > 0 ? Theme.okBg : Theme.surfaceElevated
              implicitWidth: projectState.implicitWidth + 12
              implicitHeight: 20

              Text {
                id: projectState
                anchors.centerIn: parent
                text: (group.project.running || 0) + "/" + (group.project.total || 0) + " up"
                font.pixelSize: Theme.fontXs
                font.family: Theme.mono
                color: (group.project.running || 0) > 0 ? Theme.green : Theme.ink3
              }
            }
          }

          Text {
            Layout.fillWidth: true
            visible: (group.project.config_files || "").length > 0
            text: group.project.config_files
            font.pixelSize: Theme.fontXs
            font.family: Theme.mono
            color: Theme.ink3
            elide: Text.ElideMiddle
          }
        }

        Rectangle {
          Layout.preferredWidth: group.groupBusy ? 58 : projectActions.implicitWidth + 4
          Layout.preferredHeight: 30
          Layout.rightMargin: 8
          radius: 3
          color: Theme.inset
          border.color: Theme.lineMuted
          border.width: 1

          Row {
            id: projectActions
            anchors.centerIn: parent
            visible: !group.groupBusy
            spacing: 0

            IconButton {
              visible: (group.project.working_dir || "").length > 0
              glyph: "󰉋"
              btnSize: 28
              fs: Theme.iconSm
              fg: Theme.accent
              tooltip: "Open project folder"
              dimmed: root.busy
              onClicked: {
                if (root.activeMonitor)
                  root.activeMonitor.openPath(group.project.working_dir);
              }
            }

            IconButton {
              visible: !group.groupBusy
              glyph: "󰐊"
              btnSize: 28
              fs: Theme.iconSm
              fg: Theme.green
              tooltip: "Start all containers"
              dimmed: root.busy
              onClicked: {
                if (root.activeMonitor)
                  root.activeMonitor.startProject(group.project.name);
              }
            }

            IconButton {
              visible: !group.groupBusy
              glyph: "󰏤"
              btnSize: 28
              fs: Theme.iconSm
              fg: Theme.amber
              tooltip: "Stop all containers"
              dimmed: root.busy
              onClicked: {
                if (root.activeMonitor)
                  root.activeMonitor.stopProject(group.project.name, 10);
              }
            }
          }

          Text {
            visible: group.groupBusy
            anchors.centerIn: parent
            text: "…"
            font.family: Theme.textFont
            font.pixelSize: Theme.fontSm
            color: Theme.accent
          }
        }
      }

      Repeater {
        model: group.members
        delegate: ContainerRow {
          required property var modelData
          width: groupCol.width
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
    readonly property bool rowBusy: root.busy && (row.info.id || "").length > 0 && root.busyContext.endsWith(":" + row.info.id)
    spacing: 0

    Hairline {
      visible: row.showTopLine
      width: row.width
    }

    RowLayout {
      width: row.width
      height: 58
      spacing: 10

      Rectangle {
        Layout.preferredWidth: 3
        Layout.fillHeight: true
        color: root.stateColor(row.info.state)
      }

      ColumnLayout {
        Layout.fillWidth: true
        Layout.leftMargin: 2
        spacing: 4

        RowLayout {
          Layout.fillWidth: true
          spacing: 8

          Text {
            Layout.fillWidth: true
            text: row.info.name || ""
            font.family: Theme.textFont
            font.pixelSize: Theme.fontBase
            font.weight: Font.DemiBold
            color: Theme.ink1
            elide: Text.ElideRight
          }

          Text {
            text: root.stateWord(row.info.state)
            font.family: Theme.textFont
            font.pixelSize: Theme.fontSm
            color: root.stateColor(row.info.state)
          }
        }

        Text {
          Layout.fillWidth: true
          text: (row.info.image || "") + " · " + (row.info.status || "")
          font.pixelSize: Theme.fontXs
          font.family: Theme.mono
          color: Theme.ink3
          elide: Text.ElideRight
        }
      }

      Rectangle {
        visible: !row.rowBusy
        Layout.preferredWidth: containerActions.implicitWidth + 4
        Layout.preferredHeight: 30
        Layout.rightMargin: 8
        radius: 3
        color: Theme.inset
        border.color: Theme.lineMuted
        border.width: 1

        Row {
          id: containerActions
          anchors.centerIn: parent
          spacing: 0

          IconButton {
            visible: !(row.info.is_running || false)
            glyph: "󰐊"
            btnSize: 28
            fs: Theme.iconSm
            fg: Theme.ok
            tooltip: "Start container"
            dimmed: root.busy
            onClicked: root.activeMonitor.startContainer(row.info.id)
          }
          IconButton {
            visible: (row.info.is_running || false)
            glyph: "󰏤"
            btnSize: 28
            fs: Theme.iconSm
            fg: Theme.warn
            tooltip: "Stop container"
            dimmed: root.busy
            onClicked: root.activeMonitor.stopContainer(row.info.id, 10)
          }
          IconButton {
            glyph: "󰌱"
            btnSize: 28
            fs: Theme.iconSm
            fg: Theme.ink2
            tooltip: "View logs"
            dimmed: root.busy
            onClicked: root.openLogs(row.info.id, row.info.name)
          }
          IconButton {
            glyph: "󰑓"
            btnSize: 28
            fs: Theme.iconSm
            fg: Theme.accent
            tooltip: "Restart container"
            dimmed: root.busy
            onClicked: root.activeMonitor.restartContainer(row.info.id, 10)
          }
          Rectangle {
            width: 1
            height: 14
            anchors.verticalCenter: parent.verticalCenter
            color: Theme.line
          }
          IconButton {
            glyph: "󰆴"
            btnSize: 28
            fs: Theme.iconSm
            fg: Theme.err
            tooltip: "Remove container"
            dimmed: root.busy
            onClicked: root.activeMonitor.removeContainer(row.info.id, false)
          }
        }
      }

      Text {
        visible: row.rowBusy
        Layout.preferredWidth: 48
        text: "Working…"
        font.family: Theme.textFont
        font.pixelSize: Theme.fontSm
        color: Theme.accent
      }
    }
  }
}
