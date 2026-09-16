#!/usr/bin/env bash
set -uo pipefail

# =============================== CONFIG ===============================
METHOD_THRESHOLD="3.0.11"        # <=3.0.11 = SERVICE method, above = PRELOAD method
MAX_SUPPORTED="3.0.305"          # this or later = tool will NOT work
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="$SCRIPT_DIR/unlock_log_$(date +%Y%m%d_%H%M%S).txt"
STEP_USER_CONFIRM=1
DRY_RUN=0

# =============================== COLORS ===============================
if [ -t 1 ] && command -v tput >/dev/null 2>&1; then
  BOLD=$(tput bold); RED=$(tput setaf 1); GREEN=$(tput setaf 2)
  YELLOW=$(tput setaf 3); BLUE=$(tput setaf 4); CYAN=$(tput setaf 6)
  RESET=$(tput sgr0)
else
  BOLD=""; RED=""; GREEN=""; YELLOW=""; BLUE=""; CYAN=""; RESET=""
fi

# ============================== HELPERS ==============================
info()  { echo -e "${BLUE}[i]${RESET} $*"; }
ok()    { echo -e "${GREEN}[+]${RESET} $*"; }
warn()  { echo -e "${YELLOW}[!]${RESET} $*"; }
err()   { echo -e "${RED}[x]${RESET} $*"; }
banner() {
  echo
  echo -e "${BOLD}${CYAN}  ╔══════════════════════════════════════════════════╗${RESET}"
  echo -e "${BOLD}${CYAN}  ║      TURBO 4 PRO · BOOTLOADER UNLOCK (UBL)      ║${RESET}"
  echo -e "${BOLD}${CYAN}  ║      auto-detect SERVICE / PRELOAD method        ║${RESET}"
  echo -e "${BOLD}${CYAN}  ╚══════════════════════════════════════════════════╝${RESET}"
  echo
}
log() { echo -e "[$(date '+%H:%M:%S')] $*" >>"$LOG_FILE" 2>/dev/null; }

dump_environment() { # collect all diagnostics into the log for bug reports
  log "=== ENVIRONMENT ==="
  log "Date:        $(date '+%F %T %Z')"
  log "hostname:    $(hostname 2>/dev/null)"
  log "uname:       $(uname -a 2>/dev/null)"
  log "Distro:      $( (. /etc/os-release && echo "$PRETTY_NAME") 2>/dev/null || echo n/a)"
  log "Bash:        ${BASH_VERSION:-n/a}"
  log "adb:         $(adb version 2>/dev/null | head -1 || echo 'adb not found')"
  log "fastboot:    $(fastboot --version 2>/dev/null | head -1 || echo 'fastboot not found')"
  log "Script:      $SCRIPT_DIR/unlock.sh"
  log "Args:        $*"
  log "Home:        ${HOME:-n/a}"
  log "adb devices: $(adb devices 2>/dev/null | sed -n '2p' || echo 'none')"
  log "fastboot:    $(fastboot devices 2>/dev/null | sed -n '1p' || echo 'none')"
  if adb get-state >/dev/null 2>&1; then
    log "Serial:      $(adb get-serialno 2>/dev/null)"
    log "Model:       $(adb shell getprop ro.product.model 2>/dev/null | tr -d '\r')"
    log "Codename:    $(adb shell getprop ro.product.codename 2>/dev/null | tr -d '\r')"
    log "HOS name:    $(adb shell getprop ro.mi.os.version.name 2>/dev/null | tr -d '\r')"
    log "Android:     $(adb shell getprop ro.build.version.release 2>/dev/null | tr -d '\r')"
    log "MiUI ver:    $(adb shell getprop ro.miui.version.name 2>/dev/null | tr -d '\r')"
    log "Kernel:      $(adb shell uname -r 2>/dev/null | tr -d '\r')"
    log "Secureboot:  $(adb shell getprop ro.boot.secureboot 2>/dev/null | tr -d '\r')"
    log "SELinux:     $(adb shell getenforce 2>/dev/null | tr -d '\r')"
    log "Battery:     $(adb shell cat /sys/class/power_supply/capacity 2>/dev/null | tr -d '\r')%"
  fi
  log "=== END ENVIRONMENT ==="
}

