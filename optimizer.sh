#!/data/data/com.termux/files/usr/bin/bash
# Author: Redwan Ahemed
# Git: xemonbae01
# Writing Time: 2026-01-29
# Description:
# This script is a non-root Android optimization tool designed for Termux.
# It safely cleans cache, temporary files, and junk data without touching
# user media such as photos, videos, or documents. It operates only within
# approved cache and temporary directories, supports a dry-run preview mode,
# provides storage and system reports, opens app settings for heavy apps,
# and can schedule automatic weekly cleanups using Termux Job Scheduler.
# The script uses a menu-driven interface and follows strict safety rules
# to prevent accidental data loss.

set -euo pipefail
IFS=$'\n\t'

DRY_RUN=${DRY_RUN:-0}
REPORT_LINES=${REPORT_LINES:-30}
NOW="$(date '+%Y-%m-%d %H:%M:%S')"

SAFE_CACHE_DIRS=(
  "/sdcard/Android/data"
  "/sdcard/Android/media"
  "/sdcard"
)

SAFE_FILE_PATTERNS=("*.tmp" "*.temp" "*.log" "*.old" "*.bak" "*.partial" "*.crdownload")

PROTECT_DIRS=(
  "/sdcard/DCIM"
  "/sdcard/Pictures"
  "/sdcard/Movies"
  "/sdcard/Download/Telegram"
  "/sdcard/WhatsApp/Media"
  "/sdcard/Download/Instagram"
)

HEAVY_PACKAGES=(
  "com.facebook.katana"
  "com.instagram.android"
  "com.google.android.youtube"
  "com.pubg.imobile"
  "com.tencent.ig"
  "com.snapchat.android"
  "com.whatsapp"
  "com.google.android.apps.photos"
)

log(){ echo -e "[$NOW] $*"; }
run(){ if [ "$DRY_RUN" -eq 1 ]; then echo "DRY-RUN: $*"; else eval "$@"; fi; }
has_cmd(){ command -v "$1" >/dev/null 2>&1; }

require_storage(){
  if [ ! -d "/sdcard" ]; then
    log "Granting storage… (first time only)"
    termux-setup-storage || true
    sleep 2
  fi
}

ensure_termux_api(){
  if ! has_cmd termux-battery-status; then
    log "Installing termux-api (provides battery/telephony/etc)…"
    pkg install -y termux-api >/dev/null 2>&1 || true
  fi
}

safe_find_delete(){
  local base="$1"
  local name="$2"
  find "$base" -type d \( -iname "cache" -o -iname "caches" -o -iname "tmp" -o -iname "temp" -o -path "*/files/temp*" \) \
    -prune -print0 2>/dev/null | while IFS= read -r -d '' d; do
      for p in "${PROTECT_DIRS[@]}"; do
        [[ "$d" == "$p"* ]] && continue 2
      done
      if [ "$DRY_RUN" -eq 1 ]; then
        find "$d" -type f -name "$name" -print 2>/dev/null
      else
        find "$d" -type f -name "$name" -delete 2>/dev/null
      fi
  done
}

clean_termux(){
  log "Cleaning Termux caches & package leftovers…"
  run "rm -rf $PREFIX/var/cache/* $PREFIX/var/log/* $PREFIX/tmp/* 2>/dev/null || true"
  run "apt-get clean >/dev/null 2>&1 || true"
}

clean_app_external_caches(){
  log "Clearing external app caches (safe dirs)…"
  for root in "${SAFE_CACHE_DIRS[@]}"; do
    for pat in "${SAFE_FILE_PATTERNS[@]}"; do
      safe_find_delete "$root" "$pat"
    done
    find "$root" -type d \( -iname "cache" -o -iname "caches" \) -print0 2>/dev/null | \
    while IFS= read -r -d '' cdir; do
      skip=0
      for p in "${PROTECT_DIRS[@]}"; do [[ "$cdir" == "$p"* ]] && skip=1; done
      [ $skip -eq 1 ] && continue
      if [ "$DRY_RUN" -eq 1 ]; then
        find "$cdir" -type f -print 2>/dev/null
      else
        find "$cdir" -type f -delete 2>/dev/null
      fi
    done
  done
}

clear_thumbnails(){
  local tdir="/sdcard/DCIM/.thumbnails"
  if [ -d "$tdir" ]; then
    log "Removing .thumbnails cache…"
    if [ "$DRY_RUN" -eq 1 ]; then
      find "$tdir" -type f -print 2>/dev/null
    else
      find "$tdir" -type f -delete 2>/dev/null
    fi
  fi
}

