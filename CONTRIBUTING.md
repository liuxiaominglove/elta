# 贡献指南

感谢你对 ELTA 的关注！无论是反馈 Bug、提出功能建议，还是贡献代码，都欢迎。

## 反馈 Bug 或提功能建议

请在 [Issues](https://github.com/liuxiaominglove/elta/issues) 中提交，尽量包含以下信息：

- **Bug 反馈**：macOS 版本、ELTA 版本、操作步骤、预期结果与实际结果
- **功能建议**：描述你希望 ELTA 支持的功能，以及使用场景

## 提交代码

1. **Fork** 本仓库
2. 创建你的功能分支：
   ```bash
   git checkout -b feature/你的功能名
   ```
3. 提交你的修改：
   ```bash
   git commit -m '添加了xxx功能'
   ```
4. 推送到分支：
   ```bash
   git push origin feature/你的功能名
   ```
5. 创建一个 **Pull Request**

## 开发环境

- macOS 13.0+
- Xcode 15+
- Swift 5.9+

## 本地编译

```bash
# 编译 macOS 客户端
./build.sh

# 前端开发，直接用浏览器打开 website/ 下的 HTML 文件即可
```

## 代码规范

- Swift 代码保持与现有风格一致
- 前端保持纯 HTML/CSS/JS，不引入第三方框架
- 提交信息用中文或英文均可