confirm() { # confirm [prompt]
  local p="${1:-continue?}"
  if [ "$STEP_USER_CONFIRM" = "0" ]; then return 0; fi
  echo -en "${YELLOW}?${RESET} $p (Y/n): "
  read -r -n1 -s reply; echo
  [ "$reply" != "n" ] && [ "$reply" != "N" ]
}

need() { # need <tool>
  if ! command -v "$1" >/dev/null 2>&1; then
    err "$1 not found. Install android-tools."
    exit 1
  fi
}

run() { # run <quiet?> <description> <command...>
  local quiet="$1"; shift
  local desc="$1"; shift
  info "$desc"
  log "> $desc :: $*"
  if [ "$DRY_RUN" = "1" ]; then warn "DRY-RUN: skipped -> $*"; return 0; fi
  if [ "$quiet" = "1" ]; then
    "$@" >/dev/null 2>&1 && ok "$desc [OK]" || { err "$desc [FAILED]"; return 1; }
  else
    "$@" && ok "$desc [OK]" || { err "$desc [FAILED]"; return 1; }
  fi
}

adb_wait_phone() {
  info "Waiting for phone in ADB mode..."
  local t=0
  until adb get-state >/dev/null 2>&1; do
    [ $DRY_RUN = 1 ] && { warn "DRY-RUN: skipping wait"; return 0; }
    t=$((t+1)); [ $t -gt 120 ] && { err "No ADB device after 4min."; exit 1; }
    sleep 2
  done
  ok "Phone ready. device: $(adb get-serialno 2>/dev/null)"
}

fastboot_wait() {
  info "Waiting for phone in FASTBOOT mode... (Volume Down + Power to enter)"
  local t=0
  until fastboot devices >/dev/null 2>&1; do
    [ $DRY_RUN = 1 ] && { warn "DRY-RUN: skipping wait"; return 0; }
    t=$((t+1)); [ $t -gt 120 ] && { err "No FASTBOOT device after 4min."; exit 1; }
    sleep 2
  done
  ok "Fastboot ready."
}

# ========================== VERSION DETECT ===========================
get_hos_version() {
  local name ver
  name=$(adb shell getprop ro.mi.os.version.name 2>/dev/null | tr -d '\r')
  ver=$(echo "$name" | sed -nE 's/^OS?([0-9]+\.[0-9]+\.[0-9]+).*/\1/p')
  if [ -z "$ver" ]; then
    ver=$(adb shell getprop ro.build.version.incremental 2>/dev/null | tr -d '\r')
    ver=$(echo "$ver" | sed -nE 's/^[^0-9]*([0-9]+\.[0-9]+\.[0-9]+).*/\1/p')
  fi
  echo "$name|$ver"
}

# cmp_version a b -> 0 if a<b, 1 if a=b, 2 if a>b
cmp_version() {
  local IFS=. va vb i x y
  read -ra va <<<"$1"; read -ra vb <<<"$2"
  for i in 0 1 2; do
    x="${va[$i]:-0}"; y="${vb[$i]:-0}"
    [ "$((10#$x))" -lt "$((10#$y))" ] && return 0
    [ "$((10#$x))" -gt "$((10#$y))" ] && return 2
  done
  return 1
}

