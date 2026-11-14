# Hyundai Navigation Updater on Linux (Proton)

> **Disclaimer: unofficial and unsupported.** This project is not affiliated with,
> endorsed by, or supported by Hyundai. It runs Hyundai's Windows-only Navigation
> Updater under Proton/Wine, which Hyundai does not support. Updating a vehicle's
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
- `DRY_RUN=1 ./run-navigation-updater.sh` prints the steps without doing anything.
- If the checksum no longer matches (Hyundai published a new version), the script
  stops. Inspect the `.part` file, then re-run with `SKIP_CHECKSUM=1` to accept it.

## Installer source
- URL: https://oem-setup.map-care.com/update_program_download/nau_client/crossplatform/test/install/NavigationUpdaterInstaller.exe
  (found in the site config of update.hyundai.com/EU/EN; the website's own download
  button may not work. This link may change or break without notice.)
- Pinned SHA-256: 307f5a66f524bb8585fedebb37ac7a077dcf6b67fef8789995d714de598324cd

## Proton
The script looks for Proton Experimental in Steam (native or Flatpak). If none is
found, it downloads its own copy with `steamcmd` (anonymous login, no Steam account
needed) into `~/.local/share/hyundai-nau-proton`.
- `steamcmd` is 32-bit; on Fedora you may need `sudo dnf install glibc.i686 libstdc++.i686`.
- The standalone path is untested end to end.

## Locations
- Prefix: ~/.local/share/hyundai-nau-prefix
- App: ~/.local/share/hyundai-nau-prefix/pfx/drive_c/Program Files (x86)/Navigation Updater/package/

## Car workflow
1. In the car: export device info to a FAT32 USB stick (>= 32 GB) from the Update menu.
2. Plug the stick into the computer, log in to the updater, let it download to the stick.
3. Put the stick back in the car, Ready mode (or charging), run the update. Don't interrupt.

## Troubleshooting
- Updater can't see the stick: add a Wine drive symlink, e.g.
  `ln -s /run/media/$USER/HYUNDAI ~/.local/share/hyundai-nau-prefix/pfx/dosdevices/e:`
- Window problems: try another Proton version by editing the script.
- Reset everything: delete the prefix folder and run the script again.
- Prepare a stick (erases it!): `lsblk`, then `sudo mkfs.vfat -F 32 -n HYUNDAI /dev/sdX1`
