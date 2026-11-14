#!/usr/bin/env bash
# Copies the package downloaded by Navigation Updater to a USB stick, for Gen5W
# (exFAT) cars where the updater itself cannot write to the stick. See README.
#
# Usage:
#   ./copy-to-stick.sh                      pick the vehicle folder and exFAT stick automatically
#   ./copy-to-stick.sh <stick-mount-dir>    copy to a specific mount point
#   ./copy-to-stick.sh <stick> <folder>     also choose the vehicle folder (name or path)
#
# Set YES=1 to skip the confirmation prompt. Set DRY_RUN=1 to only print the plan.
set -euo pipefail

PREFIX="$HOME/.local/share/hyundai-nau-prefix"
DOWNLOADS="$PREFIX/pfx/drive_c/users/steamuser/Downloads/NaU"

fail() { echo "Error: $*" >&2; exit 1; }

# Prints the choice made from the given options: the only one, or one picked by number.
choose() {
  local label="$1" choice
  shift
  [ "$#" -gt 0 ] || return 1
  if [ "$#" -eq 1 ]; then
    echo "$1"
    return 0
  fi
  echo "Several $label found:" >&2
  PS3="Select $label: "
  select choice in "$@"; do
    [ -n "$choice" ] && { echo "$choice"; return 0; }
  done < /dev/tty
}

findVehicleFolder() {
  local given="${1:-}"
  [ -d "$DOWNLOADS" ] || fail "No downloads at $DOWNLOADS. Let the updater download first."
  [ -z "$given" ] || {
    [ -d "$given" ] && { readlink -f "$given"; return 0; }
    [ -d "$DOWNLOADS/$given" ] && { echo "$DOWNLOADS/$given"; return 0; }
    fail "Vehicle folder not found: $given"
  }
  local folders=()
  mapfile -t folders < <(find "$DOWNLOADS" -mindepth 1 -maxdepth 1 -type d | sort)
  choose "vehicle folder" "${folders[@]}" || fail "$DOWNLOADS is empty."
}

# Lists mounted exFAT drives as "<mount>  [<label>]" so several sticks can be told apart.
listExfatSticks() {
  local mount
  find /run/media/"$USER" /media/"$USER" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | sort |
    while read -r mount; do
      [ "$(findmnt -no FSTYPE --target "$mount")" = exfat ] || continue
      echo "$mount  [$(findmnt -no SOURCE --target "$mount")]"
    done
}

findStick() {
  local given="${1:-}"
  [ -z "$given" ] || {
    [ -d "$given" ] && { readlink -f "$given"; return 0; }
    fail "Stick mount point not found: $given"
  }
  local sticks=()
  mapfile -t sticks < <(listExfatSticks)
  choose "exFAT USB stick" "${sticks[@]}" | sed 's/  \[.*\]$//' | grep . ||
    fail "No mounted exFAT stick under /run/media/$USER or /media/$USER. Pass the mount point to override."
}

SOURCE="$(findVehicleFolder "${2:-}")"
STICK="$(findStick "${1:-}")"

findmnt -no FSTYPE --target "$STICK" | grep -qi 'exfat' ||
  echo "Warning: $STICK is $(findmnt -no FSTYPE --target "$STICK"), not exFAT. Gen5W cars need exFAT." >&2

echo "From: $SOURCE ($(du -sh "$SOURCE" | cut -f1))"
echo "To:   $STICK (free: $(df -h --output=avail "$STICK" | tail -n1 | tr -d ' '))"
echo "Files go to the root of the stick; same-named files are overwritten."
[ "${DRY_RUN:-0}" != 1 ] || { echo "[dry-run] nothing copied"; exit 0; }
[ "${YES:-0}" = 1 ] || {
  read -rp "Continue? [y/N] " answer < /dev/tty
  [ "$answer" = y ] || [ "$answer" = Y ] || fail "Aborted."
}

# exFAT has no permissions or ownership, so do not try to preserve them.
if command -v rsync >/dev/null; then
  rsync -rt --no-perms --no-owner --no-group --info=progress2 "$SOURCE/" "$STICK/"
else
  cp -rv --no-preserve=mode,ownership "$SOURCE/." "$STICK/"
fi

echo "Flushing to the stick (do not unplug yet)..."
sync
# Files only on the stick (e.g. the car's device-info export) are expected.
problems="$(LC_ALL=C diff -rq "$SOURCE/" "$STICK/" 2>&1 | grep -v "^Only in $STICK/\?:" || true)"
[ -z "$problems" ] || { echo "$problems" >&2; fail "Verification failed, see above."; }
echo "COPY OK. Safe to unmount: udisksctl unmount -b $(findmnt -no SOURCE --target "$STICK")"
