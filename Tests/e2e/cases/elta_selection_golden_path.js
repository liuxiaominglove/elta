function run(argv) {
  var shotDir = argv[0] || 'shots';
  var windowz = argv[1];

  var providers = ['deepseek', 'qwen'];
  var keychainService = 'com.elta.snaptranslate';
  var logPath = ObjC.unwrap($.NSHomeDirectory()) + '/Library/Logs/elta.log';
  var testText = 'This is a golden path test sentence.';

  function keyExists(provider) {
    var code = runShell('/bin/bash', ['-c',
      'security find-generic-password -s "' + keychainService + '" -a "snaptranslate.apikey.' + provider + '" -w >/dev/null 2>&1'
    ]);
    return code === 0;
  }

  function readProvider() {
    return runShellCapture('/usr/bin/defaults', ['read', 'com.elta.app', 'snaptranslate.apiProvider']).trim();
  }

  function writeProvider(p) {
    runShell('/usr/bin/defaults', ['write', 'com.elta.app', 'snaptranslate.apiProvider', p]);
  }

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

  var originalProvider = readProvider() || 'deepseek';
  var switched = false;

  try {
    if (!keyExists(originalProvider)) {
      var target = null;
      for (var i = 0; i < providers.length; i++) {
        if (keyExists(providers[i])) { target = providers[i]; break; }
      }
      assert(target !== null, 'no provider has a valid API key — configure one first');
      writeProvider(target);
      switched = true;
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

    // 选中文本必须在 ELTA 启动后（ELTA 启动会抢焦点）
    selectTextInTextEdit(testText);

    statusItem.click();
    assert(
      waitUntil(function () { return statusItem.menus.length > 0; }, 3000),
      'ELTA menu did not open'
    );

    var baseLines = fileLineCount(logPath);
    assert(
      clickMenuLabel(statusItem.menus[0], '📝 划词翻译'),
      '划词翻译 menu item not found'
    );

    // 核心断言：结果弹窗出现（真实翻译 5–15s，超时 60s）
    assert(
      waitUntil(function () { return eltaHasWindowTitle('翻译结果 — ELTA'); }, 60000),
      '翻译结果弹窗未出现\n--- ELTA UI ---\n' + dumpEltaUI()
    );
    shot(shotDir + '/elta_golden_path.png');

    // 路径证明：日志增量含「划词翻译流水线完成」（.missingKey 分支无此日志）
    var newLog = fileTailSince(logPath, baseLines);
    assert(
      newLog.indexOf('划词翻译流水线完成') >= 0,
      '日志未出现「划词翻译流水线完成」— 未走 success 分支\n--- new log ---\n' + newLog
    );

    return 'PASS: 划词翻译金路径走通（弹窗出现 + 流水线完成）';
  } finally {
    runShell('/usr/bin/killall', ['ELTA']);
    runShell('/usr/bin/killall', ['TextEdit']);
    if (switched) {
      writeProvider(originalProvider);
    }
  }
}
