import 'package:at_shield/engine/window_close.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('X minimizes by default, even with a live session', () {
    expect(
      decideWindowClose(
        reason: 'close',
        sessionOn: true,
        closeMinimizes: true,
        minimizeToTray: false,
      ),
      WindowCloseAction.minimizeTaskbar,
    );
    expect(
      decideWindowClose(
        reason: 'close',
        sessionOn: false,
        closeMinimizes: true,
        minimizeToTray: true,
      ),
      WindowCloseAction.hideToTray,
    );
  });

  test('X asks before quit when close-minimizes is off', () {
    expect(
      decideWindowClose(
        reason: 'close',
        sessionOn: false,
        closeMinimizes: false,
        minimizeToTray: false,
      ),
      WindowCloseAction.confirmQuit,
    );
    expect(
      decideWindowClose(
        reason: 'close',
        sessionOn: true,
        closeMinimizes: false,
        minimizeToTray: true,
      ),
      WindowCloseAction.confirmStopSession,
    );
  });

  test('tray Sair never minimizes', () {
    expect(
      decideWindowClose(
        reason: 'exit',
        sessionOn: false,
        closeMinimizes: true,
        minimizeToTray: true,
      ),
      WindowCloseAction.quitNow,
    );
    expect(
      decideWindowClose(
        reason: 'exit',
        sessionOn: true,
        closeMinimizes: true,
        minimizeToTray: true,
      ),
      WindowCloseAction.confirmStopSession,
    );
  });
}
