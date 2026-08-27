function run(argv) {
  var shotDir = argv[0] || 'shots';
  var windowz = argv[1];

  var logPath = ObjC.unwrap($.NSHomeDirectory()) + '/Library/Logs/elta.log';

  function eltaHasWindowTitle(title) {
    var proc = SE.processes['ELTA'];
    if (!proc.exists()) { return false; }
    var wins = proc.windows;
    for (var i = 0; i < wins.length; i++) {
      try {
        if (wins[i].name() === title) { return true; }
      } catch (e) {}
    }
    return false;
  }

  function dumpEltaUI() {
    var proc = SE.processes['ELTA'];
    if (!proc.exists()) { return 'ELTA not running'; }
    var lines = [];
    var wins = proc.windows;
    for (var i = 0; i < wins.length; i++) {
      lines.push('win[' + i + '] name=' + wins[i].name());
    }
    return lines.join('\n');
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

  var baseLines = fileLineCount(logPath);
  assert(
    clickMenuLabel(statusItem.menus[0], '📷 截图翻译'),
    '截图翻译 menu item not found'
  );

  // 等截图遮罩出现
  sleep(1.5);

  // 框选屏幕中央大部分区域（CGEvent 左上原点；Y 会被截图引擎按 Cocoa 左下原点翻转）
  dragMouse(150, 150, 1550, 950);

  // 核心断言：翻译结果弹窗出现（OCR ~2s + 真实翻译 5–15s，超时 60s）
  assert(
    waitUntil(function () { return eltaHasWindowTitle('翻译结果 — ELTA'); }, 60000),
    '翻译结果弹窗未出现\n--- ELTA UI ---\n' + dumpEltaUI()
  );
  shot(shotDir + '/elta_screenshot_golden_path.png');

  // 路径证明：日志增量含「流水线完成」+「OCR 识别」
  var newLog = fileTailSince(logPath, baseLines);
  assert(
    newLog.indexOf('OCR: 识别到') >= 0 && newLog.indexOf('流水线完成') >= 0,
    '日志未出现 OCR 识别 + 流水线完成\n--- new log ---\n' + newLog
  );

  runShell('/usr/bin/killall', ['ELTA']);

  return 'PASS: 截图翻译金路径走通（弹窗出现 + OCR + 流水线完成）';
}
