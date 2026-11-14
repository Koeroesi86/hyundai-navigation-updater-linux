#!/usr/bin/env bash
# Installs/launches Hyundai Navigation Updater through Proton Experimental
# in a dedicated prefix (does not touch your Steam games).
#
# Proton lookup order:
#   1. Steam's own copy (~/.local/share/Steam, ~/.steam/steam, Flatpak Steam)
#   2. A standalone copy downloaded with steamcmd (anonymous login, no Steam
#      account or Steam client needed) into ~/.local/share/hyundai-nau-proton
#
# Usage:
#   ./run-navigation-updater.sh                 install (first run) or launch
#   ./run-navigation-updater.sh <url>           launch with a browser link, e.g.
#                                               com.hyundai.update.nau://...
#   ./run-navigation-updater.sh --install-desktop
#                                               add an app-menu entry and register
#                                               the browser link handlers
#
# Set INSTALLER_ARGS="..." to pass flags to the installer (first run only).
# Set DRY_RUN=1 to print what would happen without downloading or running.
set -euo pipefail

PREFIX="$HOME/.local/share/hyundai-nau-prefix"
STANDALONE="$HOME/.local/share/hyundai-nau-proton"
STEAMCMD_DIR="$STANDALONE/steamcmd"
PROTON_APPID=1493710
SCRIPT_PATH="$(readlink -f "$0")"
SCRIPT_DIR="$(dirname "$SCRIPT_PATH")"
INSTALLER="$SCRIPT_DIR/NavigationUpdaterInstaller.exe"
# Official installer, taken from the config of update.hyundai.com (EU). It may change or disappear.
INSTALLER_URL="https://oem-setup.map-care.com/update_program_download/nau_client/crossplatform/test/install/NavigationUpdaterInstaller.exe"
INSTALLER_SHA256="307f5a66f524bb8585fedebb37ac7a077dcf6b67fef8789995d714de598324cd"
APP="$PREFIX/pfx/drive_c/Program Files (x86)/Navigation Updater/package/Navigation Updater.exe"

SCHEMES=(com.hyundai.update.nau com.genesis.update.nau com.kia.update.nau)

installDesktop() {
  local dir="$HOME/.local/share/applications"
  local file="$dir/navigation-updater.desktop"
  local mimes
  mimes="$(printf 'x-scheme-handler/%s;' "${SCHEMES[@]}")"
  run mkdir -p "$dir" "$HOME/.config" # xdg-mime fails without ~/.config
  if [ "${DRY_RUN:-0}" = 1 ]; then
    echo "[dry-run] write $file (Exec=\"$SCRIPT_PATH\" %u, MimeType=$mimes)"
  else
    cat > "$file" <<DESKTOP
[Desktop Entry]
Type=Application
Name=Navigation Updater
Comment=Hyundai/Kia/Genesis navigation updater (via Proton)
Exec="$SCRIPT_PATH" %u
Icon=applications-system
Terminal=false
Categories=Utility;
MimeType=$mimes
DESKTOP
  fi
  command -v update-desktop-database >/dev/null && run update-desktop-database "$dir"
  local scheme
  for scheme in "${SCHEMES[@]}"; do
    run xdg-mime default navigation-updater.desktop "x-scheme-handler/$scheme"
  done
  echo "Installed $file and registered link handlers."
}

run() { if [ "${DRY_RUN:-0}" = 1 ]; then echo "[dry-run] $*"; else "$@"; fi; }

