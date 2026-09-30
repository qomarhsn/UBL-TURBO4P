# ======================================================================
# TURBO 4 PRO - Bootloader Unlock (UBL) - Windows PowerShell port
# Auto-detects SERVICE / PRELOAD method. Port of unlock.sh.
# Run via unlock.bat, or:  powershell -NoProfile -ExecutionPolicy Bypass -File unlock.ps1
# ======================================================================
param(
  [switch]$Service,   # force SERVICE method (skip version detect)
  [switch]$Preload,   # force PRELOAD method (skip version detect)
  [switch]$Auto,      # skip confirmation prompts
  [switch]$DryRun,    # print commands without executing
  [switch]$Help       # show usage
)

# =============================== CONFIG ===============================
$METHOD_THRESHOLD = [version]'3.0.11'   # <=3.0.11 = SERVICE method, above = PRELOAD method
$MAX_SUPPORTED    = [version]'3.0.305'  # this or later = tool will NOT work
$SCRIPT_DIR = Split-Path -Parent $MyInvocation.MyCommand.Path
$LOG_FILE   = Join-Path $SCRIPT_DIR ("unlock_log_{0}.txt" -f (Get-Date -Format 'yyyyMMdd_HHmmss'))
$StepConfirm = -not $Auto
$Dry         = [bool]$DryRun
$Method      = $null

# =============================== USAGE ================================
if ($Help) {
  Write-Host "Usage: unlock.ps1 [-Service] [-Preload] [-Auto] [-DryRun] [-Help]"
  Write-Host "  -Service  force SERVICE method (skip version detect)"
  Write-Host "  -Preload  force PRELOAD method (skip version detect)"
  Write-Host "  -Auto     skip confirmation prompts"
  Write-Host "  -DryRun   print commands without executing"
  exit 0
}

# ============================== HELPERS ===============================
function Info([string]$m) { Write-Host "[i] " -ForegroundColor Cyan -NoNewline; Write-Host $m }
function Ok([string]$m)   { Write-Host "[+] " -ForegroundColor Green -NoNewline; Write-Host $m }
function Warn([string]$m) { Write-Host "[!] " -ForegroundColor Yellow -NoNewline; Write-Host $m }
function Err([string]$m)  { Write-Host "[x] " -ForegroundColor Red -NoNewline; Write-Host $m }

function Banner {
  Write-Host ""
  Write-Host "  ============================================" -ForegroundColor Cyan
  Write-Host "     TURBO 4 PRO - BOOTLOADER UNLOCK (UBL)"    -ForegroundColor Cyan
  Write-Host "     auto-detect SERVICE / PRELOAD method"      -ForegroundColor Cyan
  Write-Host "  ============================================" -ForegroundColor Cyan
  Write-Host ""
}

function Log([string]$m) {
  try { Add-Content -Path $LOG_FILE -Value ("[{0}] {1}" -f (Get-Date -Format 'HH:mm:ss'), $m) -ErrorAction SilentlyContinue } catch {}
}

function Confirm([string]$p) {
  if (-not $StepConfirm) { return $true }
  Write-Host "? $p (Y/n): " -ForegroundColor Yellow -NoNewline
  # ReadKey reads the console directly (piped stdin is eaten by adb shell)
  try { $k = [Console]::ReadKey($true) } catch { Write-Host ""; return $true }
  Write-Host $k.Key
  return ($k.Key -ne 'N')
}

# Run-Step <description> <command array> [-Quiet]
# Executes and ABORTS the script (exit 1) if the command fails.
function Run-Step {
  param([string]$Desc, [string[]]$Cmd, [switch]$Quiet)
  Info $Desc
  Log ("> {0} :: {1}" -f $Desc, ($Cmd -join ' '))
  if ($Dry) { Warn ("DRY-RUN: skipped -> {0}" -f ($Cmd -join ' ')); return }
  $exe = $Cmd[0]
  $rest = @()
  if ($Cmd.Count -gt 1) { $rest = @($Cmd[1..($Cmd.Count - 1)]) }
  if ($Quiet) {
    $null = & $exe $rest 2>&1
  } else {
    & $exe $rest
  }
  if ($LASTEXITCODE -eq 0) { Ok "$Desc [OK]" }
  else { Err "$Desc [FAILED] - aborting."; Log "FAILED: $($Cmd -join ' ')"; exit 1 }
}

