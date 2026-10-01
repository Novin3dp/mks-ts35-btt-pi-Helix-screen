# HelixScreen (اختیاری)

HelixScreen can be used as an alternative UI to KlipperScreen. The virtual touchscreen created by `scripts/virtual_touch.py` is exposed through standard Linux evdev/uinput and can be detected by HelixScreen.

## Install

```bash
curl -sSL https://raw.githubusercontent.com/prestonbrown/helixscreen/main/scripts/install.sh | sh
```

KlipperScreen and HelixScreen should not be run simultaneously.

## Verify touch

```bash
ls /dev/input/event*
cat /proc/bus/input/devices | grep -A5 ADS7846
sudo systemctl status helixscreen
```

## Return to KlipperScreen

```bash
curl -sSL https://raw.githubusercontent.com/prestonbrown/helixscreen/main/scripts/install.sh | sh -s -- --uninstall
```

Klipper configuration is not removed by the HelixScreen installer.
