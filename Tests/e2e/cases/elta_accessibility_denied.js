function run(argv) {
  var shotDir = argv[0] || 'shots';
  var windowz = argv[1];

  var logPath = ObjC.unwrap($.NSHomeDirectory()) + '/Library/Logs/elta.log';

  function eltaHasStaticText(text) {
    var proc = SE.processes['ELTA'];
    if (!proc.exists()) { return false; }
    var wins = proc.windows;
    for (var i = 0; i < wins.length; i++) {
      try {
        var sts = wins[i].staticTexts;
        for (var j = 0; j < sts.length; j++) {
          if (sts[j].name() === text) { return true; }
        }
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
      try {
        var sts = wins[i].staticTexts;
        for (var j = 0; j < sts.length; j++) {
          lines.push('  staticText[' + j + ']=' + sts[j].name());
        }
      } catch (e) {}
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

  function triggerSelectionTranslate(statusItem) {
    statusItem.click();
    sleep(0.4);
    for (var m = 0; m < statusItem.menus.length; m++) {
      if (clickMenuLabel(statusItem.menus[m], '📝 划词翻译')) { return true; }
    }
    return false;
  }

  runShell('/usr/bin/tccutil', ['reset', 'Accessibility', 'com.elta.app']);
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
  assert(triggerSelectionTranslate(statusItem), '第一次触发划词翻译失败');
  sleep(2);
  var log1 = fileTailSince(logPath, base1);
  assert(
    log1.indexOf('Accessibility 权限: 未授权，TCC 弹窗已触发') >= 0,
    '首次未触发 TCC 弹窗（primeAndAbort）\n--- new log ---\n' + log1
  );

  // 第二次触发：guideAndAbort（弹「需要辅助功能权限」引导 alert）
  assert(triggerSelectionTranslate(statusItem), '第二次触发划词翻译失败');
  assert(
    waitUntil(function () { return eltaHasStaticText('需要辅助功能权限'); }, 8000),
    '引导 alert「需要辅助功能权限」未出现\n--- ELTA UI ---\n' + dumpEltaUI()
  );

  runShell('/usr/bin/killall', ['ELTA']);

  return 'PASS: 划词翻译权限拒绝降级（primeAndAbort + guideAndAbort 引导）';
}
