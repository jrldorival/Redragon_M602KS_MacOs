# Redragon Battery for macOS

A macOS menu bar app for the **Redragon M602-KS (Griffin)** wireless mouse. It shows the battery level and lets you change the mouse settings that the official software only allows on Windows: DPI levels and colors, polling rate, lighting effects and button assignments.

**Version:** 1.0.0 · see [CHANGELOG.md](CHANGELOG.md)

> [!WARNING]
> **Unofficial project. Use at your own risk.** This app is not affiliated with, endorsed by or supported by Redragon. It writes settings directly to the mouse. Read the [Disclaimer](#disclaimer) before using it.

## Features

- **Battery level in the menu bar**: a battery icon that fills according to the charge, followed by the percentage. It refreshes every 60 seconds, whenever the receiver or the cable is connected or disconnected, and on demand.
- **Mouse settings** (window "Configurações do mouse…"):
  - polling rate: 125, 250, 500 or 1000 Hz;
  - 1 to 5 DPI levels, from 250 to 8000 DPI, each with its own color;
  - lighting effect, with speed, brightness, direction and color where the effect supports them, or lights off.
- **Safe writes**: before writing, the app checks that the device identifies itself as an M602-KS and saves a backup of the current settings. After writing, it reads the settings back to confirm them. Any backup can be restored.
- **Button assignments** (window "Botões do mouse…"): left, right and middle click, back, forward, scroll up and down, DPI up and down, or a keyboard shortcut (⌃ ⇧ ⌥ ⌘ + one key) for each of the 7 programmable buttons, plus a factory-default option.

The app interface is in Brazilian Portuguese.

## Requirements

- macOS 11 (Big Sur) or later.
- Xcode Command Line Tools, used to compile the app. You do not need the full Xcode.
- A Redragon M602-KS connected through its 2.4 GHz USB receiver or the USB cable. Bluetooth was not tested.

Tested on one Mac with one M602-KS using the 2.4 GHz receiver (USB PID `0x002F`).

## Installation

The app is distributed as source code and compiled on your Mac, which takes about a minute.

### 1. Install the Command Line Tools

Open **Terminal** and check whether Swift is available:

```bash
swift --version
```

If it is not installed, run the command below, confirm the dialog and wait for the installation to finish:

```bash
xcode-select --install
```

### 2. Download the project

Clone it with Git:

```bash
git clone https://github.com/jrldorival/Redragon_M602KS_MacOs.git
cd Redragon_M602KS_MacOs
```

Or download it from GitHub (**Code › Download ZIP**), unzip it, and open Terminal in that folder.

### 3. Create the local signing certificate (once)

```bash
bash criar-certificado.sh
```

This creates a self-signed code signing certificate named **"Redragon Battery Local"** in your login keychain, valid for 10 years, and asks for your password to trust it for code signing. macOS ties the Input Monitoring permission (step 6) to the app signature, so signing every build with the same certificate keeps the permission when you rebuild. You only need to do this once per Mac.

### 4. Build

```bash
bash build.sh
```

The last lines should show `Pronto: …/RedragonBattery.app (versão 1.0.0)` and `Authority=Redragon Battery Local`. If a dialog asks whether `codesign` may use the keychain key, enter your password and choose **Always Allow**.

### 5. Install

```bash
cp -R RedragonBattery.app /Applications/
open /Applications/RedragonBattery.app
```

To start it automatically, add it to **System Settings › General › Login Items**.

### 6. Allow Input Monitoring

On the first launch, macOS asks for **Input Monitoring** permission. Allow it, then quit the app (menu › Sair) and open it again. The permission is required because the mouse receiver also presents itself as a keyboard, which is used for the mouse macros.

If the menu shows "Sem permissão de Monitoramento de Entrada" or "SetFeature falhou (0xE00002CD)", the permission does not match the current signature. Reset it and open the app again:

```bash
tccutil reset ListenEvent local.redragon-battery
open /Applications/RedragonBattery.app
```

### Updating

Download the new version, then build and replace the app:

```bash
bash build.sh
rm -rf /Applications/RedragonBattery.app
cp -R RedragonBattery.app /Applications/
open /Applications/RedragonBattery.app
```

With the certificate from step 3 the permission is kept. If the app icon does not update in Spotlight, restart the Mac.

### Uninstalling

```bash
rm -rf /Applications/RedragonBattery.app
tccutil reset ListenEvent local.redragon-battery
```

Optionally:

- delete the settings backups with `rm -rf ~/Library/Application\ Support/RedragonBattery` (you will no longer be able to restore them);
- open **Keychain Access**, search for "Redragon Battery Local" and delete the certificate and its private key.

## Usage

Click the mouse icon in the menu bar.

| Menu item | What it does |
|---|---|
| Atualizar agora | Reads the battery now. |
| Configurações do mouse… | Polling rate, DPI levels and colors, lighting effect. **Aplicar** writes and verifies; **Restaurar backup…** restores a saved backup. |
| Botões do mouse… | Function of each programmable button. **Padrão de fábrica** loads the factory layout; **Gravar no mouse** writes it. |
| Salvar backup da configuração… | Reads the mouse settings and saves a backup without changing anything. |
| Abrir Monitoramento de Entrada… | Opens the Input Monitoring page in System Settings. |

Backups are saved in `~/Library/Application Support/RedragonBattery/`. Use the `general-<date>.bin` files to restore; the `.txt` files with the same name are the same data, readable as text.

The battery level the mouse reports varies by a few points from one reading to the next (for example 37 → 39 → 37), so the menu bar shows the median of the last 5 readings.

## Known limitations

- **No battery level while charging.** On the cable, the mouse reports "cable" without a percentage, and the receiver keeps repeating the last wireless value, which stays the same while the mouse charges. The official software behaves the same way. The menu shows a charging icon and the last wireless value.
- **A mouse that is turned off is not detected.** The receiver keeps answering with the last known value.
- **Button assignments cannot be read from the mouse.** The hardware has no read command for them, so there is no backup of the previous state and no verification after writing. The app remembers what it wrote last (`botoes.json`), and **Padrão de fábrica** restores the original layout. Like the official software, it refuses to write a layout without a left click.
- **Macros are not supported.** The write command is known, but the macro data format was not decoded. Keyboard shortcuts cover the common cases.
- DPI values above 4000 follow the same conversion as the factory values but were not tested on the mouse.
- The LED switch and the Bluetooth button under the mouse are hardware controls and cannot be changed by software.

## Disclaimer

This is an independent, unofficial project. It is not affiliated with, endorsed by, sponsored by or supported by Redragon or any of its partners. "Redragon" and "Griffin" are trademarks of their respective owners and are used here only to identify the compatible device.

The communication protocol was obtained by studying how the official Windows software talks to the mouse, for the sole purpose of interoperability with macOS. No code from the official software is included in this repository.

This app writes settings directly to the mouse's memory. It checks the device identity, keeps backups and reads settings back where the hardware allows it, but a wrong or interrupted write may still leave the mouse misconfigured. Button assignments cannot be read back at all.

**This software is provided "as is", without warranty of any kind. The author is not responsible for any damage, malfunction, data loss, loss of warranty, or any misuse resulting from the use of this software. By using it, you accept full responsibility for its use.** See also the [LICENSE](LICENSE).

## Versioning

The project follows [Semantic Versioning](https://semver.org/). The version number lives in the `VERSION` file; `build.sh` writes it into the app, and it appears at the bottom of the app menu. Every release is described in [CHANGELOG.md](CHANGELOG.md) and tagged in Git as `v<version>`.

## Project files

| File | Purpose |
|---|---|
| `main.swift` | Menu bar app, battery reading, HID communication, backups. |
| `Settings.swift` | Settings window (polling rate, DPI, lighting). |
| `Buttons.swift` | Button assignment window. |
| `build.sh` | Compiles, generates the icon, signs and creates `RedragonBattery.app`. |
| `criar-certificado.sh` | Creates the local signing certificate (once). |
| `icon.png` | App icon source (1024 × 1024). |
| `VERSION` | Current version. |

## Protocol

For anyone who wants to build on this work. Everything below was obtained from the official Windows software (`OemDrv.exe` v1.0 and `Lowerdev.dll`, internally called HidParse) and confirmed on a real mouse where noted.

### Device

| Item | Value |
|---|---|
| USB IDs | VID `0x258A`, PID `0x002F` (2.4 GHz receiver) and `0x002E` (mouse on the cable) |
| HID collection | Usage page `0xFF00`, usage `0x01` |
| Command report | Feature report ID 5, 8 bytes: `05 <command> 00 00 00 00 00 00` |
| Data report | Feature report ID 8, 520 bytes |
| Mode | The official software selects a mode from the PID: `0x002E` → 1, `0x002F` → 2. Commands below use `0x1_` in mode 1 and `0x2_` in mode 2. |

### Battery (command `0x90`)

Send `05 90 00 00 00 00 00 00` and read feature report 5 about 20 ms later.

| Byte | Meaning |
|---|---|
| 1 | `0x90` (echo of the command) |
| 2 | `0x10` = on the cable, `0x11` = wireless |
| 3 | battery percentage when wireless; `0x01` on the cable |

Real responses: `05 90 11 26 00 00 00 00` (wireless, 38%) and `05 90 10 01 00 00 00 00` (cable).

### Identification (command `0x01`)

The response carries `32 38 38 30` ("2880") in bytes 2–5, which the official software compares with the `PSD` value of its `Cfg.ini` before writing anything.

### Settings block ("General", 146 bytes)

- **Read:** command `0x11` (mode 1) or `0x21` (mode 2) on report 5. The answer comes in report 8: `08 <command> 00 00 00 00 00 00` followed by the 146 bytes.
- **Write:** report 8 = `08 <command> 00 92 00 00 00 00` + 146 bytes, using the same command as the read.

| Byte | Content |
|---|---|
| 0 | `0x64` (fixed) |
| 1 | `0x13` on the tested mouse; not changed by the official software |
| 2 | low nibble: polling rate (1 = 125, 2 = 250, 3 = 500, 4 = 1000 Hz); bit 7: independent X/Y DPI |
| 3 | high nibble: active DPI level (from 1); low nibble: number of DPI levels |
| 5–20 | 8 DPI slots for the X axis, 2 bytes each, little endian; code = DPI ÷ 250 (factory: 2, 4, 8, 12, 16) |
| 21–36 | same for the Y axis, used only with independent X/Y |
| 37–60 | RGB color of each active DPI level, in sequence |
| 61 | lighting effect: 1 Colorful Streaming, 2 Steady, 3 Breathing, 4 Colorful Tail, 5 Neon, 6 Colorful Steady, 7 Flicker, 8 Stars Twinkle, 9 Wave, 0 off |
| 62, 64, 68, 91, 92, 93, 124, 131, 132, 133 | one parameter byte per effect (effects 1–9 and off): high nibble = brightness (1–4), low nibble = speed (1–3) |
| 63 | Colorful Streaming direction (0 or 1) |
| 65–67 | Steady color (RGB) |
| 69, 70… | Breathing: number of colors, then the colors |
| 94… | Colorful Steady colors |
| 144 | `0xA5` (fixed) |

Factory values read from the tested mouse: 500 Hz; 5 levels of 500, 1000, 2000, 3000 and 4000 DPI with red, blue, green, purple and yellow; Colorful Streaming. Brightness and speed ranges come from the official lighting window (4 and 3 positions) and match the factory values (brightness 4, speed 2). Confirmed on the mouse: speed 3 is the fastest and brightness 4 the brightest. Which controls each effect offers follows `LedOpt1`…`LedOpt10` in the official `Cfg.ini`.

### Buttons (write only)

Report 8 = `08 <command + 1> 00 50 00 00 00 00` + 20 slots × 4 bytes + `A5`, where the command is the one of the settings block (`0x12` in mode 1, `0x22` in mode 2). There is no read command. Unused slots are `50 01 00 00`. The slot of each physical button comes from the 4th value of the `K<n>_1` keys in the official `Cfg.ini`.

| Slot | Factory function | Code |
|---|---|---|
| 1 | left click | `11 01 00 00` |
| 2 | right click | `11 02 00 00` |
| 3 | middle click | `11 04 00 00` |
| 4 | back | `11 08 00 00` |
| 5 | forward | `11 10 00 00` |
| 6 | top button near the wheel: DPI up | `41 01 00 00` |
| 7 | top button behind it: DPI down | `41 02 00 00` |
| 8 | (no physical button identified) | `50 04 00 00` |
| 9–20 | unused | `50 01 00 00` |

Other codes: `12 01` / `12 FF` scroll up and down; keyboard shortcut `21 <modifiers> <key> 00`, with the modifiers byte in HID order (⌃ `0x01`, ⇧ `0x02`, ⌥ `0x04`, ⌘ `0x08`) and the key as a HID usage code. The official software also produces `41 00`, `50 02`, `50 06`, `50 07` and `31 01 32 02/03`, whose functions were not confirmed.

### Macros (not implemented)

Written through report 8 with command `0x30`, in 510-byte packets. The content format was not decoded.

## License

[MIT](LICENSE). Free to use, modify and share, with no warranty.
