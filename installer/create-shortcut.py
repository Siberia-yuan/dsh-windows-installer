#!/usr/bin/env python3
"""Create the dsh.ico (multi-size, via Pillow) and a desktop shortcut
(pywin32) pointing at <repo>/start-dsh.cmd with the icon.

Usage: python create-shortcut.py <repoDir>
Requires: pip install pywin32 pillow   (optional shortcut step)
"""
import os
import sys

REPO = os.path.abspath(sys.argv[1] if len(sys.argv) > 1 else os.getcwd())
ICO = os.path.join(REPO, "dsh.ico")
PNG = os.path.join(REPO, "dsh-icon-256.png")

# 1) multi-size .ico from the 256px PNG
if os.path.exists(PNG):
    try:
        from PIL import Image
        Image.open(PNG).convert("RGBA").save(
            ICO, format="ICO",
            sizes=[(16, 16), (24, 24), (32, 32), (48, 48), (64, 64), (128, 128), (256, 256)],
        )
        print("dsh.ico written:", ICO)
    except Exception as e:
        print("WARN: could not build .ico:", e)
        ICO = os.path.join(REPO, "dsh.ico") if os.path.exists(os.path.join(REPO, "dsh.ico")) else ""

# 2) desktop shortcut
try:
    import win32com.client
    shell = win32com.client.Dispatch("WScript.Shell")
    desktop = shell.SpecialFolders("Desktop")
    lnk = os.path.join(desktop, "DeepSeek Harness.lnk")
    sc = shell.CreateShortCut(lnk)
    sc.TargetPath = os.path.join(REPO, "start-dsh.cmd")
    sc.WorkingDirectory = REPO
    if ICO:
        sc.IconLocation = f"{ICO},0"
    sc.Description = "DeepSeek Harness Web UI (http://127.0.0.1:3080)"
    sc.Save()
    print("shortcut written:", lnk)
except Exception as e:
    print("WARN: could not create shortcut:", e)
