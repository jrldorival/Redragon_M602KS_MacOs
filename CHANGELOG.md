# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project follows [Semantic Versioning](https://semver.org/).

## [1.1.0] - 2026-10-24

### Added

- English interface. The app follows the macOS language: English by default, Brazilian Portuguese when macOS is set to Portuguese.
- Standard macOS localization files (`Localization/<language>.lproj/Localizable.strings`), so new languages can be added without changing the code.

### Changed

- `build.sh` and `criar-certificado.sh` print their messages in English.

## [1.0.0] - 2026-10-24

First public release.

### Added

- Menu bar battery indicator for the Redragon M602-KS: a battery icon that fills with the charge, plus the percentage, refreshed every 60 seconds, on connect and disconnect, and on demand.
- Median of the last 5 readings to smooth the small variations reported by the mouse.
- Charging state on the USB cable (the mouse does not report the percentage while charging).
- Settings window: polling rate (125 to 1000 Hz), 1 to 5 DPI levels (250 to 8000 DPI) with their colors, lighting effect with speed, brightness, direction and color.
- Safe settings writes: device identity check, automatic backup, read-back verification, and restore from any backup.
- Button assignment window for the 7 programmable buttons, including keyboard shortcuts and the factory layout.
- Local code signing certificate script, so the Input Monitoring permission survives rebuilds.
- App icon, and the app version shown in the menu.
- Documentation of the HID protocol (battery, identification, settings block, buttons).

[1.1.0]: https://github.com/jrldorival/Redragon_M602KS_MacOs/releases/tag/v1.1.0
[1.0.0]: https://github.com/jrldorival/Redragon_M602KS_MacOs/releases/tag/v1.0.0
