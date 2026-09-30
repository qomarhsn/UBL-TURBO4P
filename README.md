# TURBO 4 PRO · Bootloader Unlock (UBL)

Cross-platform (Linux / Windows) tool for unofficial bootloader unlock on **Redmi Turbo 4 Pro (onyx)** running Chinese HyperOS.

| Platform | Script | Run with |
|----------|--------|----------|
| Linux / macOS | `unlock.sh` | bash |
| Windows | `unlock.ps1` | PowerShell (via `unlock.bat`) |

## Requirements

- `adb` and `fastboot` in PATH, USB debugging enabled, phone connected via USB
  - **Linux**: install from your distro's repos — e.g. `sudo pacman -S android-tools` / `sudo apt install adb fastboot` / `sudo dnf install android-tools`
  - **Windows**: `winget install Google.PlatformTools` (reopen the terminal afterwards so PATH updates), or manually from [Google platform-tools](https://developer.android.com/tools/releases/platform-tools)
- Device booted to Android (version detected via ADB)

## What it does

1. Detects HyperOS version via ADB (`ro.mi.os.version.name`)
2. **Refuses** to run on HOS >= 3.0.305 (exploit patched after June 2026)
3. Chooses the correct method:
   - **SERVICE** (HOS <= 3.0.11): sets permissive flag via fastboot, resumes boot (`fastboot continue`, falls back to `fastboot reboot` if unsupported), uses MQSAS service call to flash engineering ABL, then GPT unlock trick + temp boot
   - **PRELOAD** (HOS 3.0.12 – 3.0.304): uses `LD_PRELOAD` root exploit to flash engineering ABL via dd, then GPT unlock trick + temp boot
4. Verifies unlock status with `fastboot getvar unlocked`
5. Optionally restores stock GPT

Safety behavior on both platforms: every step asks for confirmation, a failed step aborts the whole flow instead of continuing, and `fastboot wait` checks actually wait for the phone.

## Version support

| HOS version | Method | Status |
|-------------|--------|--------|
| <= 3.0.11 | SERVICE | Supported |
| 3.0.12 – 3.0.304 | PRELOAD | Supported |
| >= 3.0.305 | — | This tool will not work — exploit is patched |

## Usage

### Linux

```bash
git clone https://github.com/qomarhsn/UBL-TURBO4P.git
cd UBL-TURBO4P
chmod +x unlock.sh
./unlock.sh
```

### Windows

No install needed — double-click `unlock.bat`, or from cmd / PowerShell:

```bat
unlock.bat
```

`unlock.bat` is a thin wrapper that runs `unlock.ps1` with the right execution policy (uses `pwsh` if installed, otherwise built-in Windows PowerShell). PowerShell users can also call it directly — the bypass flag is needed because Windows ships with script execution disabled by default:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\unlock.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File .\unlock.ps1 -Preload -DryRun
```

### Options

Flags differ per platform but have the same meaning. Both support a dry-run mode — **use it first** to preview every command without touching the phone.

| Effect | Linux (`unlock.sh`) | Windows (`unlock.ps1`) |
|--------|---------------------|------------------------|
| Force SERVICE method (skip version detect) | `-s` / `--service` | `-Service` |
| Force PRELOAD method (skip version detect) | `-p` / `--preload` | `-Preload` |
| Skip confirmation prompts | `-a` / `--auto` | `-Auto` |
| Print commands without executing | `-n` / `--dry-run` | `-DryRun` |
| Show usage | — | `-Help` |

Each run writes a log (`unlock_log_*.txt`) next to the script — attach it when reporting bugs.

## Unlock files

Included in this directory (from the original kit):

| File | Purpose |
|------|---------|
| `abl.elf` | Engineering ABL (both methods) |
| `preload.so` | LD_PRELOAD root exploit (PRELOAD method only) |
| `onyx_gpt_both4.bin` | Unlock GPT image |
| `gpt_both4.bin` | Stock GPT image (restore after unlock) |
| `bonito.img` | Temp boot image for GPT unlock step |

## Bug reports

Open an issue with this [bug report template](.github/ISSUE_TEMPLATE/bug_report.yml). Write the title and description and attach the log file (`unlock_log_*.txt`) from the script folder. That's it.

## Credits

- **@Littlenine** — creator of the exploit

## License

No license file is included. This wrapper script is provided as-is for educational purposes. The underlying exploit and unlock files belong to @Littlenine.
