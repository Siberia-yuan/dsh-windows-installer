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
rem    - The embedded DeepSeek icon is decoded from base64 (it is the same
rem      whale logo as the official favicon of the project website).
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
  git pull --ff-only 2>nul
  if errorlevel 1 echo   [WARN] git pull failed - leaving existing checkout untouched.
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
if defined DRY ( echo   [dry-run] decode embedded icon + create Desktop\DeepSeek Harness.lnk & goto :after_shortcut )
rem resolve the real desktop path (works with OneDrive-redirected desktops too)
for /f "delims=" %%d in ('powershell -NoProfile -ExecutionPolicy Bypass -Command "[Environment]::GetFolderPath('Desktop')"') do set "DESKTOP=%%d"
if not defined DESKTOP set "DESKTOP=%USERPROFILE%\Desktop"
rem decode the embedded icon (base64 - temp file to stay under the cmdline limit)
if not exist "%TARGET%\dsh.ico" (
  if exist "%TEMP%\dsh_icon.b64" del "%TEMP%\dsh_icon.b64"
  > "%TEMP%\dsh_icon.b64" echo AAABAAIAMDAAAAEAIAAQBQAAJgAAAAAAAAABACAAxhsAADYFAACJUE5HDQoaCgAAAA1JSERSAAAAMAAAADAIBgAAAFcC+YcAAAAJcEhZcwAACxMAAAsTAQCanBgAAATCSURBVGiB7VlZiBxlEO71vu8jiqJ4YUAfvFAQjYoJ63b9vYm6gg8aEnSyXTWTGEUQPFYQQcQrggpKyEMkRslDfAiKF8gqIkLihetBMEHjrRjFGM3WflIzO7s9Pd09PZ2ZJOAU/C89//F99df113heT3rSk578r2VoCHvPreB0b08SKuGggHG5E8y3kQUwYCx0rL+WSth3lwEMFuLQuYKj5w3juPq3oRHs5wREoquc6F9OJmCDWP/xGbem7eVER6tzQ1zbFbAjI9grEASO9RknusGx7qiDqw3927F+QaK/N36vD5SyzIdExyeJ/kIhZuXFRSGc3XT2JMZNJPp5MrB8g0o4Jm1/txjHN81nfXlwEU7NIu1EH67OFVyXPIlxSM0UigOfGowwDUx/BYclkhb9boAxY3LO/kGIK82XAsESYn2nPs8v47JE+ybW9R0BP+kDxLjLNJd4C6K/pZB4xPzCiX6btrcf4siGzWaNYB8nuq5T4GO+ss40HidArC8l35xudaITGfuNJmnjge6Anzp0Q9wnKMScInv5IW5uAD8QYiaJ/ttdAlWT+riJBOsLbe7xukXHRu2zru42+AiA9VH7HSrh8KhzZg7WsbqDT2ufMaM5vnd5sL5vwKf8bz4OING1GfN3kOjywSU4otn2GeVdCn5q6CfRmE8Cabgp0fGaeeG2/gpOagIeMZ81EaaP+owBP8QFlhlJMEysK0n06y6R+NlyRTUCsr4a0/rmVNAxAl/WF1kSS503jEuMjGPd3q6m7fpJ9NMME/mmOWzqplwELNnUF/khTms1PxCcSKIv5iUwXY2ijxiL8vobib7dEnytipxelJie04iE8Il1S0sgrNuI9T0L1bbOMW7MeXPLWoKweBrViDmS14YMhjjZYns2EFTMGYn1yfo6En269Q1gQS4QVjxFWD/vtSnVOC76VoZ9/2RlN7E+MbVmKQ6s2X06gayqtJFAQ/Gm36cVXpkkrIJl/aCFKb0ZXeMYYQbpsdyHN4RRmUBQxtVeAZlXwgmmgBZ2/ZiRnX0HDnaMezPIPpT7YGLcGfP+VV5BcWVcRaza4iY0GvlcM8kJfzHOzH3ooODcGIFxxzijMAnRZXlDrEsOn6+0fyjrWExLK4sSsLcqiX5VjIBOUIiL2j7UnmvxjZxgdlESroxL6w/2NrW/vNCBVaeKOaDVP1mP8pYkRO9vU/ubEqvNvGKJI0Ej71qpm7wCfU70Mysr/GGck9JBGM2ledZtgeBCb2clHlInN38t6T07OX9zpF5/0EqT6O8DjFNqiSzb7h3jBq8TMmcpjkrKkCT6UVKhR4LbYwnow2sEZ0XnBIyLo926jtl9Vlgl0R8TDvrTqslopu6v4NgmUKxbfcb10T1rbwv9I+MW3nCMwaa3blExmybWH1LsdYtjfc66GOYjqeFQ9Nlo/9QeSeaoLcxpY2rHrV2hMs7e6dai3ZroWhLcbX1SYtxTu8n0bE2iK7xOSbVTJ7oiu8nUVqjcGFRwnr1xnRGyDhzr6lqDS58iwS0W0r1Oi9U41kkoDJx1O7E+bgrxdp+gzxdcYW+GtJ5mksat6oz6wh4hQ9XePs635EeC+6xMthK41p5Exf5TsPJ6d+PsSU960hOvq/If9/ypKyO8c1YAAAAASUVORK5CYIKJUE5HDQoaCgAAAA1JSERSAAABAAAAAQAIBgAAAFxyqGYAAAAJcEhZcwAACxMAAAsTAQCanBgAABt4SURBVHic7Z15nF1VkccPjvuGg7iNjrgv4L47LjgCMeSd85KIjQsqgkPTr87r8ImooKIBFUGcD4oKiuLO5ga4gKKAgAuiiYKIIMgSwAGjIEuAQFJd86nbDULoTvr1u+fWuff+vp9P/QEEuFVnefeeU/Ur5wAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA0ha2Xyb1DX544f1zuZ/0sAIAKWUDyPB/54hAnxEe+0ffljRgAAFrA/HF5qI98mS7+O414bSDZyvrZAACJCcQfvdviv9P4awg+AA1mUZSH+8g3TbsBEK/2o/JA62cEIBtGRuTf/BJ5fJfk1Z2evN2TvCeQfNATHxgiHxwiHxCi7OWjjOmf0QXmavnrP2m+J8H6GQEwI5A8JfTlnT7yYT7yrz3xLRtaMNO8Rk944rN8lDg6KvfJaSj1190T/3Mjz/956+cEoNpFEWUHH/krgXjlYIt9w+YjnztvqWyWy3CGKDtv9LmJr3RONrF+VgCSMULyYL32CpG/HSLfXOaiv8cmQLI0l6EMxGfO5pm74/J862cFoPRF3yHZKRAfP/hr/RyN+BxNtMlhKLtR/sMT8yw/Yw62fl4ASsGTvNJH/tKMJ99JjK/SzWbZMrlXLsPoe0IDPP/ft95Z7m/9zAAM8WsnewfiP1e36Kde+SOfkONNgD7XgJ8ue1s/M6gJ+mvR2V0e2+nLcz3JNt0obwokfU/rlvnIn/HEh89kgfizgXg/T7Jk8hVd5vuevHjh7vKE7faUB832GUaWygMCyY4h8ok+8rqqF/7UL+chOR6g6ZtIIL52wI3sRt1IrZ8dZESnJ08KPXl9iLxvID5Kr8kC8arEi+pqH/k0vZ7SAzXdIPS7Wif1/HF
  >> "%TEMP%\dsh_icon.b64" echo 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
  >> "%TEMP%\dsh_icon.b64" echo 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
  >> "%TEMP%\dsh_icon.b64" echo 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
  powershell -NoProfile -ExecutionPolicy Bypass -Command "[IO.File]::WriteAllBytes('%TARGET%\dsh.ico',[Convert]::FromBase64String((Get-Content '%TEMP%\dsh_icon.b64' -Raw)))"
  del "%TEMP%\dsh_icon.b64" >nul 2>&1
)
if not exist "%TARGET%\dsh.ico" echo   [WARN] icon decode failed - shortcut will use a default icon.
echo   creating desktop shortcut (Windows built-in) ...
powershell -NoProfile -ExecutionPolicy Bypass -Command "$ws=New-Object -ComObject WScript.Shell; $d=$ws.SpecialFolders('Desktop'); $s=$ws.CreateShortcut($d+'\DeepSeek Harness.lnk'); $s.TargetPath='%TARGET%\start-dsh.cmd'; $s.WorkingDirectory='%TARGET%'; if(Test-Path '%TARGET%\dsh.ico'){ $s.IconLocation='%TARGET%\dsh.ico,0' }; $s.Description='DeepSeek Harness Web UI (http://127.0.0.1:3080)'; $s.Save()" >nul 2>&1
if exist "%DESKTOP%\DeepSeek Harness.lnk" goto :shortcut_ok
echo   [WARN] shortcut creation failed - install is still complete (run start-dsh.cmd to launch).
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
echo    Start it    : %TARGET%\start-dsh.cmd   ^(double-click the desktop icon^)
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
goto :done

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
  if(Test-Path $p){ $o=Get-Content $p -Raw | ConvertFrom-Json; ^
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
  echo   [info] git not found - downloading self-contained PortableGit (~59 MB) ...
  if not exist "%TOOLS_DIR%" mkdir "%TOOLS_DIR%"
  powershell -NoProfile -ExecutionPolicy Bypass -Command "$ErrorActionPreference='Stop'; $u='%GIT_URL%'; Invoke-WebRequest $u -OutFile '%GIT_SFX%'" >nul 2>nul
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
  echo   [info] downloading self-contained Node.js 22 (~35 MB) into "%TOOLS_DIR%" ...
  if not exist "%TOOLS_DIR%" mkdir "%TOOLS_DIR%"
  powershell -NoProfile -ExecutionPolicy Bypass -Command "$ErrorActionPreference='Stop'; $u='%NODE_URL%'; $z='%TOOLS_DIR%\node.zip'; Invoke-WebRequest $u -OutFile $z; Expand-Archive -Force $z '%TOOLS_DIR%'; Remove-Item $z" >nul 2>nul
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
