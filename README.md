# DeepSeek Harness — Windows 一键安装器

为 [DeepSeek Harness](https://github.com/deepseek-ai/deepseek-harness)（DeepSeek 官方开源框架）提供的一键安装脚本。

## 使用

**安装：** 双击 `install-dsh.cmd`，等待完成即可。全程自动：检测依赖 → 下载官方源码 → 安装构建 → 创建桌面快捷方式。

**启动：** 安装完成后，双击桌面 **DeepSeek Harness** 图标，浏览器会自动打开使用界面。

> 想先看它会执行什么？运行 `install-dsh.cmd --dry-run`（只预览，不做任何改动）。

## 说明

- **零预装**：缺 git / Node.js 会自动下载自包含副本，不装系统、删目录即卸载
- **无需管理员**：不修改注册表、不改系统 PATH、不装系统服务
- **卸载**：删除安装目录（默认 `%USERPROFILE%\deepseek-harness`）和桌面图标即可
- 所有脚本均为纯文本，可逐行阅读审计

## 许可

[MIT](LICENSE)

---

*DeepSeek Harness 是 DeepSeek AI 的开源项目。本安装器是社区脚本，与 DeepSeek 官方无隶属关系。*
