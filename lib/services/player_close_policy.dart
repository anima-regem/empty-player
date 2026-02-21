enum PlayerCloseAction { close, minimize, enterPip }

class PlayerClosePolicy {
  static PlayerCloseAction resolve({
    required bool isPlaying,
    required bool pipOnCloseEnabled,
    required bool pipSupported,
  }) {
    if (!isPlaying) {
      return PlayerCloseAction.close;
    }

    if (pipOnCloseEnabled && pipSupported) {
      return PlayerCloseAction.enterPip;
    }

    return PlayerCloseAction.minimize;
  }
}