# =========================== SERVICE FLOW ============================
unlock_service() {
  [ -f "$SCRIPT_DIR/abl.elf" ] && [ -f "$SCRIPT_DIR/onyx_gpt_both4.bin" ] \
  && [ -f "$SCRIPT_DIR/bonito.img" ] && [ -f "$SCRIPT_DIR/gpt_both4.bin" ] \
  || { err "Unlock files missing in $SCRIPT_DIR"; exit 1; }

  confirm "STEP 1/3 · set permissive flag + reboot to system?" || return 1
  run 0 "Set permissive boot flag" fastboot oem set-gpu-preemption 0 "androidboot.selinux=permissive"
  run 0 "Reboot to system" fastboot reboot
  adb_wait_phone

  confirm "STEP 2/3 · MQSAS exploit to flash engineering ABL?" || return 1
  run 0 "Push abl.elf" adb push "$SCRIPT_DIR/abl.elf" /data/local/tmp/abl
  run 1 "Exploit: write abl_a" adb shell service call miui.mqsas.IMQSNative 21 i32 1 s16 "dd" i32 1 s16 "if=/data/local/tmp/abl of=/dev/block/by-name/abl_a" s16 "/data/mqsas/log.txt" i32 60
  sleep 1
  run 1 "Exploit: write abl_b" adb shell service call miui.mqsas.IMQSNative 21 i32 1 s16 "dd" i32 1 s16 "if=/data/local/tmp/abl of=/dev/block/by-name/abl_b" s16 "/data/mqsas/log.txt" i32 60
  sleep 1
  run 0 "Reboot to bootloader" adb reboot bootloader
  fastboot_wait

  confirm "STEP 3/3 · unlock GPT + temp boot + verify?" || return 1
  run 0 "Flash unlock GPT" fastboot flash partition:4 "$SCRIPT_DIR/onyx_gpt_both4.bin"
  run 0 "Temp boot bonito.img" fastboot boot "$SCRIPT_DIR/bonito.img"
  warn "Phone will bootloop / show 'No OS found' — hold Volume Down + Power to re-enter fastboot."
  fastboot_wait
  run 0 "Check unlocked" fastboot getvar unlocked
  return 0
}

# =========================== PRELOAD FLOW ============================
unlock_preload() {
  [ -f "$SCRIPT_DIR/preload.so" ] && [ -f "$SCRIPT_DIR/abl.elf" ] \
  && [ -f "$SCRIPT_DIR/onyx_gpt_both4.bin" ] && [ -f "$SCRIPT_DIR/bonito.img" ] \
  && [ -f "$SCRIPT_DIR/gpt_both4.bin" ] \
  || { err "Unlock files missing in $SCRIPT_DIR"; exit 1; }

  confirm "STEP 1/3 · ADB exploit: push preload.so + root?" || return 1
  run 0 "Push preload.so" adb push "$SCRIPT_DIR/preload.so" /data/local/tmp/preload.so
  run 0 "chmod 755" adb shell chmod 755 /data/local/tmp/preload.so
  run 1 "LD_PRELOAD exploit" adb shell "LD_PRELOAD=/data/local/tmp/preload.so id"

  confirm "STEP 2/3 · push + dd engineering ABL (both slots)?" || return 1
  run 0 "Push abl.elf" adb push "$SCRIPT_DIR/abl.elf" /data/local/tmp/abl
  run 1 "dd abl_a" adb shell "su -c 'dd if=/data/local/tmp/abl of=/dev/block/by-name/abl_a'"
  run 1 "dd abl_b" adb shell "su -c 'dd if=/data/local/tmp/abl of=/dev/block/by-name/abl_b'"
  run 0 "Reboot to bootloader" adb reboot bootloader
  fastboot_wait

  confirm "STEP 3/3 · unlock GPT + temp boot + verify?" || return 1
  run 0 "Flash unlock GPT" fastboot flash partition:4 "$SCRIPT_DIR/onyx_gpt_both4.bin"
  run 0 "Temp boot bonito.img" fastboot boot "$SCRIPT_DIR/bonito.img"
  warn "Phone will bootloop / show 'No OS found' — hold Volume Down + Power to re-enter fastboot."
  fastboot_wait
  run 0 "Check unlocked" fastboot getvar unlocked
  return 0
}

