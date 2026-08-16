# DeepSeek Harness — Windows 一键安装器（透明 · 可审计）

本目录提供了一套**源码完全可见**的 Windows 一键安装流程，用于从源码安装
[deepseek-harness](https://github.com/deepseek-ai/deepseek-harness)（dsh）。

**核心原则：让安装过程可以被信任——先看后装。**

---

## 1. 安全模型（先读这个）

| 承诺 | 说明 |
|---|---|
| **源码可见** | 所有脚本都是普通文本文件，可以用记事本/编辑器逐行查看：`install-dsh.cmd`、`patch-windows.mjs`、`link-workspace.mjs`、`make-icon.mjs`、`create-shortcut.py`。没有编译好的黑盒 exe。 |
| **可预览** | 运行 `install-dsh.cmd --dry-run` 只打印每一步将要执行什么，**不执行任何操作**。 |
| **写入范围受限** | 安装器只在你指定的安装目录（默认 `%USERPROFILE%\deepseek-harness`）内写文件。**不修改注册表、不修改系统 PATH、不安装系统服务、不写系统目录**。 |
| **前置依赖自动解决** | **本地已有且满足要求（git 任意版本 / node ≥ 22.19）→ 直接使用，绝不下载**；仅在缺失或版本不足时，安装器才自动下载**自包含副本**到 `installer\tools\`（git = PortableGit 便携版，node = 官方 win-x64 zip），不装系统、用完可整个删除；`--force-download` 可强制重新下载 |
| **桌面快捷方式（默认必做）** | 安装结束会自动在桌面创建带 DeepSeek 图标的快捷方式：图标由仓库内 sharp 生成（无需 Python），快捷方式用 Windows 内置的 PowerShell 创建（无需任何第三方依赖）；仅在 PowerShell 异常时回退到 Python。不想要就加 `--no-shortcut`。 |

> 换一种说法：安装器做的一切 = **在安装目录里克隆仓库 + 修改仓库内几个配置文件 + 跑 pnpm 安装/构建**。修改的每个文件、每一处改动，都可以在 `patch-windows.mjs` 里逐条看到原因。

---

## 2. 系统要求

- Windows 10/11（x64）
- **无需预装 Git / Node.js** —— 缺失或版本不足时，安装器会自动下载自包含副本（见「安全模型」）
  - 若系统已装有 git / node（node ≥ 22.19），安装器会优先使用
- 可选：Python 3（**仅当** PowerShell 创建桌面快捷方式失败时用于回退；正常情况不需要）
- 网络：可访问 nodejs.org 与 GitHub（GitHub 走 `ghfast.top` 国内镜像）

---

## 3. 快速开始

```bat
:: 预览（强烈建议先跑这个，什么都不改）
install-dsh.cmd --dry-run

:: 正式安装（默认装到 %USERPROFILE%\deepseek-harness）
install-dsh.cmd

:: 指定目录安装
install-dsh.cmd -d D:\apps\dsh

:: 不建桌面快捷方式
install-dsh.cmd --no-shortcut

:: 强制重新下载自包含 git/Node（默认只在缺失/版本不足时自动下载）
install-dsh.cmd --force-download
```

安装完成后：
- 启动：双击安装目录里的 `start-dsh.cmd` —— **智能判断**：服务器已在运行则直接打开网页；未运行则启动服务器并自动打开浏览器。也可命令行运行 `pnpm dsh web`
- 访问：http://127.0.0.1:3080
- 停止：关闭运行 `start-dsh.cmd` 的窗口（或 Ctrl+C）

---

## 4. 安装器每一步做什么、为什么

| 步骤 | 做什么 | 为什么 |
|---|---|---|
| 0 前置依赖 | 检测 git、Node.js（≥ 22.19）；缺失/不足则自动下载自包含版本到 `installer\tools\` | 零预装也能一键装完；Node 版本过低会不满足仓库 engines 要求 |
| 1 安装目录 | 确定/创建安装目录 | 所有写入都局限在这里 |
| 2 克隆源码 | `git clone`（默认走 ghfast.top 镜像，失败回退 GitHub 直连） | 从官方仓库获取源码；已存在则 `git pull` 更新 |
| 3 Windows 补丁 | 运行 `patch-windows.mjs` | 解决 Windows + pnpm 11 的几个已知问题（见下表） |
| 4 安装依赖 | `pnpm install` | 下载全部依赖（npm 镜像用 npmmirror） |
| 5 链接 workspace | 运行 `link-workspace.mjs` | hoisted 模式下 pnpm 不创建 workspace 符号链接，用 junction（免管理员）补上 |
| 6 构建 | `pnpm run build:lib` + vite 构建前端 | 产出可运行的 lib 与 Web UI（dist/） |
| 7 启动器 | 生成 `start-dsh.cmd` + `open-browser.vbs` | 双击即启动，就绪后自动打开浏览器 |
| 8 桌面快捷方式 | 用 Node(sharp) 生成 `dsh.ico`，用 Windows 内置 PowerShell 创建桌面 `DeepSeek Harness.lnk` | **安装流程的固定环节**（默认必做，`--no-shortcut` 可跳过）；无需 Python，失败自动回退 |
| 9 汇总 | 打印安装位置与启动方式 | 收尾 |

### `patch-windows.mjs` 修改了什么（逐条可审计）

| 修改 | 原因 |
|---|---|
| `.npmrc` → `registry=https://registry.npmmirror.com` | 国内网络下 npm 官方源慢/不可达 |
| `pnpm-workspace.yaml` → `nodeLinker: hoisted` | pnpm 隔离 linker 在本项目 Windows 上顶层链接失败（typescript/@types/node 缺失 → tsc 报 TS2688）；hoisted 用扁平结构避开 |
| `pnpm-workspace.yaml` → `verifyDepsBeforeRun: false` | 防止 `pnpm run` 前自动重装清掉手动创建的 workspace junction |
| `pnpm-workspace.yaml` → `allowBuilds.koffi: false` | koffi 的 cnoke 源码构建在 Git Bash(MSYSTEM) 下误选 MinGW 生成器而失败；改用其预编译二进制 |
| `pnpm-workspace.yaml` → `allowBuilds.subprocess-local: false` | 其 postinstall（macOS 专用 spawn-helper 修复）在 Windows 上会抛错并中断整个 install |
| 根 `package.json` postinstall → no-op | lefthook git hooks 仅开发用，且其 Windows 二进制缺失时会导致安装失败 |
| `packages/subprocess/subprocess-local/package.json` postinstall → no-op | 同上，见上一条 |

> 每条修改都对应真实踩过的坑。如果你想对比"补丁前/后"，在安装目录运行
> `git diff` 即可看到所有本地改动。

---

## 5. 如何审计（3 步）

1. **看源码**：打开 `installer\` 目录，用任意文本编辑器阅读所有脚本（共 5 个，都很短）。
2. **跑预览**：`install-dsh.cmd --dry-run`，确认每一步都符合你的预期。
3. **看补丁**：装完后在安装目录执行 `git diff`，核对 `patch-windows.mjs` 声称的改动是否属实。

---

## 6. 常见问题

- **`git clone` 失败 / 网络被墙**：安装器会自动从镜像回退到直连。仍失败可手动
  `git clone https://ghfast.top/https://github.com/deepseek-ai/deepseek-harness.git`。
- **`pnpm install` 中途失败**：多为网络波动，重跑一次即可（安装器幂等，可反复执行）。
- **构建报 TS2307 / 模块找不到**：说明 workspace junction 没建好，重跑
  `node installer\link-workspace.mjs <安装目录>`。
- **koffi / postinstall 报错**：确认 `patch-windows.mjs` 已运行（`git diff` 可见改动）。
- **如何卸载**：删除安装目录（和桌面快捷方式）即可，无残留（不写注册表/系统目录）。

---

## 7. 文件清单

| 文件 | 作用 |
|---|---|
| `install-dsh.cmd` | 一键安装主脚本（入口） |
| `patch-windows.mjs` | 应用 Windows 补丁（支持 `--review` 只预览） |
| `link-workspace.mjs` | 为 workspace 包创建 junction（免管理员） |
| `make-icon.mjs` | 用仓库内 sharp 生成多尺寸 `dsh.ico`（无需 Python） |
| `create-shortcut.py` | 回退用：生成 .ico + 桌面快捷方式（仅当 PowerShell 失败时，需 pywin32/pillow） |
| `open-browser.vbs` | 轮询端口就绪后自动打开浏览器 |
| `INSTALL.md` | 本文档 |
