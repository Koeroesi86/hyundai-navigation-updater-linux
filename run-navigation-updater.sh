#!/usr/bin/env bash
# Installs/launches Hyundai Navigation Updater through Wine (default) or Proton
# Experimental, in a dedicated prefix (does not touch your Steam games).
#
# Runner selection (RUNNER=auto|wine|proton, default auto):
#   1. An app already installed in the Proton prefix keeps using Proton.
#   2. Wine from PATH (or WINE=/path/to/wine), prefix ~/.local/share/hyundai-nau-wine-prefix
#      (override with WINE_PREFIX_DIR).
#      The installer runs with Wine's menu builder on, to get the app's icon; after
#      install it is disabled and --install-desktop reuses that icon (none is shipped here).
#   3. Wine missing: in a terminal, offers to install it with the system package
#      manager (dnf, apt, pacman, zypper). Declined or no terminal: Proton.
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

PROTON_PREFIX="$HOME/.local/share/hyundai-nau-prefix"
WINE_PREFIX_DIR="${WINE_PREFIX_DIR:-$HOME/.local/share/hyundai-nau-wine-prefix}"
STANDALONE="$HOME/.local/share/hyundai-nau-proton"
STEAMCMD_DIR="$STANDALONE/steamcmd"
PROTON_APPID=1493710
SCRIPT_PATH="$(readlink -f "$0")"
SCRIPT_DIR="$(dirname "$SCRIPT_PATH")"
INSTALLER="$SCRIPT_DIR/NavigationUpdaterInstaller.exe"
# Official installer, taken from the config of update.hyundai.com (EU). It may change or disappear.
INSTALLER_URL="https://oem-setup.map-care.com/update_program_download/nau_client/crossplatform/test/install/NavigationUpdaterInstaller.exe"
INSTALLER_SHA256="307f5a66f524bb8585fedebb37ac7a077dcf6b67fef8789995d714de598324cd"
APP_REL="drive_c/Program Files (x86)/Navigation Updater/package/Navigation Updater.exe"

SCHEMES=(com.hyundai.update.nau com.genesis.update.nau com.kia.update.nau)

# The installer runs under Wine's menu builder, which extracts the app's own icon into the
# icon theme and names it in the menu entries it writes. Reuse that icon (so none
# is stored here) and delete those entries, leaving only ours. Sets ICON_NAME.
reuseWineIcon() {
  local entries
  ICON_NAME=""
  mapfile -t entries < <(find "$HOME/.local/share/applications/wine" -name '*.desktop' \
    -exec grep -lF "$WINE_PREFIX_DIR" {} + 2>/dev/null)
  [ "${#entries[@]}" -gt 0 ] || return 0
  ICON_NAME="$(sed -n '/^Icon=/{s///p;q}' "${entries[@]}")"
  # Names with spaces or a ".0" suffix are unreliable in theme lookups; use the file itself.
  [ -z "$ICON_NAME" ] || ICON_NAME="$(find "$HOME/.local/share/icons/hicolor" -name "$ICON_NAME.png" 2>/dev/null |
    sort -V | tail -n1 | grep . || echo "$ICON_NAME")"
  run rm -- "${entries[@]}"
}

