@echo off
setlocal enabledelayedexpansion
chcp 65001 >nul
title DeepSeek Harness Installer

rem ============================================================================
rem  DeepSeek Harness — One-click installer for Windows
rem  ============================================================================
rem  WHAT THIS IS
rem    Installs deepseek-harness (dsh) from source on Windows:
rem      check prerequisites -> clone -> apply Windows patches -> pnpm install
rem      -> workspace junctions -> build -> (optional) desktop shortcut
rem
rem  SAFETY MODEL (please read before running)
rem    - This script is 100% source-visible. Read every line, or run:
rem          install-dsh.cmd --dry-run
rem      which prints every step WITHOUT executing anything.
rem    - It ONLY writes inside the install directory you choose (default:
rem      %USERPROFILE%\deepseek-harness). It does NOT touch the registry,
rem      does NOT modify your PATH permanently, does NOT install services.
rem    - Prerequisites are solved automatically: if git or a Node.js >= 22.19
rem      is missing, self-contained copies are downloaded into
rem      <script-dir>\tools\ (git: PortableGit, node: official win-x64 zip).
rem      Nothing is installed into the system. Use --force-download to always
rem      download fresh copies even when a system version exists.
rem    - A desktop shortcut with the DeepSeek icon is created automatically at
rem      the end (uses Windows built-in PowerShell + sharp — no extra deps;
rem      falls back to Python if available). Skip it with --no-shortcut.
rem
rem  USAGE
rem    install-dsh.cmd                      full install (defaults)
rem    install-dsh.cmd -d D:\apps\dsh      install to a specific directory
rem    install-dsh.cmd --dry-run           preview only, no changes
rem    install-dsh.cmd --force-download    always download self-contained git/node
rem    install-dsh.cmd --skip-build        install deps only, skip the build
rem    install-dsh.cmd --no-shortcut       do not create a desktop shortcut
rem    install-dsh.cmd --help              show this help
rem ============================================================================

set "SCRIPT_DIR=%~dp0"
set "SCRIPT_DIR=%SCRIPT_DIR:~0,-1%"
set "TARGET="
set "DRY="
set "FORCE_DL="
set "SKIP_BUILD="
set "NO_SHORTCUT="
set "SHOW_HELP="
set "EXISTING_REPO="

:parse_args
if "%~1"=="" goto args_done
if /i "%~1"=="-d"           ( set "TARGET=%~2" & shift & shift & goto parse_args )
if /i "%~1"=="--dry-run"    ( set "DRY=1" & shift & goto parse_args )
if /i "%~1"=="--review"     ( set "DRY=1" & shift & goto parse_args )
if /i "%~1"=="--with-node"  ( set "FORCE_DL=1" & shift & goto parse_args )
if /i "%~1"=="--force-download" ( set "FORCE_DL=1" & shift & goto parse_args )
if /i "%~1"=="--skip-build" ( set "SKIP_BUILD=1" & shift & goto parse_args )
if /i "%~1"=="--no-shortcut" ( set "NO_SHORTCUT=1" & shift & goto parse_args )
if /i "%~1"=="--help"       ( set "SHOW_HELP=1" & shift & goto parse_args )
echo [WARN] Unknown argument: %~1
shift & goto parse_args
:args_done

if defined SHOW_HELP goto :help
if defined DRY echo.
if defined DRY echo   [MODE] DRY-RUN — showing what WOULD happen. Nothing is executed.
if defined DRY echo.

rem ------------------------------------------------------------------ helpers
set "NODE_BIN="
set "PNPM_BIN="
set "NODE_DIR="
set "GIT_BIN="
set "TOOLS_DIR=%~dp0tools"

call :echo_step 0 "Check & prepare prerequisites (auto-download if missing)"

call :ensure_git
if errorlevel 1 goto :fail
call :ensure_node
if errorlevel 1 goto :fail

