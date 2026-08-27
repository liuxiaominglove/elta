function run(argv) {
  var shotDir = argv[0] || 'shots';
  var windowz = argv[1];

  var logPath = ObjC.unwrap($.NSHomeDirectory()) + '/Library/Logs/elta.log';

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

  function triggerScreenshotTranslate(statusItem) {
    statusItem.click();
    // 等待菜单真正打开（而非硬编码 sleep），避免竞态导致误判「触发失败」
    if (!waitUntil(function () { return statusItem.menus.length > 0; }, 3000)) { return false; }
    for (var m = 0; m < statusItem.menus.length; m++) {
      if (clickMenuLabel(statusItem.menus[m], '📷 截图翻译')) { return true; }
    }
    return false;
  }

  runShell('/usr/bin/tccutil', ['reset', 'ScreenCapture', 'com.elta.app']);
  sleep(0.5);

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

  // 第一次触发：primeAndAbort（TCC 弹窗 + 静默中止）
  var base1 = fileLineCount(logPath);
  assert(triggerScreenshotTranslate(statusItem), '第一次触发截图翻译失败');
  sleep(2);
  var log1 = fileTailSince(logPath, base1);
  assert(
    log1.indexOf('屏幕录制权限: 未授权，TCC 弹窗已触发') >= 0,
    '首次未触发 TCC 弹窗（primeAndAbort）\n--- new log ---\n' + log1
  );
  // 关闭系统「屏幕录制」TCC 弹窗（modal 会挡住菜单栏，阻塞第二次触发）
  try { SE.keystroke(String.fromCharCode(27)); } catch (e) {}
  sleep(0.5);

  // 第二次触发：guideAndAbort（静默中止，无引导 alert）
  var base2 = fileLineCount(logPath);
  assert(triggerScreenshotTranslate(statusItem), '第二次触发截图翻译失败');
  sleep(2);
  var log2 = fileTailSince(logPath, base2);
  assert(
    log2.indexOf('屏幕录制权限: 仍未授权，静默中止') >= 0,
    '二次未静默中止（guideAndAbort）\n--- new log ---\n' + log2
  );

  return 'PASS: 截图翻译权限拒绝降级（primeAndAbort + guideAndAbort）';
}
