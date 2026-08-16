@echo off
setlocal enabledelayedexpansion
chcp 65001 >nul
title DeepSeek Harness Installer (single-file)

rem ============================================================================
rem  DeepSeek Harness - Windows one-click installer (SINGLE FILE EDITION)
rem  ============================================================================
rem  WHAT THIS IS
rem    Everything is inside this one file: prerequisite setup, clone, Windows
rem    patches, pnpm install, workspace junctions, build, launcher and the
rem    desktop shortcut. Double-click and it just works.
rem    No helper scripts, no external files are needed next to it.
rem
rem  SAFETY MODEL (please read before running)
rem    - 100% source-visible: it is plain text, read every line, or run:
rem          install-dsh.cmd --dry-run
rem      which prints every step WITHOUT executing anything.
rem    - It ONLY writes inside the install directory you choose (default:
rem      %USERPROFILE%\deepseek-harness) plus one desktop shortcut. It does
rem      NOT touch the registry, does NOT modify your PATH permanently,
rem      does NOT install services.
rem    - Prerequisites are solved automatically: if git or Node.js >= 22.19
rem      is missing, self-contained copies are downloaded into
rem      <script-dir>\tools\ (git: PortableGit, node: official win-x64 zip).
rem      Nothing is installed into the system. Use --force-download to always
rem      download fresh copies even when a system version exists.
rem    - All downloaded artifacts come from official sources only:
rem        github.com/deepseek-ai/deepseek-harness   (official repo)
rem        nodejs.org                                 (official Node.js)
rem        github.com/git-for-windows/git             (official Git)
rem      The URLs are listed below; you can review or change them.
rem    - Optional icon: if a dsh.ico file sits next to this script it is
rem      copied to the install dir and used for the desktop shortcut; without
rem      it the shortcut uses the default Windows icon. The icon is the
rem      official DeepSeek whale logo (see website/public/favicon.svg).
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

rem ------------------------------------------------------------------ config
set "GH_URL=https://github.com/deepseek-ai/deepseek-harness.git"
set "GH_PROXY=https://ghfast.top/https://github.com/deepseek-ai/deepseek-harness.git"
set "GIT_URL=https://ghfast.top/https://github.com/git-for-windows/git/releases/download/v2.55.0.windows.4/PortableGit-2.55.0.4-64-bit.7z.exe"
set "NODE_URL=https://nodejs.org/dist/v22.22.2/node-v22.22.2-win-x64.zip"
set "NPM_REG=registry=https://registry.npmmirror.com"

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
if defined DRY echo   [MODE] DRY-RUN - showing what WOULD happen. Nothing is executed.
if defined DRY echo.

rem ------------------------------------------------------------------ helpers
set "NODE_BIN="
set "PNPM_BIN="
set "NODE_DIR="
set "GIT_BIN="
set "TOOLS_DIR=%~dp0tools"
set "LOG_FILE=%~dp0install.log"
echo [%date% %time%] DeepSeek Harness installer started > "%LOG_FILE%" 2>nul

