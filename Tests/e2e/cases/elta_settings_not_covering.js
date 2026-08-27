function run(argv) {
  var shotDir = argv[0] || 'shots';
  var windowz = argv[1];

  var eltaOwner = 'ELTA';
  var calcOwner = '计算器';

  function layer0IndexOf(owner) {
    var wins = windowList(windowz);
    for (var i = 0; i < wins.length; i++) {
      if (wins[i].owner === owner && wins[i].layer === 0) {
        return i;
      }
    }
    return -1;
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
  runShell('/usr/bin/killall', ['Calculator']);
  // 等待进程真正退出，避免 launch 撞上未退完的旧实例（hung/慢退出/权限问题）
  waitUntil(function () { return !processExists('ELTA') && !processExists('Calculator'); }, 5000);

  try {
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
  assert(
    clickMenuLabel(statusItem.menus[0], '⚙️ 偏好设置...'),
    'preferences menu item not found'
  );

  assert(
    waitUntil(function () { return layer0IndexOf(eltaOwner) >= 0; }, 8000),
    'ELTA settings window did not appear on screen'
  );

  launch('Calculator');
  assert(
    waitUntil(function () { return layer0IndexOf(calcOwner) >= 0; }, 8000),
    'Calculator window did not appear on screen'
  );

  shot(shotDir + '/elta_settings.png');

  var eltaIdx = layer0IndexOf(eltaOwner);
  var calcIdx = layer0IndexOf(calcOwner);

  if (calcIdx < 0 || eltaIdx < 0) {
    fail('window disappeared before assertion\n' + dumpWindows(windowz));
  }

  assert(
    calcIdx < eltaIdx,
    'ELTA settings covers Calculator (eltaIdx=' + eltaIdx +
    ', calcIdx=' + calcIdx + ')\n' + dumpWindows(windowz)
  );

  return 'PASS: settings does not cover Calculator';
  } finally {
    runShell('/usr/bin/killall', ['ELTA']);
    runShell('/usr/bin/killall', ['Calculator']);
  }
}

function dumpWindows(windowz) {
  var wins = windowList(windowz);
  var lines = [];
  for (var i = 0; i < wins.length; i++) {
    lines.push(i + '\t' + wins[i].owner + '\t' + wins[i].layer);
  }
  return lines.join('\n');
}
