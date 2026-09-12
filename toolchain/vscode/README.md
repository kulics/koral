# Koral Language Support

这是一个最小化的 VS Code 语言扩展，只提供 Koral 的基础语法高亮。

## 功能

- `.koral` 文件识别
- 基础语法高亮（关键字、注释、字符串、数字、类型、函数名、操作符）
- 注释快捷键（`Ctrl+/` 行注释，`Shift+Alt+A` 块注释）
- 括号与引号自动配对
- 基础智能缩进（基于括号）
- 代码折叠标记（`// region` / `// endregion`）
- 声明块折叠（函数/类型等 `{ ... }` 代码块）

## 不包含

- LSP
- 自动补全
- 跳转定义/重命名/诊断

## 本地调试

1. 在 VS Code 打开本项目。
2. 按 `F5` 启动 Extension Development Host。
3. 在新窗口中打开任意 `.koral` 文件查看高亮效果。

## 打包与安装（VSIX）

1. 在项目根目录执行：`npm run package`
2. 生成文件：`koral-language-support-<version>.vsix`
3. 安装命令：`code --install-extension "toolchain/vscode/koral-language-support-<version>.vsix" --force`

## 识别验证

1. 新建或打开 `*.koral` 文件。
2. 查看 VS Code 右下角语言模式是否显示 `Koral`。
3. 若未生效，执行 `Developer: Reload Window` 后重试。

## 发布流程（最小）

1. 修改 `package.json` 中的 `version`（例如 `<old> -> <new>`）。
2. 执行：`npm run package`，确认生成对应版本的 `.vsix`。
3. 本地安装验证：`code --install-extension "<your-vsix-path>" --force`。
4. 如需发布到 Marketplace（已配置 publisher 与 token）：`npm run publish`。