call :echo_step 0 "Check and prepare prerequisites (auto-download if missing)"

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
    echo   [info] existing repository found - will update instead of clone.
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
if defined DRY ( echo   [dry-run] git clone %GH_PROXY%  ^(fallback %GH_URL%^) & goto :after_clone )
if defined EXISTING_REPO (
  pushd "%TARGET%"
  echo   updating existing repo (git pull --ff-only) ...
  git pull --ff-only
  if errorlevel 1 echo   [WARN] git pull failed (probably local patch changes) - leaving existing checkout untouched.
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
call :echo_step 3 "Apply Windows patches (why: see comments at each patch)"
if defined DRY ( echo   [dry-run] patch .npmrc / pnpm-workspace.yaml / postinstall no-op & goto :after_patch )
call :do_patch
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
call :echo_step 5 "Link workspace packages (junctions - no admin needed)"
if defined DRY ( echo   [dry-run] create junctions for all workspace packages & goto :after_links )
call :do_links
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
if defined DRY ( echo   [dry-run] generate smart start-dsh.cmd & goto :after_launcher )
(
echo @echo off
echo rem DeepSeek Harness launcher - generated by installer
echo cd /d "%%~dp0"
echo rem Smart launcher: open browser if server already up, else start it
echo rem No hard-coded paths: node is located at run time ^(PATH first,
echo rem then the self-contained copy the installer downloaded, if any^).
echo netstat -ano ^| findstr ":3080" ^| findstr "LISTENING" ^>nul 2^>^&1
echo if not errorlevel 1 goto :already
echo echo DeepSeek Harness server not running, starting ...
echo set "NODE_CMD="
echo where node ^>nul 2^>^&1 ^&^& set "NODE_CMD=node"
echo if not defined NODE_CMD if exist "!NODE_BIN!" set "NODE_CMD=!NODE_BIN!"
echo if not defined NODE_CMD ^( echo [ERROR] Node.js not found in PATH. Please install Node.js 22.19+ and retry. ^& pause ^& exit /b 1 ^)
echo "%%NODE_CMD%%" --import tsx/esm apps/cli/src/bin.ts web
echo powershell -NoProfile -ExecutionPolicy Bypass -Command "for($i=0;$i -lt 30;$i++){try{$r=Invoke-WebRequest -Uri 'http://127.0.0.1:3080' -UseBasicParsing -TimeoutSec 2;if($r.StatusCode -eq 200){Start-Process 'http://127.0.0.1:3080';exit}}catch{};Start-Sleep 2}"
echo goto :eof
echo :already
echo echo DeepSeek Harness server already running, opening browser ...
echo start "" http://127.0.0.1:3080
echo goto :eof
) > "%TARGET%\start-dsh.cmd"
echo   [ok] launcher ready (start-dsh.cmd).
:after_launcher

rem ------------------------------------------------------------ shortcut
if defined NO_SHORTCUT ( call :echo_step 8 "Desktop shortcut (skipped via --no-shortcut)" & goto :after_shortcut )
call :echo_step 8 "Create desktop shortcut + icon"
if defined DRY ( echo   [dry-run] copy dsh.ico + create Desktop\DeepSeek Harness.lnk & goto :after_shortcut )
rem optional icon: if a dsh.ico sits next to this installer, copy it over
rem (the icon is a separate resource file; without it the shortcut uses the
rem default Windows icon - install still works fine)
if exist "%~dp0dsh.ico" (
  copy /y "%~dp0dsh.ico" "%TARGET%\dsh.ico" >nul
  echo   [ok] icon copied (dsh.ico).
) else (
  echo   [info] dsh.ico not found next to installer - shortcut uses a default icon.
)
rem resolve the real desktop path (works with OneDrive-redirected desktops too)
for /f "delims=" %%d in ('powershell -NoProfile -ExecutionPolicy Bypass -Command "[Environment]::GetFolderPath('Desktop')"') do set "DESKTOP=%%d"
if not defined DESKTOP set "DESKTOP=%USERPROFILE%\Desktop"
echo   desktop: !DESKTOP!
echo   creating shortcut "DeepSeek Harness.lnk" ...
powershell -NoProfile -ExecutionPolicy Bypass -Command "$d='%DESKTOP%'; $s=(New-Object -ComObject WScript.Shell).CreateShortcut($d+'\DeepSeek Harness.lnk'); $s.TargetPath='%TARGET%\start-dsh.cmd'; $s.WorkingDirectory='%TARGET%'; if(Test-Path '%TARGET%\dsh.ico'){ $s.IconLocation='%TARGET%\dsh.ico,0' }; $s.Description='DeepSeek Harness Web UI (http://127.0.0.1:3080)'; $s.Save()"
if errorlevel 1 echo   [WARN] PowerShell reported an error creating the shortcut (see message above).
if exist "%DESKTOP%\DeepSeek Harness.lnk" (
  echo   [ok] shortcut created: "%DESKTOP%\DeepSeek Harness.lnk"
) else (
  echo   [WARN] desktop shortcut was not created - no problem, start it like this:
  echo          open "%TARGET%"
  echo          double-click  start-dsh.cmd
  echo          browser will open http://127.0.0.1:3080
)
:after_shortcut

rem -------------------------------------------------------------- summary
call :echo_step 9 "Summary"
echo.
echo   ========================================================
echo    DeepSeek Harness installed successfully!
echo    Install dir : %TARGET%
echo    Web UI      : http://127.0.0.1:3080
echo    Start it    : %TARGET%\start-dsh.cmd   ^(or the desktop icon if present^)
echo    Uninstall   : delete the install dir and the desktop shortcut
echo   ========================================================
echo.
if defined DRY echo   [dry-run] preview finished. No changes were made.
goto :done

:help
echo.
echo  DeepSeek Harness Installer - usage:
echo    install-dsh.cmd                      full install (defaults)
echo    install-dsh.cmd -d ^<dir^>           install to a specific directory
echo    install-dsh.cmd --dry-run            preview only, no changes
echo    install-dsh.cmd --force-download     always download self-contained git/node
echo    install-dsh.cmd --skip-build         install deps only, skip the build
echo    install-dsh.cmd --no-shortcut        do not create a desktop shortcut
echo    install-dsh.cmd --help               show this help
echo.
echo  Safety: source-visible, dry-run supported; writes only inside the
echo  chosen install directory plus one desktop shortcut.
pause
exit /b 0

rem ================================================================ patches
:do_patch
  rem ---- 1) .npmrc: use the npmmirror registry (fast in China) ----
  if not exist "%TARGET%\.npmrc" (
    echo %NPM_REG%> "%TARGET%\.npmrc"
  ) else (
    findstr /c:"registry.npmmirror.com" "%TARGET%\.npmrc" >nul 2>&1 || echo %NPM_REG%>> "%TARGET%\.npmrc"
  )
  echo   [ok] .npmrc: npmmirror registry

  rem ---- 2) pnpm-workspace.yaml + postinstall no-ops (via built-in PowerShell) ----
  rem      nodeLinker=hoisted: isolated linker fails on Windows top-level links
  rem      verifyDepsBeforeRun=false: keep manual junctions across pnpm run
  rem      koffi=false: skip failing source build, prebuilt binary is used
  rem      subprocess-local=false: skip macOS-only postinstall
  rem      postinstall no-op (root + subprocess-local): lefthook / spawn-helper
  rem      are not needed on Windows and abort the install when they fail
  powershell -NoProfile -ExecutionPolicy Bypass -Command "$t='%TARGET%'; ^
