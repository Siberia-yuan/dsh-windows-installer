# DeepSeek Harness — Windows 一键安装器（纯脚本版）

## 这是什么

为 [DeepSeek Harness](https://github.com/deepseek-ai/deepseek-harness)（`dsh`，DeepSeek 官方开源的 agent harness 框架）
提供的一个 Windows 一键安装脚本集。它做的事情和你在命令行里手工操作完全一样，只是把步骤编排好了：

```
检测/准备前置依赖 → 克隆官方源码 → 打 Windows 兼容补丁 → 安装依赖
→ 构建 → 生成启动器 → 创建桌面快捷方式
```

安装完成后，桌面上会出现一个带 DeepSeek 鲸鱼图标的 **DeepSeek Harness** 快捷方式，双击即可使用。

## 为什么坚持"脚本"而不是"安装程序"

很多安装包是编译好的 `.exe`，用户无法看到里面做了什么——这恰恰是不信任的来源。
本项目坚持：

| 原则 | 说明 |
|---|---|
| **纯脚本** | 所有逻辑都是可读的文本文件，无一例外 |
| **逐行可审计** | 每个文件用记事本打开即可完整阅读；安装器引用的每个子脚本都能单独运行和验证 |
| **可预览** | 安装前运行 `install-dsh.cmd --dry-run`，会打印每一步将要执行什么，**不执行任何操作** |
| **可核对** | 安装后运行 `git diff`，即可看到安装器对目标仓库的每一处改动 |
| **写入受限** | 只在你指定的安装目录内写文件；**不修改注册表、不改系统 PATH、不装系统服务** |

> 换一种说法：**信任不是靠口头承诺，而是靠你亲手读完那几百行脚本。**

## 特性一览

- 🚀 **极致傻瓜化**：**单文件** `install-dsh.cmd`（仓库根，自包含），**双击即用**——所有逻辑（依赖下载、补丁、安装、构建、快捷方式）都内联在这个文件里，不依赖任何子脚本
- 🪄 **零预装**：系统缺 git / Node.js 时自动下载**自包含**副本（PortableGit + 官方 Node zip，不装系统，删目录即卸载）；本地已有且满足要求则直接使用、**绝不下载**
- 🖥️ **智能启动**：生成的启动器会自动判断——服务器已在运行则直接打开网页；未运行则启动服务器并自动打开浏览器，**不会重复启动**
- 🎯 **桌面快捷方式**：安装结束自动在桌面创建带 DeepSeek 图标的快捷方式（Windows 内置 PowerShell 创建，无需第三方依赖）
- 🔍 **预览模式**：`--dry-run` 先看后装
- 🔁 **幂等可重跑**：中途失败或想升级，重跑即可

## 快速开始

**方式一：单文件版（推荐，双击即用）**

```bat
:: 1. 预览（强烈建议，什么都不改）
install-dsh.cmd --dry-run

:: 2. 正式安装（默认装到 %USERPROFILE%\deepseek-harness，装完自动建桌面快捷方式）
install-dsh.cmd
```

**方式二：分体版（installer\ 目录，便于逐文件审计）**

```bat
:: 1. 预览
installer\install-dsh.cmd --dry-run

:: 2. 正式安装
installer\install-dsh.cmd

:: 3. 指定目录 / 跳过快捷方式 / 强制重下工具
installer\install-dsh.cmd -d D:\apps\dsh
installer\install-dsh.cmd --no-shortcut
installer\install-dsh.cmd --force-download
```

安装完成后：

- 双击桌面 **DeepSeek Harness** 快捷方式（或 `deepseek-harness\start-dsh.cmd`）
- 浏览器打开 http://127.0.0.1:3080
- 停止服务：关闭启动器的黑色窗口

## 目录结构

```
dsh-windows-installer/
├── README.md              ← 本文件
├── LICENSE                ← MIT 开源协议
├── dsh.ico                ← 桌面快捷方式图标（独立资源，官方鲸鱼 logo）
├── install-dsh.cmd        ← ★ 单文件版：双击即用，全部逻辑内联（推荐）
└── installer/             ← 分体版（逻辑等价，文件更小，便于逐文件审计）
    ├── install-dsh.cmd     ← 一键安装主脚本（入口）
    ├── patch-windows.mjs   ← 应用 Windows 兼容补丁（支持 --review 只预览）
    ├── link-workspace.mjs  ← 为 workspace 包创建 junction（免管理员）
    ├── make-icon.mjs       ← 用仓库内 sharp 生成多尺寸 dsh.ico
    ├── create-shortcut.py  ← 回退用：创建桌面快捷方式（仅 PowerShell 失败时）
    ├── open-browser.vbs    ← 轮询端口就绪后自动打开浏览器
    ├── INSTALL.md          ← 完整安装与安全审计文档（建议先读）
    └── index.html          ← 可视化安装向导（离线可用）
```

> 💡 **图标说明**：`dsh.ico` 是独立的资源文件（非内嵌）。单文件版安装器会自动检测旁边的 `dsh.ico` 并用于桌面快捷方式；如果只拷贝 `install-dsh.cmd` 而不带图标，快捷方式会使用系统默认图标，**安装功能不受任何影响**。

## 工作原理（安装器执行的步骤）

| 步骤 | 做什么 | 为什么 |
|---|---|---|
| 0 | 检测/准备 git、Node.js（缺失或版本不足自动下载自包含副本） | 零预装；Node ≥ 22.19 满足官方仓库 engines 要求 |
| 1 | 确定安装目录（默认 `%USERPROFILE%\deepseek-harness`） | 所有写入都局限在此，这是安全边界 |
| 2 | 克隆官方源码（默认走 `ghfast.top` 国内镜像，失败回退直连） | 安装的是**官方仓库**，不是修改版 |
| 3 | 运行 `patch-windows.mjs` 打兼容补丁 | 解决 Windows + pnpm 11 的已知问题（hoisted 链接、koffi 构建等） |
| 4 | `pnpm install` 安装依赖 | 使用 npmmirror 镜像加速 |
| 5 | 创建 workspace junction | pnpm hoisted 模式不自动建，用 junction（免管理员）补齐 |
| 6 | 构建（tsc + tsdown + vite） | 产出可运行的 lib 与 Web UI |
| 7 | 生成智能启动器 `start-dsh.cmd` | 已在运行→直接开网页；未运行→启动+开网页 |
| 8 | 创建桌面快捷方式 + 图标（固定环节） | 像普通桌面软件一样双击即用 |
| 9 | 打印安装位置与启动方式 | 收尾 |

## 安全模型（3 步审计）

1. **读代码**：用记事本打开 `installer\` 下所有脚本，都很短，逐行可读
2. **跑预览**：`install-dsh.cmd --dry-run`，确认每一步符合预期
3. **对改动**：安装后进入安装目录执行 `git diff`，核对补丁与文档描述一致

## 系统要求

- Windows 10/11（x64）
- **无需预装 git / Node.js**（缺失时安装器自动下载自包含副本）
- 可选：Python 3（仅当 PowerShell 创建快捷方式失败时用于回退）

## 与官方项目的关系

- 本仓库**不包含也不修改** DeepSeek Harness 的源代码
- 安装器从官方仓库 `github.com/deepseek-ai/deepseek-harness` 克隆源码
- 安装器只做"环境准备 + 兼容补丁 + 启动便利"，补丁的每一处改动都带原因注释，可在安装目录用 `git diff` 核对

## 常见问题

- **clone 失败 / 网络被墙？** 安装器默认走 `ghfast.top` 镜像，失败自动回退直连
- **`pnpm install` 失败？** 多为网络波动，重跑一次即可（安装器幂等）
- **构建报 TS2307？** workspace junction 未建好，重跑 `node link-workspace.mjs <安装目录>`
- **如何卸载？** 删除安装目录（和桌面快捷方式）即可，无残留

## 许可

[MIT](LICENSE) —— 完全开源，自由使用、修改、分发。

---

*DeepSeek Harness 是 DeepSeek AI 的开源项目，详见其官方仓库。本安装器是社区脚本，与 DeepSeek 官方无隶属关系。*