# ======================== FINAL STEP (SHARED) ========================
restore_gpt_and_apps() {
  local out
  out=$(fastboot getvar unlocked 2>&1)
  if echo "$out" | grep -qiE "unlocked: *(yes|true|1)"; then
    ok "BOOTLOADER IS UNLOCKED"
  else
    warn "Unlocked flag not seen. Re-run flow or check manually."
  fi
  confirm "Restore stock GPT now (gpt_both4.bin)?" || return 0
  run 0 "Restore stock GPT" fastboot flash partition:4 "$SCRIPT_DIR/gpt_both4.bin"
  info "Verify: fastboot getvar unlocked"
}

# =============================== MAIN ================================
main() {
  banner
  while [ $# -gt 0 ]; do
    case "$1" in
      -s|--service)  FORCE_SERVICE=1;;
      -p|--preload)   FORCE_PRELOAD=1;;
      -a|--auto)     STEP_USER_CONFIRM=0;;
      -n|--dry-run)  DRY_RUN=1;;
      *) warn "Unknown option: $1";;
    esac; shift
  done

  need adb; need fastboot
  log "=== UBL auto-unlock started (method-threshold=$METHOD_THRESHOLD max-supported=$MAX_SUPPORTED) ==="
  [ "$DRY_RUN" = 1 ] && warn "DRY-RUN enabled — nothing will run."

  # ---- 1) Detect HOS version via ADB (phone must be booted) ----
  if [ "${FORCE_SERVICE:-0}" = 1 ]; then METHOD=service;
  elif [ "${FORCE_PRELOAD:-0}" = 1 ]; then METHOD=preload;
  else
    info "Checking ADB connection for version detection..."
    adb get-state >/dev/null 2>&1 || adb_wait_phone

    IFS='|' read -r hname hver <<<"$(get_hos_version)"
    ok "Version: ${hname:-n/a} (num: ${hver:-n/a})"

    if [ -z "$hver" ]; then
      warn "Could not read HOS version from ADB."
      confirm "Skip version check — use PRELOAD method anyway?" || exit 0
      METHOD=preload
    else
      cmp_version "$hver" "$MAX_SUPPORTED"; local c=$?
      if [ $c -eq 1 ] || [ $c -eq 2 ]; then
        err "HOS $hver >= $MAX_SUPPORTED → THIS TOOL WILL NOT WORK."
        err "Aborting (unlock requires HOS older than ${MAX_SUPPORTED})."
        exit 1
      fi
      cmp_version "$hver" "$METHOD_THRESHOLD"; local c2=$?
      if [ $c2 -eq 0 ] || [ $c2 -eq 1 ]; then
        METHOD=service; info "HOS <= $METHOD_THRESHOLD → SERVICE method."
      else
        METHOD=preload; info "HOS $hver (> $METHOD_THRESHOLD) → PRELOAD method."
      fi
    fi
  fi

  log "Method:      ${METHOD:-n/a}"
  dump_environment "$*"

  # ---- 2) Warnings + confirm AFTER version is visible ----
  echo "────────────────────────────────────────────────────────────"
  warn "UNLOCK WIPES ALL DATA on the phone."
  warn "Remove Mi/Google accounts + screen lock BEFORE continuing."
  warn "Backup important files now."
  confirm "Backup done & accounts removed? Proceed with $METHOD?" || exit 0

  # ---- 3) Run the unlock flow ----
  if [ "$METHOD" = "service" ]; then
    confirm "STEP 0: reboot to bootloader now?" || exit 0
    run 0 "Reboot to bootloader" adb reboot bootloader
    fastboot_wait
    unlock_service
    restore_gpt_and_apps
  else
    unlock_preload
    restore_gpt_and_apps
  fi

  ok "===== SCRIPT FINISHED ====="
  info "Log: $LOG_FILE"
  if adb get-state >/dev/null 2>&1; then
    log "Final state: ADB (android)"
  elif fastboot devices >/dev/null 2>&1; then
    log "Final state: fastboot"
  else
    log "Final state: no device connected"
  fi
}

main "$@"