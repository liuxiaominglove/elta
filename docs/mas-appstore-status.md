# ELTA Mac App Store 迁移状态

- 日期：2026-10-24
- 阶段：Phase 1 spike 完成并验证；分发前置条件未完成
- 代码基线：`0c55872`（已推送到 `origin/main`）
- 关键决策：`docs/adr/0005-mas-appstore-company-account-and-brand.md`
- 当前测试版：`/Applications/ELTA.app`（个人 Apple Development 签名 + sandbox；正式 MAS 必须换成公司 Apple Distribution + Mac App Store profile）
- 旧版备份：`~/Library/Application Support/ELTA-old-backup/*.zip`

## 当前状态

### 已完成并验证

- MAS 构建：`./build-mas.sh` 生成 Universal Binary（x86_64 + arm64），codesign 验证通过，sandbox entitlements 正确。
- 非 MAS 回归：`./run_tests.sh` 343/343 通过。
- 静态检查：MAS 二进制不含 AX / CGEventTap / CGEventPost；不含更新检查端点。
- Services：`Info-MAS.plist` 增加 `NSRequiredContext` 空字典后，“用 ELTA 翻译”出现在 Services 菜单；调用日志确认 `Services 收到文本`。
- 状态栏菜单：修复 `.accessory` 模式下 `NSMenuItem.target` 为 nil 的问题，菜单“截图翻译/划词翻译”可用。
- 剪贴板划词：菜单与全局 `⌃⇧T` 均可读取剪贴板并翻译；实测 API 返回 210 字符。
- 截图翻译：TCC 已授权 `com.elta.app.mas`；实测截图/裁剪 1500x460、OCR 识别 5 块文本、API 返回 460 字符、结果面板显示、ESC 关闭。
- Keychain：MAS 使用独立 service `com.elta.snaptranslate.mas`。
- 安全/商店策略：MAS 版关闭更新检查与匿名统计；代码中无 AX/CGEventTap 依赖。
- 旧版处理：原 `/Applications/ELTA.app` 已卸载并备份为 zip；当前 `/Applications/ELTA.app` 为 MAS 测试版。

### 当前阻塞

- 公司 Apple Developer Organization 账号尚未申请/批准；无 Team ID。
- 无公司 Apple Distribution 证书、无 Mac Installer Distribution 证书、无 Mac App Store provisioning profile。
- 无 App Store Connect App 记录；`com.elta.app.mas` 在公司账号下的可用性未确认。
- 公司无 D-U-N-S（待确认；公司 2026-10-09 成立，可能尚未被收录，是当前关键路径）。
- 域名 `autoelta.com` 为个人注册，ICP 备案为个人；无公司域名邮箱；个人到公司的 IP 授权尚未签署。
- ELTA 商标正式检索/申请尚未完成；中国区 App Store 暂无同名 App，但海外存在 ELTA TV（ELTA d.o.o.）等使用。
- App Review 所需的 BYOK 临时测试 Key 尚未准备。

### 未开始/待确认

- 公司 Apple ID、公司邮箱、公司网站主体信息。
- Free Apps Agreement；App Store Connect 隐私/支持 URL、截图、分类、版权。
- `build-mas.sh` 显式指定公司 Team/证书/profile；`.pkg` 打包与上传 TestFlight。
- 公司签名后 TCC/Keychain 会变化：测试机需重新授权屏幕录制、重新填 API Key。

## 关键决策摘要

1. MAS 使用公司 Organization 账号；官网直发版暂留个人账号，后续再评估迁移；不使用 Enterprise Program。App Store 卖家名显示公司法定名称，App 名仍为 ELTA。
2. 品牌继续用 ELTA；以公司名义做正式商标检索并申请（重点第 9/42 类，翻译服务看第 41 类）；注册前用 `™`。
3. MAS bundle ID 继续用 `com.elta.app.mas`；公司账号下新建 App Store 记录；原版未上架，不做 App Transfer。
4. `autoelta.com` 短期保留个人注册，签署个人到公司的书面 IP 授权；开公司邮箱转发；MAS 上线后再转域名/ICP。
5. 先免费；收费或 IAP 以后再加。
6. 官网直发与 MAS 两套渠道、证书、Team、profile 分开，不混用。

## 下一步

### A. 现在（关键路径，不依赖代码）

1. 查公司是否已有 D-U-N-S；没有就官方免费申请。准备营业执照、公司中英文名、地址、电话、公司邮箱、网站、经营范围。
2. 准备公司 Apple ID（建议公司邮箱 + 双重认证）。
3. 申请 Apple Developer Program Organization 账号（$99/年），等 Apple 审核。
4. 做 ELTA 商标正式检索（CNIPA + WIPO/USPTO/EUIPO，9/42/41 类）；以公司名义申请。
5. 签个人到公司的 IP 授权/转让（品牌、域名、网站内容；代码为 ISC 许可，公司可使用/分发）。
6. 开 `admin@autoelta.com` / `support@autoelta.com` 转发；更新网站隐私页/页脚公司主体。
7. 接受 Free Apps Agreement（免费模式）。

