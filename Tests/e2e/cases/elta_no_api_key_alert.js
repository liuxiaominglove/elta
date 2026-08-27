function run(argv) {
  var shotDir = argv[0] || 'shots';
  var windowz = argv[1];

  var providers = ['deepseek', 'qwen'];
  var keychainService = 'com.elta.snaptranslate';

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
      try {
        var sts = wins[i].staticTexts;
        for (var j = 0; j < sts.length; j++) {
          lines.push('  staticText[' + j + ']=' + sts[j].name());
        }
      } catch (e) {}
      try {
        var btns = wins[i].buttons;
        for (var k = 0; k < btns.length; k++) {
          lines.push('  button[' + k + ']=' + btns[k].name());
        }
      } catch (e) {}
    }
    return lines.join('\n');
  }

  function clickEltaButton(name) {
    var proc = SE.processes['ELTA'];
    if (!proc.exists()) { return false; }
    var wins = proc.windows;
    for (var i = 0; i < wins.length; i++) {
      try {
        var btns = wins[i].buttons;
        for (var k = 0; k < btns.length; k++) {
          if (btns[k].name() === name) { btns[k].click(); return true; }
        }
      } catch (e) {}
    }
    return false;
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
    if (keyExists(originalProvider)) {
      var target = null;
      for (var i = 0; i < providers.length; i++) {
        if (!keyExists(providers[i])) { target = providers[i]; break; }
      }
      assert(target !== null, 'both providers have keys — cannot test "no key" path');
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

    // ELTA 启动时会自动弹设置窗口，此处不关闭它（关闭窗口在 hybrid 配置下不稳定）。
    // 在点菜单触发之前让 TextEdit 有选中文本并 frontmost；
    // 否则 ELTA 启动时的 activate 会抢走焦点，导致划词读不到选中文本。
    selectTextInTextEdit('This is a test sentence for translation.');

    statusItem.click();
    assert(
      waitUntil(function () { return statusItem.menus.length > 0; }, 3000),
      'ELTA menu did not open'
    );
    assert(
      clickMenuLabel(statusItem.menus[0], '📝 划词翻译'),
      '划词翻译 menu item not found'
    );

    shot(shotDir + '/elta_no_key_alert.png');

    assert(
      waitUntil(function () { return eltaHasStaticText('未配置 API Key'); }, 8000),
      '「未配置 API Key」alert not found\n--- ELTA UI ---\n' + dumpEltaUI()
    );

    assert(
      clickEltaButton('打开偏好设置'),
      '「打开偏好设置」button not found\n--- ELTA UI ---\n' + dumpEltaUI()
    );
    assert(
      waitUntil(function () { return !eltaHasStaticText('未配置 API Key'); }, 8000),
      '「未配置 API Key」alert did not dismiss after clicking 打开偏好设置\n--- ELTA UI ---\n' + dumpEltaUI()
    );

    sleep(1);
    assert(
      !eltaHasStaticText('翻译失败'),
      '点「打开偏好设置」后不应再弹「翻译失败」\n--- ELTA UI ---\n' + dumpEltaUI()
    );

    return 'PASS: no-key alert shown + 打开偏好设置 dismisses alert';
  } finally {
    runShell('/usr/bin/killall', ['ELTA']);
    runShell('/usr/bin/killall', ['TextEdit']);
    if (switched) {
      writeProvider(originalProvider);
    }
  }
}