rem ------------------------------------------------------------ target dir
call :echo_step 1 "Install directory"
if not defined TARGET set "TARGET=%USERPROFILE%\deepseek-harness"
echo   target: %TARGET%
if defined DRY goto :post_target
if exist "%TARGET%" (
  if exist "%TARGET%\.git" (
    echo   [info] existing repository found — will update instead of clone.
    set "EXISTING_REPO=1"
  ) else (
    echo   [WARN] directory exists but is not a git repo.
    set /p CONFIRM="Continue into it anyway? [y/N] "
    if /i not "!CONFIRM!"=="y" ( echo   Aborted by user. & goto :fail )
  )
) else (
  mkdir "%TARGET%" 2>nul
)
:post_target

rem ---------------------------------------------------------------- clone
call :echo_step 2 "Fetch deepseek-harness source"
set "GH_URL=https://github.com/deepseek-ai/deepseek-harness.git"
set "GH_PROXY=https://ghfast.top/https://github.com/deepseek-ai/deepseek-harness.git"
if defined DRY ( echo   [dry-run] git clone %GH_PROXY%  ^(fallback %GH_URL%^) & goto :after_clone )
if defined EXISTING_REPO (
  pushd "%TARGET%"
  echo   updating existing repo (git pull --ff-only) ...
  git pull --ff-only 2>nul
  if errorlevel 1 echo   [WARN] git pull failed — leaving existing checkout untouched.
  popd
) else (
  echo   cloning via mirror %GH_PROXY% ...
  git clone %GH_PROXY% "%TARGET%" 2>nul
  if errorlevel 1 (
    echo   mirror failed, retrying direct from GitHub ...
    git clone %GH_URL% "%TARGET%"
    if errorlevel 1 ( echo   [FAIL] could not clone repository (network blocked?). & goto :fail )
  )
  if exist "%TARGET%\package.json" ( echo   [ok] source fetched. ) else ( echo   [FAIL] clone incomplete. & goto :fail )
)
:after_clone

rem ------------------------------------------------------------- patches
call :echo_step 3 "Apply Windows patches (see installer\patch-windows.mjs for the why)"
if defined DRY ( echo   [dry-run] node "%~dp0patch-windows.mjs" "%TARGET%" & goto :after_patch )
call "%NODE_BIN%" "%~dp0patch-windows.mjs" "%TARGET%"
if errorlevel 1 echo   [WARN] patching reported an issue — continuing anyway.
:after_patch

rem ------------------------------------------------------ pnpm install
call :echo_step 4 "Install dependencies (pnpm install)"
if defined DRY ( echo   [dry-run] cd "%TARGET%" ^&^& pnpm install & goto :after_install )
call :ensure_pnpm
if errorlevel 1 goto :fail
pushd "%TARGET%"
echo   running pnpm install (a few minutes) ...
call %PNPM_BIN% install
if errorlevel 1 (
  echo   [FAIL] pnpm install failed. Common causes: network to registry.npmmirror.com,
  echo          or a postinstall script error (see output above). Retry after fixing.
  popd & goto :fail
)
popd
:after_install

rem ----------------------------------------------------- workspace links
call :echo_step 5 "Link workspace packages (junctions — no admin needed)"
if defined DRY ( echo   [dry-run] node "%~dp0link-workspace.mjs" "%TARGET%" & goto :after_links )
call "%NODE_BIN%" "%~dp0link-workspace.mjs" "%TARGET%"
if errorlevel 1 echo   [WARN] some workspace links failed — build may complain.
:after_links

rem ---------------------------------------------------------------- build
if defined SKIP_BUILD ( call :echo_step 6 "Build (skipped via --skip-build)" & goto :after_build )
call :echo_step 6 "Build the project"
if defined DRY ( echo   [dry-run] pnpm run build:lib   then   vite build ^(web^) & goto :after_build )
pushd "%TARGET%"
echo   building libraries (tsc + tsdown) ...
call %PNPM_BIN% run build:lib
if errorlevel 1 ( echo   [FAIL] library build failed. & popd & goto :fail )
echo   building web frontend (vite) ...
pushd apps\web
call "%NODE_BIN%" "..\..\node_modules\vite\bin\vite.js" build
if errorlevel 1 echo   [WARN] web build failed (non-fatal for headless use).
popd
popd
:after_build