installDesktop() {
  local dir="$HOME/.local/share/applications"
  local file="$dir/navigation-updater.desktop"
  local mimes
  mimes="$(printf 'x-scheme-handler/%s;' "${SCHEMES[@]}")"
  run mkdir -p "$dir" "$HOME/.config" # xdg-mime fails without ~/.config
  reuseWineIcon
  if [ "${DRY_RUN:-0}" = 1 ]; then
    echo "[dry-run] write $file (Exec=\"$SCRIPT_PATH\" %u, MimeType=$mimes)"
  else
    cat > "$file" <<DESKTOP
[Desktop Entry]
Type=Application
Name=Navigation Updater
Comment=Hyundai/Kia/Genesis navigation updater (via Wine/Proton)
Exec="$SCRIPT_PATH" %u
Icon=${ICON_NAME:-applications-system}
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

# True when the filesystem mounted at $1 sits on a USB device (udev ID_BUS=usb), so
# internal disks, network shares and card slots on other buses are never exposed.
isUsbMount() {
  findmnt -no SOURCE --target "$1" |
    sed 's/\[.*\]$//' | # btrfs reports subvolumes as /dev/x[/subvol]
    xargs -r udevadm info -q property -n 2>/dev/null |
    grep -qx 'ID_BUS=usb'
}

# Wine/Proton does not always expose mounted USB sticks as drive letters, so the
# updater cannot find them. Link every mounted USB drive (the usual desktop
# auto-mount locations) to a free letter from e: upward before launching.
mapUsbDrives() {
  local dos="$WINEPFX/dosdevices"
  local letters=(e f g h i j k l m n o p q r s t u v w x y)
  local stale mount letter
  [ -d "$dos" ] || return 0
  # Remove links made by an earlier launch (they point into the mount directories).
  find "$dos" -maxdepth 1 -type l -name '[e-y]:' \( -lname '/run/media/*' -o -lname '/media/*' \) |
    while read -r stale; do run rm "$stale"; done
  for mount in /run/media/"$USER"/* /media/"$USER"/*; do
    [ -d "$mount" ] || continue
    isUsbMount "$mount" || { echo "Skipping non-USB mount: $mount"; continue; }
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
  [ -d "$WINEPFX" ] && [ ! -f "$marker" ] || return 0
  for letter in {e..y}; do
    cmd+="reg add HKLM\\Software\\Wine\\Drives /v $letter: /t REG_SZ /d floppy /f & "
  done
  { run "${RUN_CMD[@]}" cmd /c "${cmd}rem" >/dev/null 2>&1 && run touch "$marker"; } ||
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

findWine() {
  WINE="${WINE:-$(command -v wine || true)}"
  [ -x "$WINE" ]
}

# Sets WINE_INSTALL_CMD for the system package manager, or fails when none is known.
wineInstallCommand() {
  if command -v dnf >/dev/null; then WINE_INSTALL_CMD=(sudo dnf install -y wine)
  elif command -v apt-get >/dev/null; then WINE_INSTALL_CMD=(sudo apt-get install -y wine)
  elif command -v pacman >/dev/null; then WINE_INSTALL_CMD=(sudo pacman -S --needed wine)
  elif command -v zypper >/dev/null; then WINE_INSTALL_CMD=(sudo zypper install wine)
  else return 1
  fi
}

offerWineInstall() {
  local answer
  wineInstallCommand || return 1
  if [ "${DRY_RUN:-0}" = 1 ]; then
    echo "[dry-run] Wine is missing; would offer: ${WINE_INSTALL_CMD[*]}"
    WINE=wine
    return 0
  fi
  { [ -t 0 ] && [ -t 1 ]; } || return 1
  read -rp "Wine is not installed. Install it with '${WINE_INSTALL_CMD[*]}'? [y/N] " answer || return 1
  [[ "$answer" =~ ^[Yy] ]] || return 1
  "${WINE_INSTALL_CMD[@]}" && findWine
}

# Sets RUNNER to wine or proton.
chooseRunner() {
  RUNNER="${RUNNER:-auto}"
  case "$RUNNER" in
    proton) return 0 ;;
    wine) findWine || offerWineInstall || { echo "Wine not found (set WINE=/path/to/wine or install wine)." >&2; exit 1; }; return 0 ;;
    auto) ;;
    *) echo "RUNNER must be auto, wine or proton (got: $RUNNER)" >&2; exit 1 ;;
  esac
  if [ -f "$PROTON_PREFIX/pfx/$APP_REL" ] && [ ! -f "$WINE_PREFIX_DIR/$APP_REL" ]; then
    echo "Existing Proton install found; keeping Proton (RUNNER=wine installs a new Wine prefix)."
    RUNNER=proton
    return 0
  fi
  if findWine || offerWineInstall; then RUNNER=wine; return 0; fi
  echo "Wine unavailable; falling back to Proton."
  RUNNER=proton
}

chooseRunner
if [ "$RUNNER" = wine ]; then
  PREFIX="$WINE_PREFIX_DIR"
  WINEPFX="$PREFIX"
  RUN_CMD=("$WINE")
  export WINEPREFIX="$PREFIX" WINEARCH=win64 WINEDEBUG="${WINEDEBUG:--all}"
  echo "Wine: $WINE"
else
  PREFIX="$PROTON_PREFIX"
  WINEPFX="$PREFIX/pfx"
  if steamRoot="$(findSteamProton)"; then
    PROTON="$steamRoot/steamapps/common/Proton - Experimental/proton"
    CLIENT_PATH="$steamRoot"
  else
    [ -x "$STANDALONE/steamapps/common/Proton - Experimental/proton" ] || installStandaloneProton
    PROTON="$STANDALONE/steamapps/common/Proton - Experimental/proton"
    CLIENT_PATH="$STANDALONE"
  fi
  RUN_CMD=("$PROTON" run)
  export STEAM_COMPAT_DATA_PATH="$PREFIX"
  export STEAM_COMPAT_CLIENT_INSTALL_PATH="$CLIENT_PATH"
  echo "Proton: $PROTON"
fi
APP="$WINEPFX/$APP_REL"
# Wine's menu builder is only wanted while installing (it extracts the icon, see
# reuseWineIcon); afterwards it would add its own entries that bypass this script.
[ "$RUNNER" = wine ] && [ -f "$APP" ] && export WINEDLLOVERRIDES="winemenubuilder.exe=d${WINEDLLOVERRIDES:+;$WINEDLLOVERRIDES}"

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

run mkdir -p "$PREFIX"
seedUsbDriveTypes
mapUsbDrives
echo "Target: $TARGET"
run exec "${RUN_CMD[@]}" "$TARGET" "${ARGS[@]}"
