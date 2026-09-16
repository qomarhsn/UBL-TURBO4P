# TURBO 4 PRO · Bootloader Unlock (UBL)

Single-script Linux tool for unofficial bootloader unlock on **Redmi Turbo 4 Pro (onyx)** running Chinese HyperOS.

## Requirements

- Linux with `adb` and `fastboot` (system `android-tools`)
- USB debugging enabled, phone connected via USB
- Device booted to Android (version detected via ADB)

## What it does

1. Detects HyperOS version via ADB (`ro.mi.os.version.name`)
2. **Refuses** to run on HOS >= 3.0.305 (exploit patched after June 2026)
3. Chooses the correct method:
   - **SERVICE** (HOS <= 3.0.11): sets permissive flag via fastboot, reboots, uses MQSAS service call to flash engineering ABL, then GPT unlock trick + temp boot
   - **PRELOAD** (HOS 3.0.12 – 3.0.304): uses `LD_PRELOAD` root exploit to flash engineering ABL via dd, then GPT unlock trick + temp boot
4. Verifies unlock status with `fastboot getvar unlocked`
5. Optionally restores stock GPT

## Version support

| HOS version | Method | Status |
|-------------|--------|--------|
| <= 3.0.11 | SERVICE | Supported |
| 3.0.12 – 3.0.304 | PRELOAD | Supported |
| >= 3.0.305 | — | This tool will not work — exploit is patched |

## Usage

```bash
git clone https://github.com/qomarhsn/UBL-TURBO4P.git
cd UBL-TURBO4P
chmod +x unlock.sh
./unlock.sh
```

### Options

| Flag | Effect |
|------|--------|
| `-s` / `--service` | Force SERVICE method (skip version detect) |
| `-p` / `--preload` | Force PRELOAD method (skip version detect) |
| `-a` / `--auto` | Skip confirmation prompts |
| `-n` / `--dry-run` | Print commands without executing |

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
