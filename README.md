# Unofficial ReVanced Desktop Installer Script

This is a PowerShell script that is able to install/update some apps with ReVanced patches on devices connected to the PC with USB debugging enabled.

This does not install anything to your PC aside from ReVanced files necessary for patching.

## Features

- Will download the latest versions of the following each time the script is ran:
  - [ReVanced Patches](https://github.com/revanced/revanced-patches)
  - [ReVanced Integrations](https://github.com/revanced/revanced-integrations)
  - [ReVanced Manager](https://github.com/revanced/revanced-manager)
  - [ReVanced CLI](https://github.com/revanced/revanced-cli)
- Supports installing/updating the following apps on any connected device:
  - ReVanced Manager
  - YouTube
  - YouTube Music
  - Citra

## Dependencies

The script is dependent on only 1 PowerShell module, that being [PSWriteColor](https://www.powershellgallery.com/packages/PSWriteColor). If it hasn't already been installed, the script will ask if it's OK to install it for you.

You'll also need to have `adb.exe` in the same folder as the script files.

## Usage

First, download the script's `ps1` and `bat` files to it's own folder.

To run the script, double click on the `bat` file.

You are able to provide names for the IDs of devices detected with ADB. Put these names in a file named `revanced-desktop-installer.conf` in the same folder as the script files, where each line is setup like so: `DEVICEID=Device name, any characters are allowed`.

This script does **not** download APK files for any of the patchable apps, eg. YouTube. You will have to do that yourself.

If an APK file you downloaded to patch isn't detected by the script, the APK file must have the app's name and it's version number in it's name. For example: `app_name_12.34.56.78.apk`
