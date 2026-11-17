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
    if (!root.hasPlayer) return Theme.ink3;
    if (root.isPlaying) return Theme.green;
    return Theme.amber;
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
  readonly property int preferredHeight: Math.min(360, Theme.cardPadding * 2 + bodyCol.height)
  property int popupHeight: 240

  function syncHeight() {
    if (bodyCol.height > 0)
      popupHeight = preferredHeight;
  }

  onPreferredHeightChanged: {
    if (bodyCol.height > 0)
      popupHeight = preferredHeight;
  }

  implicitHeight: popupHeight

  PopupCard {
    id: card
    anchors.fill: parent
    padding: 10

    Image {
      id: heroBackdrop
      anchors.fill: parent
      source: root.activeMedia ? root.activeMedia.trackArtUrl : ""
      sourceSize: Qt.size(900, 700)
      fillMode: Image.PreserveAspectCrop
      asynchronous: true
      opacity: status === Image.Ready ? 0.58 : 0
    }

    Rectangle {
      anchors.fill: parent
      gradient: Gradient {
        orientation: Gradient.Horizontal
        GradientStop { position: 0.0; color: Theme.tint(Theme.bg, 0.84) }
        GradientStop { position: 0.48; color: Theme.tint(Theme.bg, 0.70) }
        GradientStop { position: 1.0; color: Theme.tint(Theme.bg, 0.52) }
      }
    }

    Flickable {
      anchors.fill: parent
      contentWidth: width
      contentHeight: bodyCol.height
      clip: true

      Column {
        id: bodyCol
        width: parent.width
        spacing: 10

        SegmentedControl {
          visible: root.playerCount > 1
          width: parent.width
          height: visible ? 30 : 0
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
            spacing: 14

            ClippingRectangle {
              Layout.preferredWidth: 136
              Layout.preferredHeight: 136
              radius: 4
              color: Theme.inset

              Image {
                id: artImage
                anchors.fill: parent
                source: root.activeMedia ? root.activeMedia.trackArtUrl : ""
                sourceSize: Qt.size(272, 272)
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                visible: status === Image.Ready
              }

              Text {
                anchors.centerIn: parent
                visible: artImage.status !== Image.Ready
                text: "󰝚"
                font.family: Theme.mono
                font.pixelSize: 36
                color: Theme.ink3
              }
            }

            Rectangle {
              Layout.preferredWidth: 2
              Layout.preferredHeight: 76
              radius: 1
              color: root.statusColor
              opacity: 0.9
            }

            ColumnLayout {
              Layout.fillWidth: true
              Layout.alignment: Qt.AlignVCenter
              spacing: 5

              Text {
                Layout.fillWidth: true
                text: root.player ? (root.player.trackTitle || "No Title") : "No Media"
                font.family: Theme.displayFont
                font.pixelSize: Theme.fontDisplay
                font.weight: Font.DemiBold
                color: Theme.ink1
                elide: Text.ElideRight
                maximumLineCount: 2
                wrapMode: Text.Wrap
              }

              Text {
                Layout.fillWidth: true
                text: {
                  if (!root.player) return "Unknown Artist";
                  if (root.player.trackArtist) return root.player.trackArtist;
                  if (root.player.trackAlbumArtist) return root.player.trackAlbumArtist;
                  return "Unknown Artist";
                }
                font.family: Theme.textFont
                font.pixelSize: Theme.fontMd
                color: Theme.ink2
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
                font.family: Theme.textFont
                font.pixelSize: Theme.fontSm
                color: Theme.ink3
                elide: Text.ElideRight
                maximumLineCount: 1
              }
            }
          }

          Column {
            width: parent.width
            spacing: 2

            Slider {
              id: seekHit
              width: parent.width
              value: root.trackPos
              from: 0.0
              to: root.trackLength > 0 ? root.trackLength : 1.0
              stepSize: 5.0
              enabledSlider: Boolean(root.player && root.player.canSeek && root.trackLength > 0)
              accessibleName: "Seek: " + root.formattedPosition
              activeColor: Theme.accent
              onMoved: val => {
                root.seekTarget = val;
              }
              onCommitted: val => {
                if (root.activeMedia && root.player && root.player.canSeek) {
                  root.activeMedia.setTrackPos(val);
                }
              }
              onDraggingChanged: dragging => {
                root.isSeeking = dragging;
              }
            }

            RowLayout {
              width: parent.width
              Text {
                text: root.formattedPosition
                font.family: Theme.mono
                font.pixelSize: Theme.fontXs
                color: Theme.ink2
              }
              Item { Layout.fillWidth: true }
              Text {
                text: root.formattedLength
                font.family: Theme.mono
                font.pixelSize: Theme.fontXs
                color: Theme.ink3
              }
            }
          }

          RowLayout {
            width: parent.width
            height: 40
            spacing: 0

            IconButton {
              glyph: "󰒝"
              fs: Theme.iconBase
              btnSize: 30
              fg: (root.player && root.player.shuffle) ? Theme.accent : Theme.ink3
              dimmed: !(root.player && root.player.shuffleSupported && root.player.canControl)
              tooltip: (root.player && root.player.shuffle) ? "Shuffle on" : "Shuffle off"
              onClicked: {
                if (root.player && root.player.shuffleSupported && root.player.canControl) {
                  root.player.shuffle = !root.player.shuffle;
                }
              }
            }

            Item { Layout.fillWidth: true }

            IconButton {
              glyph: "󰒮"
              fs: Theme.iconMd
              btnSize: 32
              dimmed: !(root.player && root.player.canGoPrevious)
              tooltip: "Previous track"
              onClicked: {
                if (root.player && root.player.canGoPrevious) root.player.previous();
              }
            }

            Item { Layout.preferredWidth: 8; Layout.preferredHeight: 1 }

            PrimaryButton {
              id: playPauseBtn
              circular: true
              btnSize: 40
              glyph: root.isPlaying ? "󰏤" : "󰐊"
              glyphSize: Theme.iconLg
              glyphOffset: root.isPlaying ? 0 : 1
              tooltip: root.isPlaying ? "Pause" : "Play"
              enabledBtn: Boolean(root.player && root.player.canTogglePlaying)
              onClicked: {
                if (root.player && root.player.canTogglePlaying) root.player.togglePlaying();
              }
            }

            Item { Layout.preferredWidth: 8; Layout.preferredHeight: 1 }

            IconButton {
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

            IconButton {
              glyph: (root.player && root.player.loopState === MprisLoopState.Track) ? "󰑘" : "󰑖"
              fs: Theme.iconBase
              btnSize: 32
              fg: (root.player && root.player.loopState !== MprisLoopState.None) ? Theme.accent : Theme.ink3
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
              font.family: Theme.mono
              font.pixelSize: 26
              color: Theme.ink3
            }
            Text {
              anchors.horizontalCenter: parent.horizontalCenter
              text: "No media playing"
              font.family: Theme.textFont
              font.pixelSize: Theme.fontBase
              color: Theme.ink2
            }
          }
        }
      }
    }
  }
}
