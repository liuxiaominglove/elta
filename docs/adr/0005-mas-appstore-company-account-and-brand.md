# 5. Mac App Store 采用公司 Organization 账号与 ELTA 品牌

- 状态：已接受
- 日期：2026-10-24

## 上下文

ELTA 已有官网直发版，原 Mac 版使用个人开发者账号。Mac App Store（MAS）沙盒版 Phase 1 spike 已完成并验证：Services、剪贴板划词、截图/OCR/API/结果面板、ESC、TCC、Keychain 均可工作。

公司主体为阜城县笑语电子商务有限公司（有限责任公司，经营范围含软件开发、软件销售，成立于 2026-10-09）。公司 Apple Developer 账号尚未申请，无 Team ID、Apple Distribution 证书、Mac App Store provisioning profile。原 Mac 版未上架过 App Store。官网 `autoelta.com` 为个人注册，ICP 备案为个人；无公司域名邮箱。品牌继续使用 ELTA。

## 决策

### 本质

这是产品法律主体、品牌/IP 归属和分发渠道的决策，不是单纯的证书或技术选择。App Store 的卖家是法律主体；品牌、域名、代码是不同 IP；MAS 与官网直发是两条独立渠道。

### 最佳实践

- 卖家账号与产品法律拥有者一致：MAS 用公司 Organization 账号。
- 品牌、域名、邮箱、商标尽量由公司拥有；短期不一致用书面授权，长期迁移。
- Bundle ID 首次上传前定好；MAS 与官网直发使用不同 bundle ID、证书和 Team。
- 长周期外部验证（D-U-N-S、Organization、商标）尽早启动，但不与首发强耦合。
- 先免费验证分发和审核；收费后再补协议、税务和银行信息。

### 方案

1. MAS 使用公司 Organization 账号；官网直发版暂留个人账号，后续再评估迁移。
2. 品牌继续用 ELTA；以公司名义做正式商标检索并申请（重点第 9/42 类，翻译服务看第 41 类）；注册前用 `™`，不用 `®`。
3. MAS bundle ID 继续用 `com.elta.app.mas`；公司账号下新建 App Store 记录；原版未上架，不做 App Transfer。
4. `autoelta.com` 短期保留个人注册，签署个人到公司的书面 IP 授权；开 `admin@autoelta.com` / `support@autoelta.com` 转发；MAS 上线后再转域名和 ICP。
5. 先免费；收费或 IAP 以后再加。
6. 两套渠道分开：官网直发用个人 Developer ID；MAS 用公司 Apple Distribution 证书和 Mac App Store profile。
7. 不采用 Apple Developer Enterprise Program，它不能上 App Store。

## 后果

正面：卖家、品牌、渠道边界清晰；MAS 可独立推进；官网直发不被阻塞；短期授权避免域名/ICP 迁移影响首发。

负面：短期存在个人持有域名/ICP、公司作为卖家的权属不一致；需要书面授权和后续迁移；公司账号、D-U-N-S、商标都有外部等待时间。

## 被拒备选

- 用个人账号发 MAS：卖家显示个人，与公司产品和品牌不一致；后续 App Transfer 有流程和审核成本。
- 用 Enterprise Program：只能内部分发，不能上 App Store。
- 立即把域名/ICP 转公司：可能触发备案变更和停机，与首发耦合风险高。
- 先收费：需要 Paid Apps Agreement、税务和银行信息，拖慢首发；先免费验证更稳。
- 另起公司域名/品牌：ELTA 已有官网和中国区 App Store 名称可用性信号，重命名成本高；保留 ELTA 并以公司名义申请商标更合适。

## 依据

- 公司执照：有限责任公司（自然人投资或控股），经营范围含软件开发、软件销售；符合 Organization 法人实体要求，最终以 Apple/D&B 审核为准。
- 原 Mac 版未上架 App Store；中国区 App Store 未搜到同名 App；用户初步检索未发现 ELTA 软件类注册。公开检索仅作初步信号，正式以 CNIPA/WIPO/USPTO/EUIPO 或代理检索为准。
- 现有证书为个人 Apple Development / Developer ID Application；无 Apple Distribution；唯一 provisioning profile 为 iOS Team，不能用于 MAS。
