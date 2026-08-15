/// What the window X / tray Sair should do.
enum WindowCloseAction {
  minimizeTaskbar,
  hideToTray,
  confirmQuit,
  confirmStopSession,
  quitNow,
}

/// ponytail: one decision for WM_CLOSE + tray Sair. Native still asks Flutter.
WindowCloseAction decideWindowClose({
  required String reason,
  required bool sessionOn,
  required bool closeMinimizes,
  required bool minimizeToTray,
}) {
  if (reason == 'exit') {
    return sessionOn
        ? WindowCloseAction.confirmStopSession
        : WindowCloseAction.quitNow;
  }
  if (closeMinimizes) {
    return minimizeToTray
        ? WindowCloseAction.hideToTray
        : WindowCloseAction.minimizeTaskbar;
  }
  return sessionOn
      ? WindowCloseAction.confirmStopSession
      : WindowCloseAction.confirmQuit;
}