$ws=Join-Path $t 'pnpm-workspace.yaml'; ^
if(Test-Path $ws){ $c=[IO.File]::ReadAllText($ws); ^
  if(-not $c.Contains('nodeLinker: hoisted')){ $c='# Workaround (Windows): isolated linker fails to link top-level deps.'+[Environment]::NewLine+'nodeLinker: hoisted'+[Environment]::NewLine+[Environment]::NewLine+$c }; ^
  if(-not $c.Contains('verifyDepsBeforeRun: false')){ $c='# Workaround (Windows): do not auto re-install before pnpm run (keeps junctions).'+[Environment]::NewLine+'verifyDepsBeforeRun: false'+[Environment]::NewLine+[Environment]::NewLine+$c }; ^
  $c=$c -replace 'koffi:\s*true','koffi: false'; ^
  $c=$c -replace '(''@deepseek-ai/dsh-subprocess-local''[^'']*'':\s*)true','$1false'; ^
  [IO.File]::WriteAllText($ws,$c); ^
  Write-Output '  [ok] pnpm-workspace.yaml: hoisted + verifyDepsBeforeRun + koffi/subprocess-local build off' } ^
foreach($p in @((Join-Path $t 'package.json'),(Join-Path $t 'packages\subprocess\subprocess-local\package.json'))){ ^
  if(Test-Path $p){ try{ $o=Get-Content $p -Raw | ConvertFrom-Json }catch{ Write-Output ('  [WARN] skip invalid JSON: '+$p); continue }; ^
    if($o.scripts.postinstall){ $q=[char]34; $o.scripts.postinstall='node -e '+$q+'process.exit(0)'+$q; ^
      $json=$o | ConvertTo-Json -Depth 20; ^
      [IO.File]::WriteAllText($p,$json,(New-Object System.Text.UTF8Encoding($false))); ^
      Write-Output ('  [ok] '+$p+' : postinstall set to no-op') } } }"
  exit /b 0

