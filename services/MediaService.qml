pragma ComponentBehavior: Bound
// MediaService.qml — Media state adapter over official Quickshell.Services.Mpris.
//
// Replaces the custom C++ Quickshell.Plugins.Media.MediaManager. The official
// Mpris singleton only exposes `players`; this adapter owns the active-player
// policy (manual selection > playing > paused > first) and the QML convenience
// props (title/artist/length/position/progress/formatters/capabilities) so
// widgets/popups keep a stable API.
//
// Position tracking: official docs state `position` does not notify on its own.
// While `positionTracking` is true (popup visible) and something is playing, a
// FrameAnimation re-emits `positionChanged()` so progress bars stay smooth.
import QtQuick
import Quickshell.Services.Mpris

Item {
  id: root

  // Manual override from the source switcher. Auto-cleared when it leaves the list.
  property var manualPlayer: null
  // Enabled by the popup while visible; bar widget leaves it off.
  property bool positionTracking: false

  readonly property var playerList: Mpris.players.values
  readonly property var players: Mpris.players.values
  readonly property int playerCount: playerList.length

  readonly property var activePlayer: {
    const list = root.playerList;
    if (root.manualPlayer && list.indexOf(root.manualPlayer) !== -1) {
      return root.manualPlayer;
    }
    for (let i = 0; i < list.length; i++) {
      if (list[i] && list[i].playbackState === MprisPlaybackState.Playing) {
        return list[i];
      }
    }
    for (let j = 0; j < list.length; j++) {
      if (list[j] && list[j].playbackState === MprisPlaybackState.Paused) {
        return list[j];
      }
    }
    return list.length > 0 ? list[0] : null;
  }
  readonly property var player: root.activePlayer
  readonly property bool hasPlayer: root.activePlayer !== null
  readonly property bool isPlaying: root.activePlayer ? root.activePlayer.isPlaying : false

  readonly property string title: {
    if (!root.activePlayer) {
      return "Media";
    }
    const t = root.activePlayer.trackTitle;
    if (t) {
      return t;
    }
    return root.activePlayer.identity || "Media";
  }
  readonly property string artist: {
    if (!root.activePlayer) {
      return "";
    }
    return root.activePlayer.trackArtist || root.activePlayer.trackAlbumArtist || "";
  }
  readonly property string trackTitle: root.title
  readonly property string trackArtist: root.artist
  readonly property string trackAlbum: root.activePlayer ? (root.activePlayer.trackAlbum || "") : ""
  readonly property string trackArtUrl: root.formatArtUrl(root.activePlayer ? root.activePlayer.trackArtUrl : "")
  readonly property real trackLength: (root.activePlayer && root.activePlayer.lengthSupported) ? root.activePlayer.length : 0
  readonly property real length: root.trackLength
  readonly property real trackPos: (root.activePlayer && root.activePlayer.positionSupported) ? root.activePlayer.position : 0
  readonly property real position: root.trackPos
  readonly property real progress: root.trackLength > 0 ? Math.min(1, Math.max(0, root.trackPos / root.trackLength)) : 0
  readonly property string formattedPosition: root.formatSeconds(root.trackPos)
  readonly property string formattedLength: root.trackLength > 0 ? root.formatSeconds(root.trackLength) : "--:--"

  readonly property bool canControl: root.activePlayer ? root.activePlayer.canControl : false
  readonly property bool canTogglePlaying: root.activePlayer ? root.activePlayer.canTogglePlaying : false
  readonly property bool canGoNext: root.activePlayer ? root.activePlayer.canGoNext : false
  readonly property bool canGoPrevious: root.activePlayer ? root.activePlayer.canGoPrevious : false
  readonly property bool canSeek: root.activePlayer ? root.activePlayer.canSeek : false
  readonly property bool shuffle: root.activePlayer ? root.activePlayer.shuffle : false
  readonly property bool shuffleSupported: root.activePlayer ? root.activePlayer.shuffleSupported : false
  readonly property int loopState: root.activePlayer ? root.activePlayer.loopState : MprisLoopState.None
  readonly property bool loopSupported: root.activePlayer ? root.activePlayer.loopSupported : false

  // Position refresh: re-emit the official signal every frame while tracked+playing.
  FrameAnimation {
    running: root.positionTracking && root.isPlaying && root.activePlayer !== null
    onTriggered: {
      if (root.activePlayer) {
        root.activePlayer.positionChanged();
      }
    }
  }

  onPlayerListChanged: {
    if (root.manualPlayer && root.playerList.indexOf(root.manualPlayer) === -1) {
      root.manualPlayer = null;
    }
  }

  function formatSeconds(sec: double): string {
    if (!isFinite(sec) || sec <= 0) {
      return "0:00";
    }
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
    if (p && p.identity) {
      return p.identity;
    }
    return "Player";
  }

  function selectPlayer(p: var): void {
    root.manualPlayer = p;
  }

  function setTrackPos(posSec: double): void {
    if (root.activePlayer && root.activePlayer.canSeek && root.activePlayer.positionSupported) {
      root.activePlayer.position = posSec;
    }
  }

  function playPause(): void {
    root.togglePlaying();
  }

  function togglePlaying(): void {
    if (root.activePlayer && root.canTogglePlaying) {
      root.activePlayer.togglePlaying();
    }
  }

  function play(): void {
    if (root.activePlayer && root.activePlayer.canPlay) {
      root.activePlayer.play();
    }
  }

  function pause(): void {
    if (root.activePlayer && root.activePlayer.canPause) {
      root.activePlayer.pause();
    }
  }

  function next(): void {
    if (root.activePlayer && root.canGoNext) {
      root.activePlayer.next();
    }
  }

  function previous(): void {
    if (root.activePlayer && root.canGoPrevious) {
      root.activePlayer.previous();
    }
  }

  function stop(): void {
    if (root.activePlayer && root.activePlayer.canControl) {
      root.activePlayer.stop();
    }
  }

  function seek(offsetSec: double): void {
    if (root.activePlayer && root.canSeek) {
      root.activePlayer.seek(offsetSec);
    }
  }

  function setShuffle(enable: bool): void {
    if (root.activePlayer && root.shuffleSupported && root.canControl) {
      root.activePlayer.shuffle = enable;
    }
  }

  function setLoopState(state: int): void {
    if (root.activePlayer && root.loopSupported && root.canControl) {
      root.activePlayer.loopState = state;
    }
  }

  function cycleLoop(): void {
    if (!root.activePlayer || !root.loopSupported || !root.canControl) {
      return;
    }
    if (root.loopState === MprisLoopState.None) {
      root.activePlayer.loopState = MprisLoopState.Playlist;
    } else if (root.loopState === MprisLoopState.Playlist) {
      root.activePlayer.loopState = MprisLoopState.Track;
    } else {
      root.activePlayer.loopState = MprisLoopState.None;
    }
  }

  function loopWord(): string {
    if (root.loopState === MprisLoopState.Track) {
      return "Track";
    }
    if (root.loopState === MprisLoopState.Playlist) {
      return "Playlist";
    }
    return "Off";
  }
}
