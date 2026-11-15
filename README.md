# Hyundai Navigation Updater on Linux (Wine / Proton)

> **Disclaimer: unofficial and unsupported.** This project is not affiliated with,
> endorsed by, or supported by Hyundai. It runs Hyundai's Windows-only Navigation
> Updater under Wine/Proton, which Hyundai does not support. Updating a vehicle's
> infotainment unit carries real risk (a failed or interrupted update can leave the
> head unit unusable and may affect your warranty). Use at your own risk, with no
> warranty of any kind. If in doubt, use a Windows or macOS machine or visit a dealer.
> The installer is Hyundai's proprietary software and is **not** included in this
> repository; the script downloads it from Hyundai's own servers.

## License
The scripts and documentation in this repository are under the [MIT License](LICENSE).
This does not cover Hyundai's Navigation Updater, which remains Hyundai's property.

## Usage
    ./run-navigation-updater.sh

- First run: downloads the installer (~205 MB) from Hyundai's server, verifies its
  SHA-256, then runs it. The installer is a bootstrapper, so the launching process
  exits immediately and a second process shows the setup window.
- Later runs: launches `Navigation Updater.exe` from the prefix.
- `./run-navigation-updater.sh --install-desktop` (after the app is installed) adds a
  "Navigation Updater" app-menu entry and registers the browser link handlers
  `com.hyundai.update.nau://`, `com.genesis.update.nau://` and `com.kia.update.nau://`
  (the schemes the app registers in its Wine registry). Links from the Hyundai
  update website then open in the updater. A link passed as an argument
  (`./run-navigation-updater.sh <url>`) is forwarded to the app.
- `DRY_RUN=1 ./run-navigation-updater.sh` prints the steps without doing anything.
- If the checksum no longer matches (Hyundai published a new version), the script
  stops. Inspect the `.part` file, then re-run with `SKIP_CHECKSUM=1` to accept it.

## Installer source
- URL: https://oem-setup.map-care.com/update_program_download/nau_client/crossplatform/test/install/NavigationUpdaterInstaller.exe
  (found in the site config of update.hyundai.com/EU/EN; the website's own download
  button may not work. This link may change or break without notice.)
- Pinned SHA-256: 307f5a66f524bb8585fedebb37ac7a077dcf6b67fef8789995d714de598324cd

## Runner (Wine by default, Proton as fallback)
`RUNNER=auto` (default) picks, in order:
1. **Proton, if the app is already installed in the Proton prefix** (so an earlier install keeps working; set `RUNNER=wine` to start a fresh Wine install instead).
2. **Wine** from `PATH` (or `WINE=/path/to/wine`), in its own prefix `~/.local/share/hyundai-nau-wine-prefix` (`WINE_PREFIX_DIR=...` to use another one, e.g. a Lutris prefix).
3. If Wine is missing and the script runs in a terminal, it asks whether to install it with `dnf`, `apt-get`, `pacman` or `zypper` (uses `sudo`). Declining, no terminal (e.g. launched from the menu) or an unknown package manager falls back to Proton.

`RUNNER=wine` or `RUNNER=proton` forces one. The Wine prefix is 64-bit (`WINEARCH=win64`), which is what a Lutris setup with Wine-GE 8-26 used successfully. Wine runs with `WINEDEBUG=-all` unless you set it. The Wine path is untested end to end.

**Menu icon:** during the install, Wine's menu builder extracts the updater's own icon into your icon theme (`~/.local/share/icons/hicolor/`; nothing is stored in this repo). After the install it is disabled with `WINEDLLOVERRIDES=winemenubuilder.exe=d`, so Wine adds no entries that bypass the script. Run `./run-navigation-updater.sh --install-desktop` once the install has finished: it uses the extracted icon file for its menu entry and deletes the Wine-generated entries for this prefix ("Navigation Updater" and its uninstaller). Without a Wine install it uses a generic icon. Until you run it, only Wine's own entry exists, which starts the app without the USB drive mapping.

## Proton
Used when Wine is unavailable or `RUNNER=proton`. The script looks for Proton Experimental in Steam (native or Flatpak). If none is
found, it downloads its own copy with `steamcmd` (anonymous login, no Steam account
needed) into `~/.local/share/hyundai-nau-proton`.
- `steamcmd` is 32-bit; on Fedora you may need `sudo dnf install glibc.i686 libstdc++.i686`.
- The standalone path is untested end to end.

## Locations
- Wine prefix: ~/.local/share/hyundai-nau-wine-prefix (app under `drive_c/Program Files (x86)/Navigation Updater/package/`)
- Proton prefix: ~/.local/share/hyundai-nau-prefix (same path under `pfx/`)

## Car workflow
1. In the car: export device info to a FAT32 USB stick (>= 32 GB) from the Update menu.
2. Plug the stick into the computer, open the updater (no login needed), let it download to the stick.
3. Put the stick back in the car, Ready mode (or charging), run the update. Don't interrupt.

## Gen5W cars (exFAT) and the manual copy
Gen5W head units (e.g. 2019-23 Kona Electric) need an **exFAT** stick. Wine cannot
report exFAT, so the updater tries to format the stick as NTFS and fails with a
write-protection error. Let it download only, then copy the package with the helper:

    ./copy-to-stick.sh                       # auto-detects the vehicle folder and the mounted exFAT stick (menu if several)
    ./copy-to-stick.sh /run/media/$USER/<stick> [<vehicle folder>]

Only exFAT mounts are offered; pass the mount point explicitly to override. It shows source, target and free space, asks for confirmation (`YES=1` skips it,
`DRY_RUN=1` only prints the plan), copies with `rsync` (or `cp`), runs `sync`, and
verifies the result with `diff`. Files already on the stick, such as the car's
device-info export, are left alone. By hand, the updater keeps the package in
`~/.local/share/hyundai-nau-prefix/pfx/drive_c/users/steamuser/Downloads/NaU/<vehicle folder>`:

    cp -rv "<vehicle folder>/." /run/media/$USER/<stick>/
    sync
    diff -rq "<vehicle folder>/" /run/media/$USER/<stick>/

The files go in the root of the stick, not a subfolder. This layout follows Hyundai's
FAQ and has not been verified in a car. Do not select a stick that holds data in the
updater's drive step, because it may try to format it.

## Troubleshooting
- Updater can't see the stick: on every launch the script links each mounted
  USB drive (`/run/media/$USER/*`, `/media/$USER/*`, only those udev reports as `ID_BUS=usb`; other mounts are skipped) to a free Wine drive letter
  from `e:` upward and prints e.g. `USB: /run/media/you/HYUNDAI -> e:`. Mount the stick
  **before** starting the updater; if you plug it in later, restart the updater. Other
  mount locations need a manual link. Wine reports linked folders as fixed disks, but the
  updater only offers *removable* drives, so the script also marks the letters `e:`-`y:`
  as removable in the prefix registry (once; marker file `~/.local/share/hyundai-nau-prefix/.usb-drive-types`).
  Wine's own auto-created `d:` stays a fixed disk and is ignored by the updater. To check:
  `wmic logicaldisk get caption,drivetype,volumename` in the prefix should show `2` for the stick.
  Manual link for other mount locations:
  `ln -s /mnt/stick ~/.local/share/hyundai-nau-prefix/pfx/dosdevices/e:`
- Window problems: try another Proton version by editing the script.
- Reset everything: delete the prefix folder and run the script again.
- Prepare a stick (erases it!): `lsblk`, then `sudo mkfs.vfat -F 32 -n HYUNDAI /dev/sdX1`