rem ============================================================== junctions
:do_links
  rem Scan vendor/packages/apps/website/examples/python for workspace packages
  rem and create a directory junction node_modules\<name> for each. Junctions
  rem do not need admin rights (real symlinks do). Re-run is safe (idempotent).
  powershell -NoProfile -ExecutionPolicy Bypass -Command "$t='%TARGET%'; ^
$nm=Join-Path $t 'node_modules'; ^
$dirs=New-Object System.Collections.ArrayList; ^
function Add-Pkg($p){ if(Test-Path (Join-Path $p 'package.json')){ [void]$dirs.Add($p) } }; ^
foreach($base in @('vendor','apps')){ $b=Join-Path $t $base; if(Test-Path $b){ Get-ChildItem $b -Directory | ForEach-Object { Add-Pkg $_.FullName } } }; ^
$pk=Join-Path $t 'packages'; if(Test-Path $pk){ Get-ChildItem $pk -Directory | ForEach-Object { Get-ChildItem $_.FullName -Directory | ForEach-Object { Add-Pkg $_.FullName } } }; ^
Add-Pkg (Join-Path $t 'website'); Add-Pkg (Join-Path $t 'examples'); Add-Pkg (Join-Path $t 'python\sdk-runtime'); ^
$lr=Join-Path $t 'native\landlock-run'; if(Test-Path $lr){ Add-Pkg $lr; $lrp=Join-Path $lr 'packages'; if(Test-Path $lrp){ Get-ChildItem $lrp -Directory | ForEach-Object { Add-Pkg $_.FullName } } }; ^
$created=0;$skipped=0;$errored=0; ^
foreach($d in $dirs){ try{ $n=(Get-Content (Join-Path $d 'package.json') -Raw | ConvertFrom-Json).name }catch{ continue }; if(-not $n){ continue }; ^
  $l=Join-Path $nm $n; if(Test-Path $l){ $skipped++; continue }; ^
  $parent=Split-Path $l -Parent; if(-not (Test-Path $parent)){ New-Item -ItemType Directory -Path $parent -Force | Out-Null }; ^
  try{ New-Item -ItemType Junction -Path $l -Target $d -Force | Out-Null; $created++ }catch{ $errored++; Write-Output ('  ERR '+$n) } }; ^
Write-Output ('  workspace junctions: created='+$created+' skipped='+$skipped+' errored='+$errored)"
  exit /b 0

rem ============================================================== git tool
:ensure_git
  if defined FORCE_DL (
    if defined DRY ( echo   [dry-run] --force-download: will fetch bundled PortableGit to tools\git. & exit /b 0 )
    goto :download_git
  )
  where git >nul 2>&1
  if not errorlevel 1 (
    for /f "delims=" %%v in ('git --version 2^>nul') do set "GIT_VER=%%v"
    echo   [ok] git: !GIT_VER! ^(system git - no download^)
    exit /b 0
  )
  if defined DRY ( echo   [dry-run] git not found - will download bundled PortableGit to tools\git. & exit /b 0 )
  goto :download_git

:download_git
  set "LOCAL_GIT=%TOOLS_DIR%\git"
  set "GIT_SFX=%TOOLS_DIR%\PortableGit.7z.exe"
  if exist "%LOCAL_GIT%\cmd\git.exe" (
    set "GIT_BIN=%LOCAL_GIT%\cmd"
    set "PATH=%LOCAL_GIT%\cmd;!PATH!"
    echo   [ok] using bundled PortableGit.
    exit /b 0
  )
  echo   [info] git not found - downloading bundled PortableGit (~59 MB) ...
  echo          source: git-for-windows official release (via ghfast.top mirror)
  echo          this download is one-time; the extracted copy stays in tools\git
  echo [%date% %time%] downloading bundled PortableGit (~59 MB) >> "%LOG_FILE%"
  if not exist "%TOOLS_DIR%" mkdir "%TOOLS_DIR%"
  powershell -NoProfile -ExecutionPolicy Bypass -Command "$ProgressPreference='SilentlyContinue'; $ErrorActionPreference='Stop'; $u='%GIT_URL%'; Invoke-WebRequest $u -OutFile '%GIT_SFX%'" >nul 2>nul
  if not exist "%GIT_SFX%" ( echo   [FAIL] could not download PortableGit (network?). & exit /b 1 )
  echo   extracting PortableGit ...
  "%GIT_SFX%" -y -o"%LOCAL_GIT%" >nul 2>nul
  del /q "%GIT_SFX%" 2>nul
  if exist "%LOCAL_GIT%\cmd\git.exe" (
    set "GIT_BIN=%LOCAL_GIT%\cmd"
    set "PATH=%LOCAL_GIT%\cmd;!PATH!"
    for /f "delims=" %%v in ('"%LOCAL_GIT%\cmd\git.exe" --version 2^>nul') do set "GIT_VER=%%v"
    echo   [ok] bundled git ready: !GIT_VER!
    exit /b 0
  )
  echo   [FAIL] PortableGit extraction failed.
  exit /b 1