# Wine/Proton does not always expose mounted USB sticks as drive letters, so the
# updater cannot find them. Link every mounted removable drive (the usual
# desktop auto-mount locations) to a free letter from e: upward before launching.
mapUsbDrives() {
  local dos="$PREFIX/pfx/dosdevices"
  local letters=(e f g h i j k l m n o p q r s t u v w x y)
  local stale mount letter
  [ -d "$dos" ] || return 0
  # Remove links made by an earlier launch (they point into the mount directories).
  find "$dos" -maxdepth 1 -type l -name '[e-y]:' \( -lname '/run/media/*' -o -lname '/media/*' \) |
    while read -r stale; do run rm "$stale"; done
  for mount in /run/media/"$USER"/* /media/"$USER"/*; do
    [ -d "$mount" ] || continue
    while [ -e "$dos/${letters[0]}:" ] || [ -L "$dos/${letters[0]}:" ]; do letters=("${letters[@]:1}"); done
    letter="${letters[0]}"
    run ln -s "$mount" "$dos/$letter:"
    echo "USB: $mount -> $letter:"
    letters=("${letters[@]:1}")
  done
}

# Wine reports mounted folders as fixed disks (DriveType 3), while Windows reports USB
# sticks as removable (2) and the updater only offers removable drives as a target.
# Wine reports the "floppy" type as removable, so mark the letters used by
# mapUsbDrives that way. One time per prefix, once the prefix exists.
seedUsbDriveTypes() {
  local marker="$PREFIX/.usb-drive-types"
  local letter cmd=""
  [ -d "$PREFIX/pfx" ] && [ ! -f "$marker" ] || return 0
  for letter in {e..y}; do
    cmd+="reg add HKLM\\Software\\Wine\\Drives /v $letter: /t REG_SZ /d floppy /f & "
  done
  { run "$PROTON" run cmd /c "${cmd}rem" >/dev/null 2>&1 && run touch "$marker"; } ||
    echo "Warning: could not mark USB drive letters as removable" >&2
}

findSteamProton() {
  local steamRoot
  for steamRoot in "$HOME/.local/share/Steam" "$HOME/.steam/steam" "$HOME/.var/app/com.valvesoftware.Steam/.local/share/Steam"; do
    [ -x "$steamRoot/steamapps/common/Proton - Experimental/proton" ] || continue
    echo "$steamRoot"
    return 0
  done
  return 1
}

installStandaloneProton() {
  local fetch
  command -v curl >/dev/null || { echo "curl is required" >&2; exit 1; }
  if ! command -v steamcmd >/dev/null && [ ! -x "$STEAMCMD_DIR/steamcmd.sh" ]; then
    echo "Downloading steamcmd from Valve..."
    run mkdir -p "$STEAMCMD_DIR"
    run bash -c 'set -o pipefail; curl -fL --proto "=https" --tlsv1.2 "$1" | tar -xz -C "$2"' _ \
      "https://steamcdn-a.akamaihd.net/client/installer/steamcmd_linux.tar.gz" "$STEAMCMD_DIR"
  fi
  fetch="$(command -v steamcmd || echo "$STEAMCMD_DIR/steamcmd.sh")"
  echo "Downloading Proton Experimental (large download)..."
  # steamcmd often fails its first run ("Missing configuration"); retrying works.
  local attempt
  for attempt in 1 2 3; do
    run "$fetch" +force_install_dir "$STANDALONE/steamapps/common/Proton - Experimental" \
      +login anonymous +app_update "$PROTON_APPID" validate +quit && return 0
    echo "steamcmd attempt $attempt failed, retrying..." >&2
    sleep 5
  done
  echo "Could not download Proton Experimental with steamcmd." >&2
  exit 1
}

if [ "${1:-}" = "--install-desktop" ]; then
  installDesktop
  exit 0
fi

# Only browser links of the registered schemes may reach the app (no flags or paths).
validateLinks() {
  local joined pattern arg
  joined="$(IFS='|'; echo "${SCHEMES[*]}")"
  pattern="^(${joined//./\\.}):"
  for arg in "$@"; do
    [[ "$arg" =~ $pattern ]] || { echo "Refusing argument that is not a Navigation Updater link: $arg" >&2; exit 1; }
  done
}

validateLinks "$@"

if steamRoot="$(findSteamProton)"; then
  PROTON="$steamRoot/steamapps/common/Proton - Experimental/proton"
  CLIENT_PATH="$steamRoot"
else
  [ -x "$STANDALONE/steamapps/common/Proton - Experimental/proton" ] || installStandaloneProton
  PROTON="$STANDALONE/steamapps/common/Proton - Experimental/proton"
  CLIENT_PATH="$STANDALONE"
fi

downloadInstaller() {
  echo "Downloading Navigation Updater installer (about 205 MB)..."
  run curl -fL --proto '=https' --tlsv1.2 --retry 3 -o "$INSTALLER.part" "$INSTALLER_URL"
  [ "${DRY_RUN:-0}" = 1 ] && return 0
  echo "$INSTALLER_SHA256  $INSTALLER.part" | sha256sum -c - && { mv "$INSTALLER.part" "$INSTALLER"; return 0; }
  echo "Checksum mismatch. Hyundai may have published a new installer version." >&2
  echo "Inspect $INSTALLER.part, then set SKIP_CHECKSUM=1 to accept it." >&2
  [ "${SKIP_CHECKSUM:-0}" = 1 ] && mv "$INSTALLER.part" "$INSTALLER" && return 0
  rm -f "$INSTALLER.part"
  exit 1
}

# A leftover installer file is run only if it still matches the pinned checksum.
verifyExistingInstaller() {
  echo "$INSTALLER_SHA256  $INSTALLER" | sha256sum -c --quiet - && return 0
  echo "$INSTALLER does not match the pinned SHA-256." >&2
  [ "${SKIP_CHECKSUM:-0}" = 1 ] && return 0
  echo "Delete it to download a fresh copy, or set SKIP_CHECKSUM=1 to run it anyway." >&2
  exit 1
}

# First run downloads (if needed) and installs; later runs launch the installed app.
# Arguments (a browser link) are only passed to the app, never to the installer.
TARGET="$APP"
ARGS=("$@")
if [ ! -f "$APP" ]; then
  if [ -f "$INSTALLER" ]; then verifyExistingInstaller; else downloadInstaller; fi
  TARGET="$INSTALLER"
  # Optional extra installer flags.
  read -ra ARGS <<< "${INSTALLER_ARGS:-}"
fi

export STEAM_COMPAT_DATA_PATH="$PREFIX"
export STEAM_COMPAT_CLIENT_INSTALL_PATH="$CLIENT_PATH"
run mkdir -p "$PREFIX"
seedUsbDriveTypes
mapUsbDrives
echo "Proton: $PROTON"
echo "Target: $TARGET"
run exec "$PROTON" run "$TARGET" "${ARGS[@]}"
