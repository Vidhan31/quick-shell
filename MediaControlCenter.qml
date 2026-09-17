// MediaControlCenter.qml — Nice modern minimalist media control center for Quickshell.
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Plugins.Media

Item {
  id: root

  readonly property string monoFont: "JetBrainsMono Nerd Font Mono"

  MediaManager {
    id: media
  }

  // Width & height of the control center card
  implicitWidth: 360
  implicitHeight: card.height
  width: implicitWidth
  height: implicitHeight

  // Manually selected player, if user clicked a tab
  property alias manualPlayer: media.manualPlayer

  // All available players from native MPRIS manager
  readonly property var playerList: media.playerList
  readonly property int playerCount: media.playerCount

  readonly property var player: media.activePlayer
  readonly property bool hasPlayer: media.hasPlayer

  // Track playback status
  readonly property bool isPlaying: media.isPlaying

  // Seeking state
  property bool isSeeking: false
  property real seekTarget: 0

  // Track length & position in seconds
  readonly property real trackLength: media.trackLength
  readonly property real trackPos: isSeeking ? seekTarget : media.trackPos

  // Format artwork URL
  function formatArtUrl(url: string): string {
    return url || "";
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

  // Main Card
  Rectangle {
    id: card
    width: root.implicitWidth
    height: contentCol.height + 28
    radius: 16
    color: "#1e1e2e" // Catppuccin Mocha Base
    border.color: "#313244" // Surface0
    border.width: 1

    Behavior on height { NumberAnimation { duration: 160; easing.type: Easing.OutQuad } }

    Column {
      id: contentCol
      anchors {
        top: parent.top
        left: parent.left
        right: parent.right
        topMargin: 14
        leftMargin: 16
        rightMargin: 16
      }
      spacing: 12

      // Top Bar: Header & Player Tabs
      RowLayout {
        width: parent.width

        Row {
          spacing: 6
          Layout.alignment: Qt.AlignVCenter

          // Glowing status dot
          Rectangle {
            width: 7
            height: 7
            radius: 3.5
            anchors.verticalCenter: parent.verticalCenter
            color: root.isPlaying ? "#a6e3a1" : (root.hasPlayer ? "#fab387" : "#585b70")

            Behavior on color { ColorAnimation { duration: 150 } }
          }

          Text {
            text: "MEDIA CENTER"
            font.family: root.monoFont
            font.pixelSize: 11
            font.bold: true
            color: "#a6adc8"
            anchors.verticalCenter: parent.verticalCenter
          }
        }

        Item { Layout.fillWidth: true }

        // Multiple players pills if > 1
        Row {
          spacing: 4
          visible: root.playerCount > 1
          Layout.alignment: Qt.AlignVCenter

          Repeater {
            model: root.playerList

            Rectangle {
              required property var modelData
              readonly property bool isCurrent: root.player === modelData
              width: tabRow.width + 10
              height: 20
              radius: 5
              color: isCurrent ? "#45475a" : (tabMouse.containsMouse ? "#313244" : "transparent")
              border.color: isCurrent ? "#89b4fa" : "transparent"
              border.width: 1

              Behavior on color { ColorAnimation { duration: 100 } }
              Behavior on border.color { ColorAnimation { duration: 100 } }

              Row {
                id: tabRow
                anchors.centerIn: parent
                spacing: 4

                // Mini indicator if playing
                Rectangle {
                  width: 4
                  height: 4
                  radius: 2
                  anchors.verticalCenter: parent.verticalCenter
                  color: "#a6e3a1"
                  visible: modelData.isPlaying
                }

                Text {
                  text: (modelData.identity || "Player").slice(0, 10)
                  font.family: root.monoFont
                  font.pixelSize: 10
                  font.bold: isCurrent
                  color: isCurrent ? "#ffffff" : "#a6adc8"
                  anchors.verticalCenter: parent.verticalCenter
                }
              }

              MouseArea {
                id: tabMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.manualPlayer = modelData
              }
            }
          }
        }
      }

      // STATE A: Media is Active
      Column {
        width: parent.width
        spacing: 12
        visible: root.hasPlayer

        // Hero: Album Art + Track Details
        Rectangle {
          width: parent.width
          height: 96
          radius: 12
          color: "#181825" // Mantle
          border.color: "#313244"
          border.width: 1

          RowLayout {
            anchors.fill: parent
            anchors.margins: 8
            spacing: 12

            // Album Artwork Container
            Rectangle {
              Layout.preferredWidth: 80
              Layout.preferredHeight: 80
              radius: 10
              color: "#313244"
              clip: true

              // Image for Track Artwork
              Image {
                id: artImage
                anchors.fill: parent
                source: root.player ? root.formatArtUrl(root.player.trackArtUrl) : ""
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                visible: status === Image.Ready
              }

              // Fallback Artwork when no artUrl or loading fails
              Item {
                anchors.fill: parent
                visible: artImage.status !== Image.Ready

                Rectangle {
                  anchors.fill: parent
                  gradient: Gradient {
                    GradientStop { position: 0.0; color: "#2c2f42" }
                    GradientStop { position: 1.0; color: "#181825" }
                  }
                }

                Text {
                  anchors.centerIn: parent
                  text: "󰝚"
                  font.family: root.monoFont
                  font.pixelSize: 32
                  color: "#89b4fa"
                  opacity: 0.8
                }
              }
            }

            // Track Details Column
            ColumnLayout {
              Layout.fillWidth: true
              Layout.alignment: Qt.AlignVCenter
              spacing: 3

              // Player Identity Badge
              Rectangle {
                Layout.preferredHeight: 16
                Layout.preferredWidth: playerBadgeText.width + 10
                radius: 4
                color: "#313244"

                Text {
                  id: playerBadgeText
                  anchors.centerIn: parent
                  text: (root.player ? (root.player.identity || "MPRIS") : "").toUpperCase()
                  font.family: root.monoFont
                  font.pixelSize: 9
                  font.bold: true
                  color: "#89b4fa"
                }
              }

              // Track Title
              Text {
                Layout.fillWidth: true
                text: root.player ? (root.player.trackTitle || "No Title") : "No Media"
                font.family: root.monoFont
                font.pixelSize: 14
                font.bold: true
                color: "#ffffff"
                elide: Text.ElideRight
                maximumLineCount: 1
              }

              // Artist
              Text {
                Layout.fillWidth: true
                text: {
                  if (!root.player) return "Unknown Artist";
                  if (root.player.trackArtist) return root.player.trackArtist;
                  if (root.player.trackArtists && root.player.trackArtists.length > 0) return root.player.trackArtists.join(", ");
                  return "Unknown Artist";
                }
                font.family: root.monoFont
                font.pixelSize: 12
                color: "#bac2de"
                elide: Text.ElideRight
                maximumLineCount: 1
              }

              // Album
              Text {
                Layout.fillWidth: true
                visible: text.length > 0
                text: root.player && root.player.trackAlbum ? root.player.trackAlbum : ""
                font.family: root.monoFont
                font.pixelSize: 10
                color: "#6c7086"
                elide: Text.ElideRight
                maximumLineCount: 1
              }
            }
          }
        }

        // Progress Bar & Duration
        Column {
          width: parent.width
          spacing: 4

          // Clickable / Draggable Seek Bar
          Item {
            id: seekHit
            width: parent.width
            height: 16

            Rectangle {
              id: seekTrack
              anchors {
                left: parent.left
                right: parent.right
                verticalCenter: parent.verticalCenter
              }
              height: seekMouse.containsMouse || root.isSeeking ? 6 : 4
              radius: height / 2
              color: "#313244"

              Behavior on height { NumberAnimation { duration: 100 } }

              // Filled progress
              Rectangle {
                id: seekFill
                anchors {
                  left: parent.left
                  top: parent.top
                  bottom: parent.bottom
                }
                width: root.trackLength > 0 ? Math.min(parent.width, Math.max(0, parent.width * (root.trackPos / root.trackLength))) : 0
                radius: parent.radius
                gradient: Gradient {
                  orientation: Gradient.Horizontal
                  GradientStop { position: 0.0; color: "#89b4fa" }
                  GradientStop { position: 1.0; color: "#cba6f7" }
                }
              }

              // Scrubber Thumb
              Rectangle {
                id: seekThumb
                width: 12
                height: 12
                radius: 6
                color: "#ffffff"
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

          // Timestamps Row
          RowLayout {
            width: parent.width

            Text {
              text: root.formatSeconds(root.trackPos)
              font.family: root.monoFont
              font.pixelSize: 11
              color: "#a6adc8"
            }

            Item { Layout.fillWidth: true }

            Text {
              text: root.trackLength > 0 ? root.formatSeconds(root.trackLength) : "--:--"
              font.family: root.monoFont
              font.pixelSize: 11
              color: "#6c7086"
            }
          }
        }

        // Modern Controls Row
        RowLayout {
          width: parent.width
          spacing: 0

          // Shuffle Button
          Item {
            Layout.preferredWidth: 36
            Layout.preferredHeight: 36

            Rectangle {
              anchors.fill: parent
              radius: 18
              color: shuffleMouse.containsMouse ? "#313244" : "transparent"

              Text {
                anchors.centerIn: parent
                text: "󰒝"
                font.family: root.monoFont
                font.pixelSize: 17
                color: (root.player && root.player.shuffle) ? "#89b4fa" : "#6c7086"
                opacity: (root.player && root.player.shuffleSupported) ? 1.0 : 0.3
              }

              MouseArea {
                id: shuffleMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: (root.player && root.player.shuffleSupported) ? Qt.PointingHandCursor : Qt.ArrowCursor
                onClicked: {
                  if (root.player && root.player.shuffleSupported && root.player.canControl) {
                    root.player.shuffle = !root.player.shuffle;
                  }
                }
              }
            }
          }

          Item { Layout.fillWidth: true }

          // Previous Button
          Item {
            Layout.preferredWidth: 42
            Layout.preferredHeight: 42

            Rectangle {
              anchors.fill: parent
              radius: 21
              color: prevMouse.containsMouse ? "#313244" : "transparent"
              scale: prevMouse.pressed ? 0.92 : (prevMouse.containsMouse ? 1.05 : 1.0)
              Behavior on scale { NumberAnimation { duration: 90 } }

              Text {
                anchors.centerIn: parent
                text: "󰒮"
                font.family: root.monoFont
                font.pixelSize: 22
                color: (root.player && root.player.canGoPrevious) ? "#cdd6f4" : "#45475a"
              }

              MouseArea {
                id: prevMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: (root.player && root.player.canGoPrevious) ? Qt.PointingHandCursor : Qt.ArrowCursor
                onClicked: {
                  if (root.player && root.player.canGoPrevious) {
                    root.player.previous();
                  }
                }
              }
            }
          }

          Item { Layout.preferredWidth: 8 }

          // Play / Pause Primary Button
          Item {
            Layout.preferredWidth: 50
            Layout.preferredHeight: 50

            Rectangle {
              id: playBtnBg
              anchors.fill: parent
              radius: 25
              color: playMouse.containsMouse ? "#b4befe" : "#89b4fa"
              scale: playMouse.pressed ? 0.92 : (playMouse.containsMouse ? 1.06 : 1.0)

              Behavior on color { ColorAnimation { duration: 120 } }
              Behavior on scale { NumberAnimation { duration: 90 } }

              Text {
                anchors.centerIn: parent
                // Visual centering offset for play icon triangle
                anchors.horizontalCenterOffset: root.isPlaying ? 0 : 2
                text: root.isPlaying ? "󰏤" : "󰐊"
                font.family: root.monoFont
                font.pixelSize: 24
                font.bold: true
                color: "#11111b"
              }

              MouseArea {
                id: playMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                  if (root.player && root.player.canTogglePlaying) {
                    root.player.togglePlaying();
                  }
                }
              }
            }
          }

          Item { Layout.preferredWidth: 8 }

          // Next Button
          Item {
            Layout.preferredWidth: 42
            Layout.preferredHeight: 42

            Rectangle {
              anchors.fill: parent
              radius: 21
              color: nextMouse.containsMouse ? "#313244" : "transparent"
              scale: nextMouse.pressed ? 0.92 : (nextMouse.containsMouse ? 1.05 : 1.0)
              Behavior on scale { NumberAnimation { duration: 90 } }

              Text {
                anchors.centerIn: parent
                text: "󰒭"
                font.family: root.monoFont
                font.pixelSize: 22
                color: (root.player && root.player.canGoNext) ? "#cdd6f4" : "#45475a"
              }

              MouseArea {
                id: nextMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: (root.player && root.player.canGoNext) ? Qt.PointingHandCursor : Qt.ArrowCursor
                onClicked: {
                  if (root.player && root.player.canGoNext) {
                    root.player.next();
                  }
                }
              }
            }
          }

          Item { Layout.fillWidth: true }

          // Loop / Repeat Button
          Item {
            Layout.preferredWidth: 36
            Layout.preferredHeight: 36

            Rectangle {
              anchors.fill: parent
              radius: 18
              color: loopMouse.containsMouse ? "#313244" : "transparent"

              Text {
                anchors.centerIn: parent
                text: (root.player && root.player.loopState === 1) ? "󰑘" : "󰑖"
                font.family: root.monoFont
                font.pixelSize: 17
                color: (root.player && root.player.loopState !== 0) ? "#89b4fa" : "#6c7086"
                opacity: (root.player && root.player.loopSupported) ? 1.0 : 0.3
              }

              MouseArea {
                id: loopMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: (root.player && root.player.loopSupported) ? Qt.PointingHandCursor : Qt.ArrowCursor
                onClicked: {
                  if (root.player && root.player.loopSupported && root.player.canControl) {
                    if (root.player.loopState === 0) {
                      root.player.loopState = 2; // Playlist
                    } else if (root.player.loopState === 2) {
                      root.player.loopState = 1; // Track
                    } else {
                      root.player.loopState = 0; // None
                    }
                  }
                }
              }
            }
          }
        }
      }

      // STATE B: Empty State (No Media Playing)
      Item {
        width: parent.width
        height: 120
        visible: !root.hasPlayer

        Rectangle {
          anchors.fill: parent
          radius: 12
          color: "#181825"
          border.color: "#313244"
          border.width: 1

          ColumnLayout {
            anchors.centerIn: parent
            spacing: 8

            // Floating icon circle
            Rectangle {
              Layout.alignment: Qt.AlignHCenter
              width: 44
              height: 44
              radius: 22
              color: "#313244"

              Text {
                anchors.centerIn: parent
                text: "󰝚"
                font.family: root.monoFont
                font.pixelSize: 22
                color: "#6c7086"
              }
            }

            Text {
              Layout.alignment: Qt.AlignHCenter
              text: "No Media Playing"
              font.family: root.monoFont
              font.pixelSize: 13
              font.bold: true
              color: "#cdd6f4"
            }

            Text {
              Layout.alignment: Qt.AlignHCenter
              text: "Play audio or video in your browser or app"
              font.family: root.monoFont
              font.pixelSize: 11
              color: "#6c7086"
            }
          }
        }
      }
    }
  }
}