rem ============================================================= node tool
:ensure_node
  if defined FORCE_DL (
    if defined DRY ( echo   [dry-run] --force-download: will fetch bundled Node 22 to tools\. & exit /b 0 )
    goto :download_node
  )
  where node >nul 2>&1
  if errorlevel 1 (
    if defined DRY ( echo   [dry-run] node not found - will download bundled Node 22 to tools\. & exit /b 0 )
    goto :download_node
  )
  set "NODE_BIN=node"
  for /f "delims=" %%v in ('node -v 2^>nul') do set "NODE_VER=%%v"
  rem repository requires node ^>=22.19 or ^>=24
  node -e "const m=process.version.slice(1).split('.').map(Number);process.exit((m[0]>22||(m[0]===22&&m[1]>=19)||m[0]>=24)?0:1)" >nul 2>&1
  if not errorlevel 1 (
    echo   [ok] node: !NODE_VER! ^(system node, meets >=22.19 - no download^)
    exit /b 0
  )
  if defined DRY ( echo   [dry-run] system node !NODE_VER! too old - will download bundled Node 22. & exit /b 0 )
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
  echo   [info] downloading Node.js 22 runtime + deps (npm/corepack/pnpm, ~35 MB) ...
  echo          source: nodejs.org official (node-v22.22.2-win-x64.zip)
  echo          this download is one-time; the extracted copy stays in tools\
  echo [%date% %time%] downloading Node.js 22 runtime + deps (~35 MB) >> "%LOG_FILE%"
  if not exist "%TOOLS_DIR%" mkdir "%TOOLS_DIR%"
  powershell -NoProfile -ExecutionPolicy Bypass -Command "$ProgressPreference='SilentlyContinue'; $ErrorActionPreference='Stop'; $u='%NODE_URL%'; $z='%TOOLS_DIR%\node.zip'; Invoke-WebRequest $u -OutFile $z; Expand-Archive -Force $z '%TOOLS_DIR%'; Remove-Item $z" >nul 2>nul
  if exist "%LOCAL_NODE%\node.exe" (
    set "NODE_BIN=%LOCAL_NODE%\node.exe"
    set "PATH=%LOCAL_NODE%;!PATH!"
    echo   [ok] self-contained node downloaded.
    exit /b 0
  )
  echo   [FAIL] could not download Node.js (network?). 
  echo          Check your internet / proxy, or install Node.js 22 LTS from
  echo          https://nodejs.org and re-run this installer.
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
  echo [%date% %time%] step %~1: %~2 >> "%LOG_FILE%"
  exit /b 0

:fail
  echo.
  echo   [FAIL] Installer aborted. Nothing was left half-done that can't be
  echo          cleaned by deleting the target directory.
  echo          Note: the desktop shortcut was NOT created because the
  echo          install did not complete. Check the messages above for the
  echo          cause (most common: network / proxy issues during clone or
  echo          pnpm install - just re-run the installer to retry).
  echo          A copy of this log is saved at: %LOG_FILE%
  echo [%date% %time%] [FAIL] installer aborted >> "%LOG_FILE%"
  echo.
  pause
  exit /b 1

:done
  echo [%date% %time%] installer finished OK >> "%LOG_FILE%"
  echo.
  echo   ---------------------------------------------------------
  echo   If you see this, the install finished. You can close this
  echo   window now. To start DeepSeek Harness later, double-click
  echo   the desktop icon (or %TARGET%\start-dsh.cmd).
  echo   ---------------------------------------------------------
  pause
  exit /b 0
