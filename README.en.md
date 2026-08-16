# DeepSeek Harness — One-Click Installer for Windows

[**中文**](README.md) | **English**

---

> **100% open source**: every line of this installer is a plain-text script (`.cmd` / `.mjs`) — nothing compiled, nothing hidden. Open any file and read it end to end to see exactly what it does before running it.

A one-click installer for [DeepSeek Harness](https://github.com/deepseek-ai/deepseek-harness), the official open-source framework from DeepSeek AI.

## Usage

**Install:** Double-click `install-dsh.cmd` and wait for it to finish. Everything is automatic: dependency check → download official source → install & build → create a desktop shortcut.

**Launch:** After installation, double-click the **DeepSeek Harness** icon on your desktop and the browser opens the UI automatically.

> Want to see what it will do first? Run `install-dsh.cmd --dry-run` (preview only, makes no changes).

## From Install to Use — Just Three Steps

The screenshots below are from a real install I did on my own machine — not demo images.

**1. Double-click `install-dsh.cmd`, wait for it to finish — you're done when you see INSTALL SUCCESS**

![Install success](docs/screenshots/install-success.png)

**2. A DeepSeek Harness icon appears on your desktop**

![Desktop icon](docs/screenshots/desktop-icon.png)

**3. Double-click the icon — it starts the server, then opens http://127.0.0.1:3080 in your browser, ready to use dsh**

![Launch server](docs/screenshots/launch-server.png)

No extra software to install, no command line required — double-click, wait, double-click again. That's all it takes.

## Highlights

- **Script-based installation**: all logic lives in plain-text scripts (`.cmd` / `.mjs`), not compiled binaries
- **Fully open source**: every line in this repo can be read and audited — no hidden content
- **Zero prerequisites**: if git / Node.js is missing, self-contained copies are downloaded automatically — nothing is installed into the system; delete the folder to uninstall
- **No admin required**: no registry changes, no system PATH modification, no system services
- **Uninstall**: delete the install directory (default `%USERPROFILE%\deepseek-harness`) and the desktop icon — done

## License

[MIT](LICENSE)

---

*DeepSeek Harness is an open-source project by DeepSeek AI. This installer is a community script and is not affiliated with DeepSeek officially.*
