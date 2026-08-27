function run(argv) {
  var shotDir = argv[0] || 'shots';
  var windowz = argv[1];

  var marker = 'ELTA_E2E_PASTEBOARD_MARKER_8f3a2c';
  var logPath = ObjC.unwrap($.NSHomeDirectory()) + '/Library/Logs/elta.log';

  function setPasteboard(text) {
    runShell('/bin/bash', ['-c', 'printf "%s" "$1" | /usr/bin/pbcopy', 'x', text]);
  }

  function getPasteboard() {
    return runShellCapture('/usr/bin/pbpaste', []);
  }

  function findMenuBarItem(appName, name) {
    var proc = SE.processes[appName];
    for (var i = 0; i < proc.menuBars.length; i++) {
      var items = proc.menuBars[i].menuBarItems;
      for (var j = 0; j < items.length; j++) {
        if (items[j].name() === name) { return items[j]; }
      }
    }
    return null;
  }

  function clickMenuLabel(menu, label) {
    for (var k = 0; k < menu.menuItems.length; k++) {
      if (menu.menuItems[k].name() === label) {
        menu.menuItems[k].click();
        return true;
      }
    }
    return false;
  }

  runShell('/usr/bin/killall', ['ELTA']);
  sleep(0.5);

  setPasteboard(marker);

  launch('ELTA');
  assert(waitForProcess('ELTA', 8000), 'ELTA did not launch');

  var statusItem = null;
  assert(
    waitUntil(function () {
      statusItem = findMenuBarItem('ELTA', '📖');
      return statusItem !== null;
    }, 8000),
    'ELTA status item 📖 not found'
  );
  statusItem.click();
  assert(
    waitUntil(function () { return statusItem.menus.length > 0; }, 3000),
    'ELTA menu did not open'
  );

  // 触发划词翻译前：把 frontmost 切到 Finder（桌面无选中文本），
  // 使 Accessibility 读不到文本、确定性回退 Cmd+C。
  runShell('/usr/bin/open', ['-a', 'Finder']);
  sleep(0.5);

  var baseLines = fileLineCount(logPath);
  assert(
    clickMenuLabel(statusItem.menus[0], '📝 划词翻译'),
    '划词翻译 menu item not found'
  );

  sleep(3);

  var after = getPasteboard();
  shot(shotDir + '/elta_pasteboard.png');

  var newLog = fileTailSince(logPath, baseLines);
  var restored = newLog.indexOf('剪贴板已恢复') >= 0;

  runShell('/usr/bin/killall', ['ELTA']);

  assert(
    after.trim() === marker,
    'pasteboard NOT restored: expected ' + marker + ', got ' + JSON.stringify(after)
  );
  assert(
    restored,
    'log "剪贴板已恢复" not found in NEW log lines — Cmd+C fallback was not exercised\n--- new log ---\n' + newLog
  );

  return 'PASS: pasteboard restored + Cmd+C fallback path confirmed';
}
