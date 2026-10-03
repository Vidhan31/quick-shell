pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Quickshell.Widgets
import Quickshell.Services.Mpris
import qs.services
import "../theme"
import "../components"

Item {
  id: root

  property var media: null
  readonly property var activeMedia: media

  readonly property var playerList: activeMedia ? activeMedia.playerList : []
  readonly property int playerCount: activeMedia ? activeMedia.playerCount : 0

  readonly property var player: activeMedia ? activeMedia.activePlayer : null
  readonly property bool hasPlayer: activeMedia ? activeMedia.hasPlayer : false

  readonly property bool isPlaying: activeMedia ? activeMedia.isPlaying : false

  property bool isSeeking: false
  property real seekTarget: 0

  readonly property real trackLength: activeMedia ? activeMedia.trackLength : 0
  readonly property real trackPos: isSeeking ? seekTarget : (activeMedia ? activeMedia.trackPos : 0)
  readonly property string formattedPosition: isSeeking
    ? (activeMedia ? activeMedia.formatSeconds(seekTarget) : "0:00")
    : (activeMedia ? activeMedia.formattedPosition : "0:00")
  readonly property string formattedLength: activeMedia ? activeMedia.formattedLength : "--:--"

  readonly property color statusColor: {
    if (!root.hasPlayer) return root.t.ink3;
    if (root.isPlaying) return root.t.green;
    return root.t.amber;
  }
  readonly property string statusWord: {
    if (!root.hasPlayer) return "Not playing";
    if (root.isPlaying) return "Playing";
    return "Paused";
  }

  function findHost(): var {
    let p = root.parent;
    while (p) {
      if (typeof p.showTip === "function") return p;
      if (p.barWindow && typeof p.barWindow.showTip === "function") return p.barWindow;
      p = p.parent;
    }
    return null;
  }

  Component.onDestruction: {
    const host = root.findHost();
    if (host && typeof host.hideTip === "function") {
      host.hideTip();
    }
  }


  implicitWidth: Theme.popupWidthMd
  readonly property int preferredHeight: Math.min(400, 28 + bodyCol.height)
  property int popupHeight: 200

  function syncHeight() {
    if (bodyCol.height > 0)
      popupHeight = preferredHeight;
  }

  onPreferredHeightChanged: {
    if (bodyCol.height > 0)
      popupHeight = preferredHeight;
  }

  implicitHeight: popupHeight

  readonly property var t: Theme

  PopupCard {
    id: card
    anchors.fill: parent

    Flickable {
      anchors.fill: parent
      contentWidth: width
      contentHeight: bodyCol.height
      clip: true

      Column {
        id: bodyCol
        width: parent.width
        spacing: 10

        Segments {
          visible: root.playerCount > 1
          width: parent.width
          height: visible ? 32 : 0
          items: {
            const out = [];
            for (let i = 0; i < root.playerList.length; i++) {
              const p = root.playerList[i];
              const name = (root.activeMedia ? root.activeMedia.playerLabel(p) : (p && p.identity)) || "Player";
              out.push({ label: name.slice(0, 14), playing: p.isPlaying });
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
            if (index >= 0 && index < root.playerList.length && root.activeMedia) {
              root.activeMedia.selectPlayer(root.playerList[index]);
            }
          }
        }

        Column {
          visible: root.hasPlayer
          width: parent.width
          spacing: 10

          RowLayout {
            width: parent.width
            spacing: 12

            ClippingRectangle {
              Layout.preferredWidth: 64
              Layout.preferredHeight: 64
              radius: Theme.radiusBase
              color: root.t.inset

              Image {
                id: artImage
                anchors.fill: parent
                source: root.activeMedia ? root.activeMedia.trackArtUrl : ""
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                visible: status === Image.Ready
              }

              Text {
                anchors.centerIn: parent
                visible: artImage.status !== Image.Ready
                text: "󰝚"
                font.family: root.t.mono
                font.pixelSize: 24
                color: root.t.ink3
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
                font.pixelSize: Theme.fontBase
                font.weight: Font.DemiBold
                color: root.t.ink1
                elide: Text.ElideRight
                maximumLineCount: 1
              }

              Text {
                Layout.fillWidth: true
                text: {
                  if (!root.player) return "Unknown Artist";
                  if (root.player.trackArtist) return root.player.trackArtist;
                  if (root.player.trackAlbumArtist) return root.player.trackAlbumArtist;
                  return "Unknown Artist";
                }
                font.pixelSize: Theme.fontSm
                color: root.t.ink2
                elide: Text.ElideRight
                maximumLineCount: 1
              }

              Text {
                Layout.fillWidth: true
                visible: text.length > 0
                text: {
                  const parts = [];
                  if (root.player && root.player.trackAlbum) parts.push(root.player.trackAlbum);
                  if (root.player && root.playerCount <= 1 && root.activeMedia) {
                    const label = root.activeMedia.playerLabel(root.player);
                    if (label) parts.push(label);
                  }
                  return parts.join(" · ");
                }
                font.pixelSize: Theme.fontXs
                color: root.t.ink3
                elide: Text.ElideRight
                maximumLineCount: 1
              }
            }
          }

          Column {
            width: parent.width
            spacing: 2

            Item {
              id: seekHit
              width: parent.width
              height: 20
              activeFocusOnTab: Boolean(root.player && root.player.canSeek && root.trackLength > 0)

              Accessible.role: Accessible.Slider
              Accessible.name: "Seek: " + root.formattedPosition

              Keys.onLeftPressed: event => {
                if (root.activeMedia && root.player && root.player.canSeek) {
                  root.activeMedia.setTrackPos(Math.max(0, root.trackPos - 5));
                  event.accepted = true;
                }
              }
              Keys.onRightPressed: event => {
                if (root.activeMedia && root.player && root.player.canSeek) {
                  root.activeMedia.setTrackPos(Math.min(root.trackLength, root.trackPos + 5));
                  event.accepted = true;
                }
              }

              Rectangle {
                id: seekTrack
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                height: seekMouse.containsMouse || root.isSeeking || seekHit.activeFocus ? 6 : 4
                radius: height / 2
                color: root.t.inset
                border.color: seekHit.activeFocus ? root.t.focusRing : "transparent"
                border.width: seekHit.activeFocus ? 1.5 : 0
                Behavior on height { NumberAnimation { duration: 100 } }
                Behavior on border.color { ColorAnimation { duration: 100 } }

                Rectangle {
                  id: seekFill
                  anchors.left: parent.left
                  anchors.top: parent.top
                  anchors.bottom: parent.bottom
                  width: root.trackLength > 0 ? Math.min(parent.width, Math.max(0, parent.width * (root.trackPos / root.trackLength))) : 0
                  radius: parent.radius
                  color: root.t.accent
                }

                Rectangle {
                  id: seekThumb
                  width: 10
                  height: 10
                  radius: 5
                  color: root.t.ink1
                  anchors.verticalCenter: parent.verticalCenter
                  x: Math.max(0, Math.min(parent.width - width, seekFill.width - width / 2))
                  visible: seekMouse.containsMouse || root.isSeeking || seekHit.activeFocus
                  opacity: visible ? 1 : 0
                  Behavior on opacity { OpacityAnimator { duration: 100 } }
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
                  seekHit.forceActiveFocus();
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
                    if (root.activeMedia && root.player && root.player.canSeek) {
                      root.activeMedia.setTrackPos(root.seekTarget);
                    }
                    root.isSeeking = false;
                  }
                }
              }
            }

            RowLayout {
              width: parent.width
              Text {
                text: root.formattedPosition
                font.family: root.t.mono
                font.pixelSize: Theme.fontXs
                color: root.t.ink2
              }
              Item { Layout.fillWidth: true }
              Text {
                text: root.formattedLength
                font.family: root.t.mono
                font.pixelSize: Theme.fontXs
                color: root.t.ink3
              }
            }
          }

          RowLayout {
            width: parent.width
            height: 40
            spacing: 0

            IconBtn {
              glyph: "󰒝"
              fs: Theme.iconBase
              btnSize: 32
              fg: (root.player && root.player.shuffle) ? root.t.accent : root.t.ink3
              dimmed: !(root.player && root.player.shuffleSupported && root.player.canControl)
              tooltip: (root.player && root.player.shuffle) ? "Shuffle on" : "Shuffle off"
              onClicked: {
                if (root.player && root.player.shuffleSupported && root.player.canControl) {
                  root.player.shuffle = !root.player.shuffle;
                }
              }
            }

            Item { Layout.fillWidth: true }

            IconBtn {
              glyph: "󰒮"
              fs: Theme.iconMd
              btnSize: 34
              dimmed: !(root.player && root.player.canGoPrevious)
              tooltip: "Previous track"
              onClicked: {
                if (root.player && root.player.canGoPrevious) root.player.previous();
              }
            }

            Item { Layout.preferredWidth: 8; Layout.preferredHeight: 1 }

            Rectangle {
              id: playPauseBtn
              Layout.preferredWidth: 44
              Layout.preferredHeight: 34
              radius: Theme.radiusChip
              activeFocusOnTab: true
              color: playMouse.pressed ? Qt.darker(root.t.accent, 1.2) : (playMouse.containsMouse || playPauseBtn.activeFocus) ? Qt.lighter(root.t.accent, 1.07) : root.t.accent
              border.color: playPauseBtn.activeFocus ? root.t.ink1 : "transparent"
              border.width: playPauseBtn.activeFocus ? 1.5 : 0
              Behavior on color { ColorAnimation { duration: 90 } }
              Behavior on border.color { ColorAnimation { duration: 90 } }

              Accessible.role: Accessible.Button
              Accessible.name: root.isPlaying ? "Pause" : "Play"

              Keys.onReturnPressed: event => {
                if (root.player && root.player.canTogglePlaying) {
                  root.player.togglePlaying();
                  event.accepted = true;
                }
              }
              Keys.onSpacePressed: event => {
                if (root.player && root.player.canTogglePlaying) {
                  root.player.togglePlaying();
                  event.accepted = true;
                }
              }

              Text {
                anchors.centerIn: parent
                anchors.horizontalCenterOffset: root.isPlaying ? 0 : 1
                text: root.isPlaying ? "󰏤" : "󰐊"
                font.family: root.t.mono
                font.pixelSize: Theme.iconMd
                color: root.t.darkInk
              }
              MouseArea {
                id: playMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onContainsMouseChanged: {
                  const host = root.findHost();
                  if (containsMouse) {
                    if (host && typeof host.showTip === "function") {
                      host.showTip(parent, root.isPlaying ? "Pause" : "Play", "");
                    }
                  } else {
                    if (host && typeof host.hideTip === "function") {
                      host.hideTip();
                    }
                  }
                }
                onClicked: {
                  const host = root.findHost();
                  if (host && typeof host.hideTip === "function") {
                    host.hideTip();
                  }
                  if (root.player && root.player.canTogglePlaying) root.player.togglePlaying();
                }
              }
            }

            Item { Layout.preferredWidth: 8; Layout.preferredHeight: 1 }

            IconBtn {
              glyph: "󰒭"
              fs: Theme.iconMd
              btnSize: 34
              dimmed: !(root.player && root.player.canGoNext)
              tooltip: "Next track"
              onClicked: {
                if (root.player && root.player.canGoNext) root.player.next();
              }
            }

            Item { Layout.fillWidth: true }

            IconBtn {
              glyph: (root.player && root.player.loopState === MprisLoopState.Track) ? "󰑘" : "󰑖"
              fs: Theme.iconBase
              btnSize: 32
              fg: (root.player && root.player.loopState !== MprisLoopState.None) ? root.t.accent : root.t.ink3
              dimmed: !(root.player && root.player.loopSupported && root.player.canControl)
              tooltip: "Repeat mode: " + (root.activeMedia ? root.activeMedia.loopWord() : "Off")
              onClicked: {
                if (root.activeMedia) root.activeMedia.cycleLoop();
              }
            }
          }
        }

        Item {
          visible: !root.hasPlayer
          width: parent.width
          height: 90
          Column {
            anchors.centerIn: parent
            spacing: 6
            Text {
              anchors.horizontalCenter: parent.horizontalCenter
              text: "󰝚"
              font.family: root.t.mono
              font.pixelSize: 26
              color: root.t.ink3
            }
            Text {
              anchors.horizontalCenter: parent.horizontalCenter
              text: "No media playing"
              font.pixelSize: Theme.fontBase
              color: root.t.ink2
            }
          }
        }
      }
    }
  }
}