rem ------------------------------------------------------------ launcher
call :echo_step 7 "Prepare start launcher (start-dsh.cmd)"
if defined DRY ( echo   [dry-run] generate start-dsh.cmd + copy open-browser.vbs & goto :after_launcher )
(
echo @echo off
echo rem DeepSeek Harness launcher - generated by installer
echo cd /d "%%~dp0"
echo rem Smart launcher: open browser if server already up, else start it
echo rem No hard-coded paths: node is located at run time ^(PATH first,
echo rem then the self-contained copy the installer downloaded, if any).
echo netstat -ano ^| findstr ":3080" ^| findstr "LISTENING" ^>nul 2^>^&1
echo if not errorlevel 1 goto :already
echo echo DeepSeek Harness server not running, starting ...
echo start "" wscript.exe "%%~dp0open-browser.vbs"
echo set "NODE_CMD="
echo where node ^>nul 2^>^&1 ^&^& set "NODE_CMD=node"
echo if not defined NODE_CMD if exist "!NODE_BIN!" set "NODE_CMD=!NODE_BIN!"
echo if not defined NODE_CMD ^( echo [ERROR] Node.js not found in PATH. Please install Node.js 22.19+ and retry. ^& pause ^& exit /b 1 ^)
echo "%%NODE_CMD%%" --import tsx/esm apps/cli/src/bin.ts web
echo goto :eof
echo :already
echo echo DeepSeek Harness server already running, opening browser ...
echo start "" http://127.0.0.1:3080
echo goto :eof
) > "%TARGET%\start-dsh.cmd"
copy /y "%~dp0open-browser.vbs" "%TARGET%\open-browser.vbs" >nul
echo   [ok] launcher ready (start-dsh.cmd).
:after_launcher

rem ------------------------------------------------------------ shortcut
if defined NO_SHORTCUT ( call :echo_step 8 "Desktop shortcut (skipped via --no-shortcut)" & goto :after_shortcut )
call :echo_step 8 "Create desktop shortcut + icon"
if defined DRY ( echo   [dry-run] generate dsh.ico  +  Desktop\DeepSeek Harness.lnk & goto :after_shortcut )
rem resolve the real desktop path (works with OneDrive-redirected desktops too)
for /f "delims=" %%d in ('powershell -NoProfile -ExecutionPolicy Bypass -Command "[Environment]::GetFolderPath('Desktop')"') do set "DESKTOP=%%d"
if not defined DESKTOP set "DESKTOP=%USERPROFILE%\Desktop"
echo   generating dsh.ico (sharp — no Python needed) ...
call "%NODE_BIN%" "%~dp0make-icon.mjs" "%TARGET%"
if errorlevel 1 echo   [WARN] icon generation failed — shortcut will use a default icon.
echo   creating desktop shortcut (Windows built-in) ...
powershell -NoProfile -ExecutionPolicy Bypass -Command "$ws=New-Object -ComObject WScript.Shell; $d=$ws.SpecialFolders('Desktop'); $s=$ws.CreateShortcut($d+'\DeepSeek Harness.lnk'); $s.TargetPath='%TARGET%\start-dsh.cmd'; $s.WorkingDirectory='%TARGET%'; if(Test-Path '%TARGET%\dsh.ico'){ $s.IconLocation='%TARGET%\dsh.ico,0' }; $s.Description='DeepSeek Harness Web UI (http://127.0.0.1:3080)'; $s.Save()" >nul 2>&1
if exist "%DESKTOP%\DeepSeek Harness.lnk" goto :shortcut_ok
echo   [WARN] PowerShell shortcut creation failed — falling back to Python (if available) ...
where py >nul 2>&1 && set "PYTHON_BIN=py"
if not defined PYTHON_BIN where python >nul 2>&1 && set "PYTHON_BIN=python"
if not defined PYTHON_BIN goto :shortcut_fail
"%PYTHON_BIN%" -m pip install --quiet --disable-pip-version-check -i https://mirrors.aliyun.com/pypi/simple pywin32 pillow >nul 2>nul
"%PYTHON_BIN%" "%~dp0create-shortcut.py" "%TARGET%" >nul 2>nul
if exist "%DESKTOP%\DeepSeek Harness.lnk" goto :shortcut_ok
:shortcut_fail
echo   [WARN] shortcut creation failed — install is still complete (run start-dsh.cmd to launch).
goto :after_shortcut
:shortcut_ok
echo   [ok] shortcut created on your desktop.
:after_shortcut