clean_downloads_junk(){
  local dld="/sdcard/Download"
  [ -d "$dld" ] || return 0
  log "Cleaning junk files in Downloads (won’t touch your actual docs/media)…"
  for pat in "${SAFE_FILE_PATTERNS[@]}"; do
    if [ "$DRY_RUN" -eq 1 ]; then
      find "$dld" -maxdepth 3 -type f -name "$pat" -print 2>/dev/null
    else
      find "$dld" -maxdepth 3 -type f -name "$pat" -delete 2>/dev/null
    fi
  done
}

remove_empty_dirs(){
  log "Removing empty directories left by apps…"
  find /sdcard -type d -empty 2>/dev/null | grep -v -E "^/sdcard/(DCIM|Pictures|Movies|WhatsApp/Media|Download/Telegram|Download/Instagram)" | \
  while read -r d; do
    if [ "$DRY_RUN" -eq 1 ]; then echo "$d"; else rmdir "$d" 2>/dev/null || true; fi
  done
}

storage_report(){
  log "Generating storage report (top ${REPORT_LINES})…"
  echo "----- BIGGEST DIRECTORIES -----"
  du -h -d 2 /sdcard 2>/dev/null | grep -v -E "/sdcard/(DCIM|Pictures|Movies|WhatsApp/Media)" | sort -hr | head -n "$REPORT_LINES"
  echo
  echo "----- BIGGEST FILES -----"
  find /sdcard -type f 2>/dev/null \
    ! -path "/sdcard/DCIM/*" ! -path "/sdcard/Pictures/*" ! -path "/sdcard/Movies/*" ! -path "/sdcard/WhatsApp/Media/*" \
    ! -name "*.jpg" ! -name "*.jpeg" ! -name "*.png" ! -name "*.mp4" ! -name "*.mkv" ! -name "*.mov" \
    -exec du -h {} + 2>/dev/null | sort -hr | head -n "$REPORT_LINES"
}

system_status(){
  ensure_termux_api
  log "Battery/Thermal & live CPU/RAM:"
  termux-battery-status 2>/dev/null || true
  echo
  echo "----- TOP (10) -----"
  top -b -n 1 2>/dev/null | head -n 15 || true
  echo
  echo "----- MEMORY -----"
  free -h 2>/dev/null || true
}

open_settings_shortcuts(){
  log "Opening Settings pages for heavy apps (press back between each)…"
  for pkg in "${HEAVY_PACKAGES[@]}"; do
    log "Opening: $pkg"
    am start -a android.settings.APPLICATION_DETAILS_SETTINGS -d "package:${pkg}" >/dev/null 2>&1 || true
    sleep 1.0
  done
}

schedule_weekly(){
  if has_cmd termux-job-scheduler; then
    log "Scheduling weekly cleanup job…"
    termux-job-scheduler --job-id 17171 \
      --period-ms 604800000 \
      --requires-charging true \
      --requires-battery-not-low true \
      --requires-device-idle false \
      --requires-storage-not-low false \
      --network any \
      --script "$HOME/optimize.sh" >/dev/null 2>&1 || true
    log "Scheduled. You can remove with: termux-job-scheduler --cancel --job-id 17171"
  else
    log "termux-job-scheduler not available on your build."
  fi
}

menu(){
  echo "================ Android Optimizer (Non-Root) ================"
  echo "1) Clean Termux caches"
  echo "2) Clear external app caches & temps (safe)"
  echo "3) Clear .thumbnails cache"
  echo "4) Clean Downloads junk files"
  echo "5) Remove empty directories"
  echo "6) Storage report (top big dirs/files)"
  echo "7) System status (battery/thermal/CPU/RAM)"
  echo "8) Open Settings pages for heavy apps"
  echo "9) RUN EVERYTHING (safe combo)"
  echo "10) Schedule weekly auto-cleanup"
  echo "0) Exit"
  echo "DRY_RUN=$DRY_RUN (set DRY_RUN=1 ./optimize.sh to preview)"
  echo "=============================================================="
  read -rp "Choose: " c
  case "$c" in
    1) clean_termux ;;
    2) clean_app_external_caches ;;
    3) clear_thumbnails ;;
    4) clean_downloads_junk ;;
    5) remove_empty_dirs ;;
    6) storage_report ;;
    7) system_status ;;
    8) open_settings_shortcuts ;;
    9) clean_termux; clean_app_external_caches; clear_thumbnails; clean_downloads_junk; remove_empty_dirs; system_status; storage_report ;;
    10) schedule_weekly ;;
    0) exit 0 ;;
    *) echo "Invalid";;
  esac
}

require_storage
menu