### B. 公司账号批准后

1. 创建 Apple Distribution 证书；如打 `.pkg`，创建 Mac Installer Distribution 证书。
2. 注册 App ID `com.elta.app.mas`；创建 Mac App Store provisioning profile。
3. App Store Connect 新建 macOS App：ELTA、bundle ID、SKU、分类、隐私/支持 URL、免费价格。
4. 改 `build-mas.sh`：显式 `MAS_SIGN_IDENTITY`（公司 Apple Distribution）、`MAS_TEAM_ID`、`MAS_PROVISIONING_PROFILE`；不再自动挑证书。
5. 重新构建，验证 `codesign -dvv`、内嵌 profile、sandbox entitlements；打 `.pkg` 并签名。
6. Transporter/Xcode 上传，TestFlight 内部测试。
7. 在公司签名版本上重新授权屏幕录制、重新填 API Key。

### C. 提交审核前

1. 准备 Review Notes：BYOK（用户自备 DeepSeek Key）；提供临时测试 Key（不要写进 App）；说明截图/Services 为用户主动触发、无后台录制。
2. 隐私政策与 App Privacy 一致：选中文本发送给 DeepSeek；本地 OCR；Keychain 存 Key；无统计/追踪。
3. 准备 macOS 截图、描述、关键词、支持 URL、版权（公司名）。
4. 确认 App Store 名称 ELTA 可用；备选 `ELTA 翻译` / `ELTA Translator`。

### D. MAS 上线后

1. 收集 TestFlight 反馈，修复后提交审核/发布。
2. 迁移域名/ICP 到公司（单独窗口，不与首发耦合）。
3. 评估官网直发版是否迁移到公司 Developer ID（重签、更新、用户重新授权）。

## 个人到公司 IP 授权清单

- 双方：个人（当前开发者账号持有人）→ 阜城县笑语电子商务有限公司。
- 资产：ELTA 名称/logo、`autoelta.com` 域名、网站内容、App Store 支持/隐私页面。
- 代码：仓库为 ISC 许可，公司可直接使用/分发；如需独占/转让，另行约定。
- 范围：全球、永久/不可撤销，用于 App Store、官网、营销、支持。
- 对价：免费授权 / 作价入股 / 转让，先让律师/税务确认。
- 交付：签署并盖章/签字的授权或转让协议；附件列明资产；域名注册商/WHOIS；商标申请号；代码仓库 LICENSE。
- 注意：以上是清单，不构成法律意见；最终由律师/税务确认。

## 公司邮箱/隐私页修改清单

- 开通 `admin@autoelta.com`（Apple/D-U-N-S 用）和 `support@autoelta.com`（用户/App Store 支持用），可先做邮件转发。
- 当前 `website/privacy.html` 的联系方式是个人 QQ 邮箱，页脚没有公司主体；需要替换。
- 更新 `website/privacy.html`：公司法定名称、公司邮箱、DeepSeek 处理选中文本、本地 OCR、Keychain、无统计/追踪、最后更新日期。
- 更新网站页脚：公司名称、联系邮箱、版权。
- App Store Connect：支持 URL `https://autoelta.com`，隐私政策 URL `https://autoelta.com/privacy`。
- 后续把 `Info-MAS.plist` 的 `NSHumanReadableCopyright` 更新为公司名。
- ICP：短期保留个人备案；MAS 上线后再迁域名/变更备案。具体问腾讯云/备案接入商。

## 验证记录

- `./run_tests.sh`：Total 343 / Passed 343。
- `./build-mas.sh`：Universal Binary；codesign valid；sandbox + network.client entitlements。
- `nm -u build/mas/ELTA.app/Contents/MacOS/ELTA`：无 AX / CGEventTap / CGEventPost 符号。
- TCC：`com.elta.app.mas` 屏幕录制 `auth_value=2`。
- 日志：Services `len=17`；剪贴板 API 210 字符；截图 1500x460、OCR 5 块、API 460 字符；ESC 关闭成功。
- Git：`0c55872 feat(mas): 新增沙盒版 Mac App Store 构建与 Services/剪贴板入口`。

## 不要做

- 不要用 Apple Developer Enterprise Program 上 App Store。
- 不要混用个人/公司证书、Team、profile。
- 不要在未确认 ICP 的情况下转域名，不要和 MAS 首发同时做。
- 不要在商标注册前使用 `®`。
- 不要把真实 API Key 写进 App 或 Review Notes；只用临时测试 Key。
- 不要在账号/App ID 未就绪前创建 App Store 记录。
- 不要在多张证书环境下依赖脚本自动挑签名身份。
