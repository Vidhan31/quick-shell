pragma ComponentBehavior: Bound
// MediaControlCenter.qml — Media playback popup.
// Tailscale visual system: same tokens, card, grouped surface rows with hairlines,
// SectionHead, RowBase, TextBtn, IconBtn, TSwitch, Segments. Words + tint carry
// state, no badge pills or boxed banners. Content hugs bodyCol.height (capped) so
// the popover never clips or leaves empty space; overflow scrolls inside the card.
// Native C++ Qt6 QML module (Quickshell.Plugins.Media).
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Plugins.Media

Item {
  id: root

  property MediaManager media: null

  Loader {
    id: fallbackMediaLoader
    active: root.media === null
    sourceComponent: MediaManager {
      running: root.media === null
    }
  }

  readonly property MediaManager activeMedia: root.media ? root.media : fallbackMediaLoader.item

  // Position tracking: enable 100ms clock interpolation only when popup is visible
  Binding {
    target: root.activeMedia
    property: "positionTracking"
    value: root.visible
    when: root.activeMedia !== null
  }

  // Manually selected player, if user clicked a tab
  property var manualPlayer: activeMedia ? activeMedia.manualPlayer : null
  onManualPlayerChanged: {
    if (activeMedia && activeMedia.manualPlayer !== manualPlayer) {
      activeMedia.manualPlayer = manualPlayer;
    }
  }

  Connections {
    target: root.activeMedia
    function onManualPlayerChanged() {
      if (root.activeMedia && root.manualPlayer !== root.activeMedia.manualPlayer) {
        root.manualPlayer = root.activeMedia.manualPlayer;
      }
    }
  }

  // All available players from native MPRIS manager
  readonly property var playerList: activeMedia ? activeMedia.playerList : []
  readonly property int playerCount: activeMedia ? activeMedia.playerCount : 0

  readonly property var player: activeMedia ? activeMedia.activePlayer : null
  readonly property bool hasPlayer: activeMedia ? activeMedia.hasPlayer : false

  // Track playback status
  readonly property bool isPlaying: activeMedia ? activeMedia.isPlaying : false

  // Seeking state
  property bool isSeeking: false
  property real seekTarget: 0

  // Track length & position in seconds
  readonly property real trackLength: activeMedia ? activeMedia.trackLength : 0
  readonly property real trackPos: isSeeking ? seekTarget : (activeMedia ? activeMedia.trackPos : 0)

  // Status tint carries state everywhere — no pills, no boxes.
  readonly property color statusColor: {
    if (!root.hasPlayer) return t.ink3;
    if (root.isPlaying) return t.green;
    return t.amber;
  }
  readonly property string statusWord: {
    if (!root.hasPlayer) return "Not playing";
    if (root.isPlaying) return "Playing";
    return "Paused";
  }

  // Format seconds to mm:ss or hh:mm:ss
  function formatSeconds(sec: double): string {
    if (!isFinite(sec) || sec <= 0) return "0:00";
    const total = Math.floor(sec);
    const hrs = Math.floor(total / 3600);
    const mins = Math.floor((total % 3600) / 60);
    const secs = total % 60;
    const secsStr = (secs < 10 ? "0" : "") + secs;
    if (hrs > 0) {
      const minsStr = (mins < 10 ? "0" : "") + mins;
      return hrs + ":" + minsStr + ":" + secsStr;
    }
    return mins + ":" + secsStr;
  }

  function formatArtUrl(url: string): string {
    return url || "";
  }

  function playerLabel(p: var): string {
    if (!p) return "";
    return p.identity || "Player";
  }

  function cycleLoop(): void {
    if (!root.player || !root.player.loopSupported || !root.player.canControl) return;
    if (root.player.loopState === 0) {
      root.player.loopState = 2; // Playlist
    } else if (root.player.loopState === 2) {
      root.player.loopState = 1; // Track
    } else {
      root.player.loopState = 0; // None
    }
  }

  function loopWord(): string {
    if (!root.player) return "Off";
    if (root.player.loopState === 1) return "Track";
    if (root.player.loopState === 2) return "Playlist";
    return "Off";
  }

  implicitWidth: 440
  // Hug the content (chrome 32 + body), capped so overflow scrolls inside
  // the card instead of growing off-screen. bodyCol.height is driven only
  // by its children (width comes from the viewport), so no binding loop.
  implicitHeight: Math.min(640, 32 + bodyCol.height)
  width: implicitWidth
  height: implicitHeight

  // ================= Design tokens (mirrors TailscaleControlCenter) =================
  QtObject {
    id: t
    readonly property color bg: "#17171E"
    readonly property color surface: "#1F202B"
    readonly property color inset: "#121217"
    readonly property color line: "#2B2C3A"
    readonly property color ink1: "#F1F1F6"
    readonly property color ink2: "#A6A6B8"
    readonly property color ink3: "#6F6F84"
    readonly property color accent: "#5E9DFF"
    readonly property color green: "#46C786"
    readonly property color amber: "#E2A63B"
    readonly property color red: "#DF6363"
    readonly property color violet: "#AE8CFF"
    readonly property color darkInk: "#101018"
    readonly property string mono: "JetBrainsMono Nerd Font Mono"
  }

  // ================= Reusable quiet components (mirrors TailscaleControlCenter) =================
  component Hairline: Rectangle {
    color: t.line
    height: 1
  }

  // Small caps section label with an optional trailing quiet action.
  component SectionHead: Item {
    property string label: ""
    property string actionText: ""
    property color actionColor: t.ink2
    signal actionClicked
    implicitHeight: 20
    Text {
      anchors.left: parent.left
      anchors.verticalCenter: parent.verticalCenter
      text: label
      font.pixelSize: 11
      font.bold: true
      font.capitalization: Font.AllUppercase
      font.letterSpacing: 0.8
      color: t.ink3
    }
    TextBtn {
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      visible: actionText.length > 0
      text: parent.actionText
      fg: parent.actionColor
      fs: 11
      onClicked: parent.actionClicked()
    }
  }

  // Base for every clickable row: same wash everywhere, no borders.
  // Set actionable: false when there is nothing to do — the row then
  // stays inert (no wash, no pointer cursor) instead of faking affordance.
  component RowBase: Rectangle {
    id: rb
    signal clicked
    property color base: "transparent"
    property color hover: "#0FFFFFFF"
    property color press: "#1AFFFFFF"
    property real rad: 0
    property bool actionable: true
    radius: rb.rad
    color: (!rb.actionable || (!ma.containsMouse && !ma.pressed)) ? base : (ma.pressed ? press : hover)
    Behavior on color { ColorAnimation { duration: 90 } }
    MouseArea {
      id: ma
      anchors.fill: parent
      hoverEnabled: rb.actionable
      cursorShape: rb.actionable ? Qt.PointingHandCursor : Qt.ArrowCursor
      onClicked: {
        if (rb.actionable) rb.clicked();
      }
    }
  }

  // Borderless text button.
  component TextBtn: Rectangle {
    id: tb
    signal clicked
    property string text: ""
    property color fg: t.ink2
    property int fs: 12
    property bool bold: false
    implicitWidth: lbl.implicitWidth + 18
    implicitHeight: 26
    radius: 7
    color: ma.pressed ? "#1CFFFFFF" : ma.containsMouse ? "#0FFFFFFF" : "transparent"
    Behavior on color { ColorAnimation { duration: 90 } }
    Text {
      id: lbl
      anchors.centerIn: parent
      text: tb.text
      font.pixelSize: tb.fs
      font.bold: tb.bold
      color: (ma.containsMouse || ma.pressed) ? t.ink1 : tb.fg
      Behavior on color { ColorAnimation { duration: 90 } }
    }
    MouseArea {
      id: ma
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: tb.clicked()
    }
  }

  // Borderless square icon button.
  component IconBtn: Rectangle {
    id: ib
    signal clicked
    property string glyph: ""
    property int fs: 14
    property color fg: t.ink2
    property bool dimmed: false
    width: 30
    height: 30
    radius: 8
    color: ma.pressed ? "#1CFFFFFF" : ma.containsMouse ? "#0FFFFFFF" : "transparent"
    Behavior on color { ColorAnimation { duration: 90 } }
    Text {
      id: ibGlyph
      anchors.centerIn: parent
      text: ib.glyph
      font.family: t.mono
      font.pixelSize: ib.fs
      color: ib.dimmed ? t.ink3 : ((ma.containsMouse || ma.pressed) ? t.ink1 : ib.fg)
      opacity: ib.dimmed ? 0.35 : 1.0
      Behavior on color { ColorAnimation { duration: 90 } }
    }
    MouseArea {
      id: ma
      anchors.fill: parent
      hoverEnabled: !ib.dimmed
      cursorShape: ib.dimmed ? Qt.ArrowCursor : Qt.PointingHandCursor
      onClicked: {
        if (!ib.dimmed) ib.clicked();
      }
    }
  }

  // macOS-style switch. Track carries the color, thumb just slides.
  component TSwitch: Item {
    id: sw
    signal toggled
    property bool on: false
    property color onColor: t.green
    property bool enabledSwitch: true
    width: 42
    height: 24
    opacity: sw.enabledSwitch ? 1.0 : 0.35
    Rectangle {
      anchors.fill: parent
      radius: 12
      color: sw.on ? sw.onColor : "#3B3C4C"
      Behavior on color { ColorAnimation { duration: 140 } }
      Rectangle {
        width: 20
        height: 20
        radius: 10
        y: 2
        x: sw.on ? parent.width - width - 2 : 2
        color: "#F4F4F8"
        Behavior on x { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
      }
    }
    MouseArea {
      anchors.fill: parent
      hoverEnabled: sw.enabledSwitch
      cursorShape: sw.enabledSwitch ? Qt.PointingHandCursor : Qt.ArrowCursor
      onClicked: {
        if (sw.enabledSwitch) sw.toggled();
      }
    }
  }

  // One inset track, segments share it — not separate pills.
  component Segments: Item {
    id: sg
    property var items: []
    property int current: 0
    signal selected(int index)
    implicitHeight: 34
    Rectangle {
      anchors.fill: parent
      radius: 10
      color: t.inset
    }
    Row {
      anchors.fill: parent
      anchors.margins: 3
      spacing: 2
      Repeater {
        model: sg.items
        Item {
          required property var modelData
          required property int index
          width: (parent.width - 2 * (sg.items.length - 1)) / sg.items.length
          height: parent.height
          Rectangle {
            anchors.fill: parent
            radius: 7
            color: sg.current === index ? "#2E2F42" : (segMa.containsMouse || segMa.pressed ? "#22232F" : "transparent")
            Behavior on color { ColorAnimation { duration: 110 } }
          }
          Row {
            anchors.centerIn: parent
            spacing: 6
            Text {
              anchors.verticalCenter: parent.verticalCenter
              text: modelData.label
              font.pixelSize: 12
              font.weight: sg.current === index ? Font.DemiBold : Font.Normal
              color: sg.current === index ? t.ink1 : t.ink2
            }
            Rectangle {
              visible: Boolean(modelData.playing)
              anchors.verticalCenter: parent.verticalCenter
              width: 5
              height: 5
              radius: 2.5
              color: t.green
            }
          }
          MouseArea {
            id: segMa
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: sg.selected(index)
          }
        }
      }
    }
  }

  // Single solid primary action. Fill darkens on press like a native button.
  component PrimaryBtn: Rectangle {
    id: pb
    signal clicked
    property string text: ""
    property string glyph: ""
    property color fill: t.accent
    property color ink: t.darkInk
    property bool enabledBtn: true
    implicitHeight: 34
    radius: 9
    scale: (ma.pressed && pb.enabledBtn) ? 0.985 : 1.0
    Behavior on scale { NumberAnimation { duration: 80 } }
    color: !pb.enabledBtn ? "#24252F" : ma.pressed ? Qt.darker(fill, 1.2) : ma.containsMouse ? Qt.lighter(fill, 1.07) : fill
    Behavior on color { ColorAnimation { duration: 90 } }
    Row {
      anchors.centerIn: parent
      spacing: 7
      Text {
        visible: pb.glyph.length > 0
        anchors.verticalCenter: parent.verticalCenter
        text: pb.glyph
        font.family: t.mono
        font.pixelSize: 12
        color: pb.enabledBtn ? pb.ink : t.ink3
      }
      Text {
        anchors.verticalCenter: parent.verticalCenter
        text: pb.text
        font.pixelSize: 13
        font.weight: Font.DemiBold
        color: pb.enabledBtn ? pb.ink : t.ink3
      }
    }
    MouseArea {
      id: ma
      anchors.fill: parent
      hoverEnabled: pb.enabledBtn
      cursorShape: pb.enabledBtn ? Qt.PointingHandCursor : Qt.ArrowCursor
      onClicked: {
        if (pb.enabledBtn) pb.clicked();
      }
    }
  }

  // ================= Card =================
  Rectangle {
    id: card
    anchors.fill: parent
    radius: 14
    color: t.bg
    border.color: "#26272F"
    border.width: 1

    Flickable {
      anchors.fill: parent
      anchors.margins: 16
      contentWidth: width
      contentHeight: bodyCol.height
      clip: true

      Column {
        id: bodyCol
        width: parent.width
        spacing: 0

        // ---- Header: identity left, status word right ----
        RowLayout {
          width: parent.width
          height: 40
          spacing: 10

          Text {
            text: "󰝚"
            font.family: t.mono
            font.pixelSize: 19
            color: root.statusColor
            Behavior on color { ColorAnimation { duration: 150 } }
          }

          Column {
            Layout.fillWidth: true
            spacing: 1
            Text {
              text: "Media"
              font.pixelSize: 14
              font.weight: Font.DemiBold
              color: t.ink1
            }
            Text {
              width: parent.width
              text: root.hasPlayer ? (root.playerLabel(root.player) + " · " + root.statusWord) : "Nothing playing"
              font.pixelSize: 11
              color: t.ink3
              elide: Text.ElideRight
            }
          }

          Text {
            visible: root.hasPlayer
            text: root.statusWord
            font.pixelSize: 12
            font.weight: Font.Medium
            color: root.statusColor
          }
        }

        Item { width: 1; height: 14 }

        // ---- Source switcher: one inset track when several players exist ----
        Segments {
          visible: root.playerCount > 1
          width: parent.width
          height: visible ? 34 : 0
          items: {
            const out = [];
            for (let i = 0; i < root.playerList.length; i++) {
              const p = root.playerList[i];
              out.push({ label: (root.playerLabel(p) || "Player").slice(0, 14), playing: p.isPlaying });
            }
            return out;
          }
          current: {
            for (let j = 0; j < root.playerList.length; j++) {
              if (root.playerList[j] === root.player) return j;
            }
            return 0;
          }
          onSelected: index => {
            if (index >= 0 && index < root.playerList.length) {
              root.manualPlayer = root.playerList[index];
            }
          }
        }

        Item { visible: root.playerCount > 1; width: 1; height: 12 }

        // ---- Now playing: grouped rows, artwork + seek + transport ----
        SectionHead {
          width: parent.width
          label: "Now playing"
        }

        Item { width: 1; height: 6 }

        Rectangle {
          visible: root.hasPlayer
          width: parent.width
          height: playingCol.height
          radius: 12
          color: t.surface

          Column {
            id: playingCol
            width: parent.width

            // Track row: artwork left, title/artist/album right. Inert.
            RowBase {
              width: parent.width
              height: 96
              rad: 12
              actionable: false
              RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 12
                anchors.rightMargin: 12
                anchors.topMargin: 8
                anchors.bottomMargin: 8
                spacing: 12

                Rectangle {
                  Layout.preferredWidth: 80
                  Layout.preferredHeight: 80
                  radius: 8
                  color: t.inset
                  clip: true

                  Image {
                    id: artImage
                    anchors.fill: parent
                    source: root.player ? root.formatArtUrl(root.player.trackArtUrl) : ""
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                    visible: status === Image.Ready
                  }

                  Text {
                    anchors.centerIn: parent
                    visible: artImage.status !== Image.Ready
                    text: "󰝚"
                    font.family: t.mono
                    font.pixelSize: 28
                    color: t.ink3
                    opacity: 0.8
                  }
                }

                ColumnLayout {
                  Layout.fillWidth: true
                  Layout.alignment: Qt.AlignVCenter
                  spacing: 2

                  Text {
                    Layout.fillWidth: true
                    text: root.player ? (root.player.trackTitle || "No Title") : "No Media"
                    font.pixelSize: 14
                    font.weight: Font.DemiBold
                    color: t.ink1
                    elide: Text.ElideRight
                    maximumLineCount: 1
                  }

                  Text {
                    Layout.fillWidth: true
                    text: {
                      if (!root.player) return "Unknown Artist";
                      if (root.player.trackArtist) return root.player.trackArtist;
                      if (root.player.trackArtists && root.player.trackArtists.length > 0) return root.player.trackArtists.join(", ");
                      return "Unknown Artist";
                    }
                    font.pixelSize: 12
                    color: t.ink2
                    elide: Text.ElideRight
                    maximumLineCount: 1
                  }

                  Text {
                    Layout.fillWidth: true
                    visible: text.length > 0
                    text: root.player && root.player.trackAlbum ? root.player.trackAlbum : ""
                    font.pixelSize: 11
                    color: t.ink3
                    elide: Text.ElideRight
                    maximumLineCount: 1
                  }
                }
              }
            }

            Hairline { width: parent.width - 24; anchors.horizontalCenter: parent.horizontalCenter }

            // Progress row: seek bar + timestamps. Inert container, MouseArea owns input.
            Column {
              width: parent.width
              anchors.leftMargin: 0
              spacing: 2

              Item {
                id: seekHit
                width: parent.width - 24
                anchors.horizontalCenter: parent.horizontalCenter
                height: 26

                Rectangle {
                  id: seekTrack
                  anchors.left: parent.left
                  anchors.right: parent.right
                  anchors.verticalCenter: parent.verticalCenter
                  height: seekMouse.containsMouse || root.isSeeking ? 6 : 4
                  radius: height / 2
                  color: t.inset
                  Behavior on height { NumberAnimation { duration: 100 } }

                  Rectangle {
                    id: seekFill
                    anchors.left: parent.left
                    anchors.top: parent.top
                    anchors.bottom: parent.bottom
                    width: root.trackLength > 0 ? Math.min(parent.width, Math.max(0, parent.width * (root.trackPos / root.trackLength))) : 0
                    radius: parent.radius
                    color: t.accent
                  }

                  Rectangle {
                    id: seekThumb
                    width: 10
                    height: 10
                    radius: 5
                    color: t.ink1
                    anchors.verticalCenter: parent.verticalCenter
                    x: Math.max(0, Math.min(parent.width - width, seekFill.width - width / 2))
                    visible: seekMouse.containsMouse || root.isSeeking
                    opacity: visible ? 1 : 0
                    Behavior on opacity { NumberAnimation { duration: 100 } }
                  }
                }

                MouseArea {
                  id: seekMouse
                  anchors.fill: parent
                  hoverEnabled: true
                  cursorShape: (root.player && root.player.canSeek && root.trackLength > 0) ? Qt.PointingHandCursor : Qt.ArrowCursor

                  function updatePos(mouseX: real): void {
                    if (!root.player || !root.player.canSeek || root.trackLength <= 0) return;
                    const ratio = Math.max(0, Math.min(1, mouseX / width));
                    root.seekTarget = ratio * root.trackLength;
                  }

                  onPressed: mouse => {
                    if (!root.player || !root.player.canSeek || root.trackLength <= 0) return;
                    root.isSeeking = true;
                    updatePos(mouse.x);
                  }

                  onPositionChanged: mouse => {
                    if (root.isSeeking) {
                      updatePos(mouse.x);
                    }
                  }

                  onReleased: {
                    if (root.isSeeking) {
                      if (root.player && root.player.canSeek) {
                        root.player.position = root.seekTarget;
                      }
                      root.isSeeking = false;
                    }
                  }
                }
              }

              RowLayout {
                width: parent.width - 24
                anchors.horizontalCenter: parent.horizontalCenter
                Text {
                  text: root.formatSeconds(root.trackPos)
                  font.family: t.mono
                  font.pixelSize: 11
                  color: t.ink2
                }
                Item { Layout.fillWidth: true }
                Text {
                  text: root.trackLength > 0 ? root.formatSeconds(root.trackLength) : "--:--"
                  font.family: t.mono
                  font.pixelSize: 11
                  color: t.ink3
                }
              }

              Item { width: 1; height: 4 }
            }

            Hairline { width: parent.width - 24; anchors.horizontalCenter: parent.horizontalCenter }

            // Transport row: quiet washes, one solid primary play action.
            RowLayout {
              width: parent.width - 24
              anchors.horizontalCenter: parent.horizontalCenter
              height: 56
              spacing: 4

              Item { Layout.fillWidth: true }

              IconBtn {
                glyph: "󰒮"
                fs: 16
                dimmed: !(root.player && root.player.canGoPrevious)
                onClicked: {
                  if (root.player && root.player.canGoPrevious) root.player.previous();
                }
              }

              Item { Layout.preferredWidth: 6; Layout.preferredHeight: 1 }

              // Play / pause: the single solid action in this group.
              Rectangle {
                Layout.preferredWidth: 46
                Layout.preferredHeight: 38
                radius: 10
                color: playMouse.pressed ? Qt.darker(t.accent, 1.2) : playMouse.containsMouse ? Qt.lighter(t.accent, 1.07) : t.accent
                Behavior on color { ColorAnimation { duration: 90 } }
                Text {
                  anchors.centerIn: parent
                  anchors.horizontalCenterOffset: root.isPlaying ? 0 : 1
                  text: root.isPlaying ? "󰏤" : "󰐊"
                  font.family: t.mono
                  font.pixelSize: 17
                  color: t.darkInk
                }
                MouseArea {
                  id: playMouse
                  anchors.fill: parent
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  onClicked: {
                    if (root.player && root.player.canTogglePlaying) root.player.togglePlaying();
                  }
                }
              }

              Item { Layout.preferredWidth: 6; Layout.preferredHeight: 1 }

              IconBtn {
                glyph: "󰒭"
                fs: 16
                dimmed: !(root.player && root.player.canGoNext)
                onClicked: {
                  if (root.player && root.player.canGoNext) root.player.next();
                }
              }

              Item { Layout.fillWidth: true }
            }
          }
        }

        // ---- Empty state: quiet words, no box (mirrors Tailscale peers empty) ----
        Item {
          visible: !root.hasPlayer
          width: parent.width
          height: 64
          Column {
            anchors.centerIn: parent
            spacing: 3
            Text {
              anchors.horizontalCenter: parent.horizontalCenter
              text: "No media playing"
              font.pixelSize: 12
              color: t.ink2
            }
            Text {
              anchors.horizontalCenter: parent.horizontalCenter
              text: "Play audio or video in any app to control it here."
              font.pixelSize: 11
              color: t.ink3
            }
          }
        }

        Item { visible: root.hasPlayer; width: 1; height: 14 }

        // ---- Playback: toggles as grouped rows with switches (mirrors Tailscale Settings) ----
        SectionHead {
          visible: root.hasPlayer
          width: parent.width
          label: "Playback"
        }

        Item { visible: root.hasPlayer; width: 1; height: 6 }

        Rectangle {
          visible: root.hasPlayer
          width: parent.width
          height: prefsCol.height
          radius: 12
          color: t.surface

          Column {
            id: prefsCol
            width: parent.width

            RowBase {
              width: parent.width
              height: 54
              rad: 12
              actionable: Boolean(root.player && root.player.shuffleSupported && root.player.canControl)
              onClicked: {
                if (root.player && root.player.shuffleSupported && root.player.canControl) {
                  root.player.shuffle = !root.player.shuffle;
                }
              }
              RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 12
                anchors.rightMargin: 12
                spacing: 10
                Text {
                  text: "󰒝"
                  font.family: t.mono
                  font.pixelSize: 15
                  color: (root.player && root.player.shuffle) ? t.accent : t.ink3
                }
                Column {
                  Layout.fillWidth: true
                  spacing: 1
                  Text {
                    text: "Shuffle"
                    font.pixelSize: 13
                    font.weight: Font.Medium
                    color: t.ink1
                  }
                  Text {
                    text: (root.player && root.player.shuffle) ? "Playing tracks in random order" : "Play tracks in order"
                    font.pixelSize: 11
                    color: t.ink3
                  }
                }
                TSwitch {
                  on: Boolean(root.player && root.player.shuffle)
                  onColor: t.accent
                  enabledSwitch: Boolean(root.player && root.player.shuffleSupported && root.player.canControl)
                  onToggled: {
                    if (root.player && root.player.shuffleSupported && root.player.canControl) {
                      root.player.shuffle = !root.player.shuffle;
                    }
                  }
                }
              }
            }

            Hairline { width: parent.width - 24; anchors.horizontalCenter: parent.horizontalCenter }

            RowBase {
              width: parent.width
              height: 54
              rad: 12
              actionable: Boolean(root.player && root.player.loopSupported && root.player.canControl)
              onClicked: root.cycleLoop()
              RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 12
                anchors.rightMargin: 12
                spacing: 10
                Text {
                  text: (root.player && root.player.loopState === 1) ? "󰑘" : "󰑖"
                  font.family: t.mono
                  font.pixelSize: 15
                  color: (root.player && root.player.loopState !== 0) ? t.accent : t.ink3
                }
                Column {
                  Layout.fillWidth: true
                  spacing: 1
                  Text {
                    text: "Repeat"
                    font.pixelSize: 13
                    font.weight: Font.Medium
                    color: t.ink1
                  }
                  Text {
                    text: {
                      const w = root.loopWord();
                      if (w === "Track") return "Repeating this track";
                      if (w === "Playlist") return "Repeating the whole queue";
                      return "Repeat is off";
                    }
                    font.pixelSize: 11
                    color: t.ink3
                  }
                }
                Text {
                  visible: Boolean(root.player && root.player.loopSupported)
                  text: root.loopWord()
                  font.pixelSize: 12
                  font.weight: Font.Medium
                  color: (root.player && root.player.loopState !== 0) ? t.accent : t.ink2
                }
              }
            }
          }
        }
      }
    }
  }
}
