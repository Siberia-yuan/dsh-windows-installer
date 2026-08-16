# DeepSeek Harness — Windows 一键安装器

为 [DeepSeek Harness](https://github.com/deepseek-ai/deepseek-harness)（DeepSeek 官方开源框架）提供的一键安装脚本。

## 使用

**安装：** 双击 `install-dsh.cmd`，等待完成即可。全程自动：检测依赖 → 下载官方源码 → 安装构建 → 创建桌面快捷方式。

**启动：** 安装完成后，双击桌面 **DeepSeek Harness** 图标，浏览器会自动打开使用界面。

> 想先看它会执行什么？运行 `install-dsh.cmd --dry-run`（只预览，不做任何改动）。

## 首次运行提示（SmartScreen / 未知发布者）

从网上下载的未签名脚本，Windows 默认会弹出「来自没有验证的发行者」或「Windows 已保护你的电脑」——**这是对任何未签名脚本的常规提醒，不代表脚本有问题**（纯文本 `.cmd` 无法做代码签名，所有开源脚本都一样）。解除方式：

| 方式 | 操作 |
|---|---|
| 解除锁定（推荐） | 右键 `install-dsh.cmd` → **属性** → 勾选底部**「解除锁定」** → 确定 |
| 命令行解除 | 在脚本所在目录运行：`powershell -Command "Unblock-File .\install-dsh.cmd"` |
| 直接运行 | 点击提示窗的**「更多信息」** → **「仍要运行」** |

**校验文件完整性（可选）**：运行 `certutil -hashfile install-dsh.cmd SHA256`（或 `sha256sum install-dsh.cmd`），与仓库发布的校验和比对，一致即说明文件未被篡改。

## 说明

- **零预装**：缺 git / Node.js 会自动下载自包含副本，不装系统、删目录即卸载
- **无需管理员**：不修改注册表、不改系统 PATH、不装系统服务
- **卸载**：删除安装目录（默认 `%USERPROFILE%\deepseek-harness`）和桌面图标即可
- 所有脚本均为纯文本，可逐行阅读审计

## 许可

[MIT](LICENSE)

---

*DeepSeek Harness 是 DeepSeek AI 的开源项目。本安装器是社区脚本，与 DeepSeek 官方无隶属关系。*