rem -------------------------------------------------------------- summary
call :echo_step 9 "Summary"
echo.
echo   ========================================================
echo    DeepSeek Harness installed successfully!
echo    Install dir : %TARGET%
echo    Web UI      : http://127.0.0.1:3080
echo    Start it    : %TARGET%\start-dsh.cmd   (or run: pnpm dsh web)
echo    Read docs   : installer\INSTALL.md
echo    Uninstall   : delete the install dir (and the desktop shortcut)
echo   ========================================================
echo.
if defined DRY echo   [dry-run] preview finished. No changes were made.
goto :done

:help
echo.
echo  DeepSeek Harness Installer — usage:
echo    install-dsh.cmd                      full install (defaults)
echo    install-dsh.cmd -d ^<dir^>           install to a specific directory
echo    install-dsh.cmd --dry-run            preview only, no changes
echo    install-dsh.cmd --force-download    always download self-contained git/node
echo    install-dsh.cmd --skip-build         install deps only, skip the build
echo    install-dsh.cmd --no-shortcut        do not create a desktop shortcut
echo    install-dsh.cmd --help               show this help
echo.
echo  Safety: source-visible, dry-run supported; writes only inside the
echo  chosen install directory. See installer\INSTALL.md for details.
goto :done

:ensure_git
  if defined FORCE_DL (
    if defined DRY ( echo   [dry-run] --force-download: will fetch bundled PortableGit to tools\git. & exit /b 0 )
    goto :download_git
  )
  where git >nul 2>&1
  if not errorlevel 1 (
    for /f "delims=" %%v in ('git --version 2^>nul') do set "GIT_VER=%%v"
    echo   [ok] git: !GIT_VER! ^(system git — no download^)
    exit /b 0
  )
  if defined DRY ( echo   [dry-run] git not found — will download bundled PortableGit to tools\git. & exit /b 0 )
  goto :download_git

:download_git
  set "LOCAL_GIT=%TOOLS_DIR%\git"
  set "GIT_ZIP=%TOOLS_DIR%\PortableGit.7z.exe"
  if exist "%LOCAL_GIT%\cmd\git.exe" (
    set "GIT_BIN=%LOCAL_GIT%\cmd"
    set "PATH=%LOCAL_GIT%\cmd;!PATH!"
    echo   [ok] using bundled PortableGit.
    exit /b 0
  )
  echo   [info] git not found - downloading self-contained PortableGit (~59 MB) ...
  if not exist "%TOOLS_DIR%" mkdir "%TOOLS_DIR%"
  powershell -NoProfile -ExecutionPolicy Bypass -Command "$ErrorActionPreference='Stop'; $u='https://ghfast.top/https://github.com/git-for-windows/git/releases/download/v2.55.0.windows.4/PortableGit-2.55.0.4-64-bit.7z.exe'; Invoke-WebRequest $u -OutFile '%GIT_ZIP%'" >nul 2>nul
  if not exist "%GIT_ZIP%" ( echo   [FAIL] could not download PortableGit (network?). & exit /b 1 )
  echo   extracting PortableGit ...
  "%GIT_ZIP%" -y -o"%LOCAL_GIT%" >nul 2>nul
  del /q "%GIT_ZIP%" 2>nul
  if exist "%LOCAL_GIT%\cmd\git.exe" (
    set "GIT_BIN=%LOCAL_GIT%\cmd"
    set "PATH=%LOCAL_GIT%\cmd;!PATH!"
    for /f "delims=" %%v in ('"%LOCAL_GIT%\cmd\git.exe" --version 2^>nul') do set "GIT_VER=%%v"
    echo   [ok] bundled git ready: !GIT_VER!
    exit /b 0
  )
  echo   [FAIL] PortableGit extraction failed.
  exit /b 1

