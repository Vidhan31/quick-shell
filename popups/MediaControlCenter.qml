pragma ComponentBehavior: Bound
// MediaControlCenter.qml — Media playback popup.
// Tailscale visual system: same tokens, card, grouped surface rows with hairlines,
// SectionHead, RowBase, TextBtn, IconBtn, TSwitch, Segments. Words + tint carry
// state, no badge pills or boxed banners. Content hugs bodyCol.height (capped) so
// the popover never clips or leaves empty space; overflow scrolls inside the card.
// Official Quickshell.Services.Mpris backend via qs.services.MediaService.
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Widgets
import Quickshell.Services.Mpris
import qs.services
import "../theme"
import "../components"

Item {
  id: root

  property var media: null

  Loader {
    id: fallbackMediaLoader
    active: root.media === null
    sourceComponent: MediaService {}
  }

  readonly property var activeMedia: root.media ? root.media : fallbackMediaLoader.item

  // Position tracking: re-emits the official positionChanged signal every frame
  // (FrameAnimation in MediaService) only when the popup is visible.
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

  // All available players from the official MPRIS service
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
    if (!url) {
      return "";
    }
    if (url.startsWith("/") && !url.startsWith("//")) {
      return "file://" + url;
    }
    return url;
  }

  function playerLabel(p: var): string {
    if (!p) return "";
    return p.identity || "Player";
  }

  function cycleLoop(): void {
    if (!root.player || !root.player.loopSupported || !root.player.canControl) return;
    if (root.player.loopState === MprisLoopState.None) {
      root.player.loopState = MprisLoopState.Playlist;
    } else if (root.player.loopState === MprisLoopState.Playlist) {
      root.player.loopState = MprisLoopState.Track;
    } else {
      root.player.loopState = MprisLoopState.None;
    }
  }

  function loopWord(): string {
    if (!root.player) return "Off";
    if (root.player.loopState === MprisLoopState.Track) return "Track";
    if (root.player.loopState === MprisLoopState.Playlist) return "Playlist";
    return "Off";
  }

  implicitWidth: 440
  readonly property int preferredHeight: Math.min(640, 32 + bodyCol.height)
  property int popupHeight: 360

  function syncHeight() {
    popupHeight = preferredHeight;
  }

  onPreferredHeightChanged: {
    if (!root.visible)
      popupHeight = preferredHeight;
  }

  implicitHeight: popupHeight

  readonly property var t: Theme

  // ================= Card =================
  Rectangle {
    id: card
    anchors.fill: parent
    radius: Theme.radiusCard
    color: Theme.bg
    border.color: Theme.cardBorder
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

                ClippingRectangle {
                  Layout.preferredWidth: 80
                  Layout.preferredHeight: 80
                  radius: 8
                  color: t.inset

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
                      if (root.player.trackAlbumArtist) return root.player.trackAlbumArtist;
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
                  text: (root.player && root.player.loopState === MprisLoopState.Track) ? "󰑘" : "󰑖"
                  font.family: t.mono
                  font.pixelSize: 15
                  color: (root.player && root.player.loopState !== MprisLoopState.None) ? t.accent : t.ink3
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
                  color: (root.player && root.player.loopState !== MprisLoopState.None) ? t.accent : t.ink2
                }
              }
            }
          }
        }
      }
    }
  }
}
