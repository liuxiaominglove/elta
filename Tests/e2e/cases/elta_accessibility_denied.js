function run(argv) {
  var shotDir = argv[0] || 'shots';
  var windowz = argv[1];

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
    // 等待菜单真正打开（而非硬编码 sleep），避免竞态导致误判「触发失败」
    if (!waitUntil(function () { return statusItem.menus.length > 0; }, 3000)) { return false; }
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

  // 未授权触发划词 → 直接弹「需要辅助功能权限」引导框（每次未授权都提示）
  assert(triggerSelectionTranslate(statusItem), '触发划词翻译失败');
  assert(
    waitUntil(function () { return eltaHasStaticText('需要辅助功能权限'); }, 8000),
    '引导 alert「需要辅助功能权限」未出现\n--- ELTA UI ---\n' + dumpEltaUI()
  );

  runShell('/usr/bin/killall', ['ELTA']);

  return 'PASS: 划词翻译未授权时直接弹引导框';
}