function Wait-Adb {
  Info "Waiting for phone in ADB mode..."
  $t = 0
  while ($true) {
    $null = & adb get-state 2>$null
    if ($LASTEXITCODE -eq 0) { break }
    if ($Dry) { Warn "DRY-RUN: skipping wait"; return }
    $t += 2
    if ($t -gt 240) { Err "No ADB device after 4min."; exit 1 }
    Start-Sleep -Seconds 2
  }
  $ser = "$(& adb get-serialno 2>$null)".Trim()
  Ok "Phone ready. device: $ser"
}

function Wait-Fastboot {
  Info "Waiting for phone in FASTBOOT mode... (Volume Down + Power to enter)"
  $t = 0
  while ($true) {
    # NB: `fastboot devices` exits 0 even with NO device - must check non-empty output.
    $out = ("$(& fastboot devices 2>$null)").Trim()
    if ($out) { break }
    if ($Dry) { Warn "DRY-RUN: skipping wait"; return }
    $t += 2
    if ($t -gt 240) { Err "No FASTBOOT device after 4min."; exit 1 }
    Start-Sleep -Seconds 2
  }
  Ok ("Fastboot ready. device: {0}" -f ($out -split '\s+')[0])
}


function Dump-Environment {
  Log "=== ENVIRONMENT ==="
  Log ("Date:     {0}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'))
  Log ("PS:       {0}" -f $PSVersionTable.PSVersion)
  Log ("OS:       {0}" -f ([Environment]::OSVersion.VersionString))
  Log ("adb:      {0}" -f ((& adb version 2>$null) | Select-Object -First 1))
  Log ("fastboot: {0}" -f ((& fastboot --version 2>$null) | Select-Object -First 1))
  Log ("Script:   {0}" -f (Join-Path $SCRIPT_DIR 'unlock.ps1'))
  $null = & adb get-state 2>$null
  if ($LASTEXITCODE -eq 0) {
    Log ("Serial:    {0}" -f ("$(& adb get-serialno 2>$null)").Trim())
    Log ("Model:     {0}" -f ("$(& adb shell getprop ro.product.model 2>$null)").Trim())
    Log ("Codename:  {0}" -f ("$(& adb shell getprop ro.product.codename 2>$null)").Trim())
    Log ("HOS name:  {0}" -f ("$(& adb shell getprop ro.mi.os.version.name 2>$null)").Trim())
    Log ("Android:   {0}" -f ("$(& adb shell getprop ro.build.version.release 2>$null)").Trim())
    Log ("Battery:   {0}%" -f ("$(& adb shell cat /sys/class/power_supply/capacity 2>$null)").Trim())
  }
  Log "=== END ENVIRONMENT ==="
}

# ========================== VERSION DETECT ============================
# Returns @{ name = <prop value>; ver = <numeric 3-part or $null> }
function Get-HosVersion {
  $name = ("$(& adb shell getprop ro.mi.os.version.name 2>$null)").Trim()
  $ver = $null
  if ($name -match '^OS?(\d+\.\d+\.\d+)') { $ver = $Matches[1] }
  if (-not $ver) {
    $inc = ("$(& adb shell getprop ro.build.version.incremental 2>$null)").Trim()
    if ($inc -match '^\D*(\d+\.\d+\.\d+)') { $ver = $Matches[1] }
  }
  return @{ name = $name; ver = $ver }
}

# =========================== SERVICE FLOW =============================
function Invoke-ServiceUnlock {
  foreach ($f in @('abl.elf', 'onyx_gpt_both4.bin', 'bonito.img', 'gpt_both4.bin')) {
    if (-not (Test-Path (Join-Path $SCRIPT_DIR $f))) { Err "Unlock files missing in $SCRIPT_DIR ($f)"; exit 1 }
  }

  if (-not (Confirm "STEP 1/3 - set permissive flag + reboot to system?")) { return $false }
  Run-Step "Set permissive boot flag" @('fastboot', 'oem', 'set-gpu-preemption', '0', 'androidboot.selinux=permissive')
  # Prefer `continue` (resumes boot with the permissive cmdline intact, per the kit);
  # some bootloaders don't implement it - fall back to a plain reboot then.
  if ($Dry) {
    Run-Step "Continue boot to system" @('fastboot', 'continue')
  } else {
    $null = & fastboot continue 2>$null
    if ($LASTEXITCODE -eq 0) { Ok "Continue boot to system [OK]" }
    else {
      Warn "'fastboot continue' failed or unsupported - falling back to 'fastboot reboot'"
      Run-Step "Reboot to system (fallback)" @('fastboot', 'reboot')
    }
  }
  Wait-Adb

  if (-not (Confirm "STEP 2/3 - MQSAS exploit to flash engineering ABL?")) { return $false }
  Run-Step "Push abl.elf" @('adb', 'push', (Join-Path $SCRIPT_DIR 'abl.elf'), '/data/local/tmp/abl')
  # NB: the whole device command must go as ONE adb shell string with INNER quotes -
  # otherwise the device shell splits `if=... of=...` and the service call is malformed.
  Run-Step "Exploit: write abl_a" @('adb', 'shell', "service call miui.mqsas.IMQSNative 21 i32 1 s16 'dd' i32 1 s16 'if=/data/local/tmp/abl of=/dev/block/by-name/abl_a' s16 '/data/mqsas/log.txt' i32 60") -Quiet
  Start-Sleep -Seconds 1
  Run-Step "Exploit: write abl_b" @('adb', 'shell', "service call miui.mqsas.IMQSNative 21 i32 1 s16 'dd' i32 1 s16 'if=/data/local/tmp/abl of=/dev/block/by-name/abl_b' s16 '/data/mqsas/log.txt' i32 60") -Quiet
  Start-Sleep -Seconds 1
  Run-Step "Reboot to bootloader" @('adb', 'reboot', 'bootloader')
  Wait-Fastboot

  if (-not (Confirm "STEP 3/3 - unlock GPT + temp boot + verify?")) { return $false }
  Run-Step "Flash unlock GPT" @('fastboot', 'flash', 'partition:4', (Join-Path $SCRIPT_DIR 'onyx_gpt_both4.bin'))
  Run-Step "Temp boot bonito.img" @('fastboot', 'boot', (Join-Path $SCRIPT_DIR 'bonito.img'))
  Warn "Phone will bootloop / show 'No OS found' - hold Volume Down + Power to re-enter fastboot."
  Wait-Fastboot
  Run-Step "Check unlocked" @('fastboot', 'getvar', 'unlocked')
  return $true
}

# =========================== PRELOAD FLOW =============================
function Invoke-PreloadUnlock {
  foreach ($f in @('preload.so', 'abl.elf', 'onyx_gpt_both4.bin', 'bonito.img', 'gpt_both4.bin')) {
    if (-not (Test-Path (Join-Path $SCRIPT_DIR $f))) { Err "Unlock files missing in $SCRIPT_DIR ($f)"; exit 1 }
  }

  if (-not (Confirm "STEP 1/3 - ADB exploit: push preload.so + root?")) { return $false }
  Run-Step "Push preload.so" @('adb', 'push', (Join-Path $SCRIPT_DIR 'preload.so'), '/data/local/tmp/preload.so')
  Run-Step "chmod 755" @('adb', 'shell', 'chmod 755 /data/local/tmp/preload.so')
  Run-Step "LD_PRELOAD exploit" @('adb', 'shell', "LD_PRELOAD=/data/local/tmp/preload.so id") -Quiet

  if (-not (Confirm "STEP 2/3 - push + dd engineering ABL (both slots)?")) { return $false }
  Run-Step "Push abl.elf" @('adb', 'push', (Join-Path $SCRIPT_DIR 'abl.elf'), '/data/local/tmp/abl')
  Run-Step "dd abl_a" @('adb', 'shell', "su -c 'dd if=/data/local/tmp/abl of=/dev/block/by-name/abl_a'") -Quiet
  Run-Step "dd abl_b" @('adb', 'shell', "su -c 'dd if=/data/local/tmp/abl of=/dev/block/by-name/abl_b'") -Quiet
  Run-Step "Reboot to bootloader" @('adb', 'reboot', 'bootloader')
  Wait-Fastboot

  if (-not (Confirm "STEP 3/3 - unlock GPT + temp boot + verify?")) { return $false }
  Run-Step "Flash unlock GPT" @('fastboot', 'flash', 'partition:4', (Join-Path $SCRIPT_DIR 'onyx_gpt_both4.bin'))
  Run-Step "Temp boot bonito.img" @('fastboot', 'boot', (Join-Path $SCRIPT_DIR 'bonito.img'))
  Warn "Phone will bootloop / show 'No OS found' - hold Volume Down + Power to re-enter fastboot."
  Wait-Fastboot
  Run-Step "Check unlocked" @('fastboot', 'getvar', 'unlocked')
  return $true
}

# ======================== FINAL STEP (SHARED) =========================
function Restore-Gpt {
  if ($Dry) { Warn "DRY-RUN: skipping unlock check + GPT restore."; return }
  # NB: `fastboot getvar` BLOCKS forever with no device - only run after Wait-Fastboot.
  $out = ("$(& fastboot getvar unlocked 2>&1 | Out-String)")
  if ($out -match 'unlocked:\s*(yes|true|1)') { Ok "BOOTLOADER IS UNLOCKED" }
  else { Warn "Unlocked flag not seen. Re-run flow or check manually." }
  if (-not (Confirm "Restore stock GPT now (gpt_both4.bin)?")) { return }
  Run-Step "Restore stock GPT" @('fastboot', 'flash', 'partition:4', (Join-Path $SCRIPT_DIR 'gpt_both4.bin'))
  Info "Verify: fastboot getvar unlocked"
}

# =============================== MAIN =================================
Banner

foreach ($t in @('adb', 'fastboot')) {
  if (-not (Get-Command $t -ErrorAction SilentlyContinue)) { Err "$t not found. Install platform-tools."; exit 1 }
}
Log "=== UBL auto-unlock started (method-threshold=$METHOD_THRESHOLD max-supported=$MAX_SUPPORTED) ==="
if ($Dry) { Warn "DRY-RUN enabled - nothing will run." }

# ---- 1) Detect HOS version via ADB (phone must be booted) ----
if ($Service) { $Method = 'service' }
elseif ($Preload) { $Method = 'preload' }
else {
  Info "Checking ADB connection for version detection..."
  $null = & adb get-state 2>$null
  if ($LASTEXITCODE -ne 0) { Wait-Adb }

  $h = Get-HosVersion
  Ok ("Version: {0} (num: {1})" -f $(if ($h.name) { $h.name } else { 'n/a' }), $(if ($h.ver) { $h.ver } else { 'n/a' }))

  if (-not $h.ver) {
    Warn "Could not read HOS version from ADB."
    if (-not (Confirm "Skip version check - use PRELOAD method anyway?")) { exit 0 }
    $Method = 'preload'
  } else {
    try { $v = [version]$h.ver } catch { Err "Unparseable version '$($h.ver)'."; exit 1 }
    if ($v -ge $MAX_SUPPORTED) {
      Err "HOS $($h.ver) >= $MAX_SUPPORTED -> THIS TOOL WILL NOT WORK."
      Err "Aborting (unlock requires HOS older than $MAX_SUPPORTED)."
      exit 1
    }
    if ($v -le $METHOD_THRESHOLD) { $Method = 'service'; Info "HOS <= $METHOD_THRESHOLD -> SERVICE method." }
    else { $Method = 'preload'; Info "HOS $($h.ver) (> $METHOD_THRESHOLD) -> PRELOAD method." }
  }
}

Log "Method: $Method"
Dump-Environment

# ---- 2) Warnings + confirm AFTER version is visible ----
Write-Host "--------------------------------------------"
Warn "UNLOCK WIPES ALL DATA on the phone."
Warn "Remove Mi/Google accounts + screen lock BEFORE continuing."
Warn "Uninstall the KernelSU app first if you ever used KSU root (kit requirement)."
Warn "Backup important files now."
if (-not (Confirm "Backup done & accounts removed? Proceed with $Method?")) { exit 0 }

# ---- 3) Run the unlock flow ----
if ($Method -eq 'service') {
  if (-not (Confirm "STEP 0: reboot to bootloader now?")) { exit 0 }
  Run-Step "Reboot to bootloader" @('adb', 'reboot', 'bootloader')
  Wait-Fastboot
  if (-not (Invoke-ServiceUnlock)) { exit 1 }
} else {
  if (-not (Invoke-PreloadUnlock)) { exit 1 }
}
Restore-Gpt

Ok "===== SCRIPT FINISHED ====="
Info "Log: $LOG_FILE"
$null = & adb get-state 2>$null
if ($LASTEXITCODE -eq 0) { Log "Final state: ADB (android)" }
else {
  $fb = ("$(& fastboot devices 2>$null)").Trim()
  if ($fb) { Log "Final state: fastboot" }
  else { Log "Final state: no device connected" }
}
