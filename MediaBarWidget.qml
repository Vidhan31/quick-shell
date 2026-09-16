// MediaBarWidget.qml — Compact top bar widget for current media status.
import QtQuick
import Quickshell
import Quickshell.Services.Mpris

Item {
  id: root

  readonly property string monoFont: "JetBrainsMono Nerd Font Mono"

  readonly property var playerList: (Mpris.players && Mpris.players.values) ? Mpris.players.values : []

  function getBestPlayer(): var {
    if (playerList.length === 0) return null;
    for (let i = 0; i < playerList.length; i++) {
      if (playerList[i].playbackState === MprisPlaybackState.Playing) return playerList[i];
    }
    for (let i = 0; i < playerList.length; i++) {
      if (playerList[i].playbackState === MprisPlaybackState.Paused) return playerList[i];
    }
    return playerList[0];
  }

  readonly property var activePlayer: getBestPlayer()
  readonly property bool hasPlayer: activePlayer !== null
  readonly property bool isPlaying: activePlayer ? (activePlayer.playbackState === MprisPlaybackState.Playing) : false

  readonly property string title: activePlayer ? (activePlayer.trackTitle || activePlayer.identity || "Media") : "Media"
  readonly property string artist: {
    if (!activePlayer) return "";
    if (activePlayer.trackArtist) return activePlayer.trackArtist;
    if (activePlayer.trackArtists && activePlayer.trackArtists.length > 0) return activePlayer.trackArtists.join(", ");
    return "";
  }

  implicitWidth: contentRow.width
  implicitHeight: 20
  width: implicitWidth
  height: implicitHeight

  Row {
    id: contentRow
    spacing: 6
    anchors.verticalCenter: parent.verticalCenter

    // Mini animated visualizer when playing
    Row {
      id: eqRow
      spacing: 2
      anchors.verticalCenter: parent.verticalCenter
      visible: root.isPlaying

      Repeater {
        model: 3
        Rectangle {
          id: eqBar
          required property int index
          width: 2
          radius: 1
          color: "#a6e3a1" // Green accent

          SequentialAnimation on height {
            running: root.isPlaying
            loops: Animation.Infinite
            NumberAnimation {
              from: index === 1 ? 5 : (index === 0 ? 11 : 8)
              to: index === 1 ? 13 : (index === 0 ? 4 : 12)
              duration: index === 1 ? 300 : (index === 0 ? 420 : 360)
              easing.type: Easing.InOutQuad
            }
            NumberAnimation {
              from: index === 1 ? 13 : (index === 0 ? 4 : 12)
              to: index === 1 ? 5 : (index === 0 ? 11 : 8)
              duration: index === 1 ? 300 : (index === 0 ? 420 : 360)
              easing.type: Easing.InOutQuad
            }
          }
        }
      }
    }

    // Static icon when paused or idle
    Text {
      visible: !root.isPlaying
      anchors.verticalCenter: parent.verticalCenter
      text: root.hasPlayer ? "󰏤" : "󰝚"
      font.family: root.monoFont
      font.pixelSize: 13
      color: root.hasPlayer ? "#fab387" : "#a6adc8"
    }

    // Track Title / Artist text
    Text {
      id: labelText
      anchors.verticalCenter: parent.verticalCenter
      text: {
        if (!root.hasPlayer) return "Media";
        if (root.artist) return root.title + " • " + root.artist;
        return root.title;
      }
      font.family: root.monoFont
      font.pixelSize: 12
      font.bold: root.isPlaying
      color: root.isPlaying ? "#ffffff" : "#cdd6f4"
      elide: Text.ElideRight
      width: Math.min(implicitWidth, 160)
    }
  }
}