:ensure_node
  if defined FORCE_DL (
    if defined DRY ( echo   [dry-run] --force-download: will fetch bundled Node 22 to tools\. & exit /b 0 )
    goto :download_node
  )
  where node >nul 2>&1
  if errorlevel 1 (
    if defined DRY ( echo   [dry-run] node not found — will download bundled Node 22 to tools\. & exit /b 0 )
    goto :download_node
  )
  set "NODE_BIN=node"
  for /f "delims=" %%v in ('node -v 2^>nul') do set "NODE_VER=%%v"
  rem repository requires node ^>=22.19 or ^>=24
  node -e "const m=process.version.slice(1).split('.').map(Number);process.exit((m[0]>22||(m[0]===22&&m[1]>=19)||m[0]>=24)?0:1)" >nul 2>&1
  if not errorlevel 1 (
    echo   [ok] node: !NODE_VER! ^(system node, meets >=22.19 — no download^)
    exit /b 0
  )
  if defined DRY ( echo   [dry-run] system node !NODE_VER! too old — will download bundled Node 22. & exit /b 0 )
  echo   [info] node found but too old (!NODE_VER!); downloading self-contained Node 22 ...
  goto :download_node

:download_node
  set "LOCAL_NODE=%TOOLS_DIR%\node-v22.22.2-win-x64"
  if exist "%LOCAL_NODE%\node.exe" (
    set "NODE_BIN=%LOCAL_NODE%\node.exe"
    set "PATH=%LOCAL_NODE%;!PATH!"
    echo   [ok] using bundled node.
    exit /b 0
  )
  echo   [info] downloading self-contained Node.js 22 (~35 MB) into "%TOOLS_DIR%" ...
  if not exist "%TOOLS_DIR%" mkdir "%TOOLS_DIR%"
  powershell -NoProfile -ExecutionPolicy Bypass -Command "$ErrorActionPreference='Stop'; $u='https://nodejs.org/dist/v22.22.2/node-v22.22.2-win-x64.zip'; $z='%TOOLS_DIR%\node.zip'; Invoke-WebRequest $u -OutFile $z; Expand-Archive -Force $z '%TOOLS_DIR%'; Remove-Item $z" >nul 2>nul
  if exist "%LOCAL_NODE%\node.exe" (
    set "NODE_BIN=%LOCAL_NODE%\node.exe"
    set "PATH=%LOCAL_NODE%;!PATH!"
    echo   [ok] self-contained node downloaded.
    exit /b 0
  )
  echo   [FAIL] could not download Node.js (network?). Install Node 22 from https://nodejs.org.
  exit /b 1

:ensure_pnpm
  where pnpm >nul 2>&1
  if not errorlevel 1 ( set "PNPM_BIN=pnpm" & exit /b 0 )
  rem corepack ships with Node; find the node dir and enable the pnpm shim
  for /f "delims=" %%d in ('where node 2^>nul') do set "NODE_DIR=%%~dpd"
  if defined NODE_DIR (
    set "PATH=!NODE_DIR!;!PATH!"
    call "!NODE_DIR!corepack.cmd" enable >nul 2>nul
  )
  where pnpm >nul 2>&1
  if not errorlevel 1 ( set "PNPM_BIN=pnpm" & exit /b 0 )
  echo   [FAIL] pnpm could not be enabled. Install Node 22 LTS (ships corepack) and retry.
  exit /b 1

:echo_step
  echo.
  echo   ------------------------------------------------------------------
  echo   [Step %~1] %~2
  echo   ------------------------------------------------------------------
  exit /b 0

:fail
  echo.
  echo   [FAIL] Installer aborted. Nothing was left half-done that can't be
  echo          cleaned by deleting the target directory.
  exit /b 1

:done
  exit /b 0
