#!/usr/bin/env bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALL_DIR="/opt/novin3dp-ts35"
USER_NAME="${SUDO_USER:-${USER}}"
USER_HOME="$(getent passwd "$USER_NAME" | cut -d: -f6)"
BACKUP_DIR="$USER_HOME/novin3dp-ts35-helix-backups/$(date +%Y%m%d-%H%M%S)"

log() { printf '\n[Novin3dp TS35 Helix] %s\n' "$*"; }
fail() { echo "ERROR: $*" >&2; exit 1; }

[[ "$(id -u)" -ne 0 ]] || fail "Run as a normal user, not root. sudo is used when required."
[[ -d /sys/firmware/devicetree/base ]] || fail "Device Tree is not available."
sudo -v

log "Checking target hardware"
if ! grep -qiE 'sun50i-h616|CB1|bigtreetech' /proc/device-tree/compatible 2>/dev/null; then
    echo "WARNING: this system does not look like the tested BTT CB1/H616 platform."
    read -r -p "Continue anyway? [y/N] " answer
    [[ "$answer" =~ ^[Yy]$ ]] || exit 1
fi

log "Installing TS35 runtime dependencies"
sudo apt-get update
sudo apt-get install -y device-tree-compiler python3-evdev python3-spidev curl git udev fbset

log "Preparing Novin3dp TS35 files"
sudo mkdir -p "$INSTALL_DIR/scripts" "$INSTALL_DIR/overlay"
sudo cp "$PROJECT_DIR/scripts/virtual_touch.py" "$INSTALL_DIR/scripts/virtual_touch.py"
sudo cp "$PROJECT_DIR/overlay/ts35_cb1.dts" "$INSTALL_DIR/overlay/ts35_cb1.dts"
sudo chmod 755 "$INSTALL_DIR/scripts/virtual_touch.py"

log "Backing up existing TS35-related configuration"
sudo mkdir -p "$BACKUP_DIR"
for f in /boot/armbianEnv.txt /etc/udev/rules.d/99-novin3dp-ts35-touch.rules; do
    if [[ -f "$f" ]]; then
        sudo cp -a "$f" "$BACKUP_DIR/$(basename "$f").bak"
    fi
done
printf '%s\n' "$BACKUP_DIR" | sudo tee "$INSTALL_DIR/last_backup" >/dev/null

log "Compiling Device Tree Overlay"
TMP_DTBO="$(mktemp --suffix=.dtbo)"
trap 'rm -f "$TMP_DTBO"' EXIT
dtc -@ -I dts -O dtb -o "$TMP_DTBO" "$INSTALL_DIR/overlay/ts35_cb1.dts"
sudo mkdir -p /boot/overlay-user
sudo cp "$TMP_DTBO" /boot/overlay-user/ts35_cb1.dtbo
sudo cp "$TMP_DTBO" "$INSTALL_DIR/overlay/ts35_cb1.dtbo"

log "Enabling TS35 Device Tree overlay"
[[ -f /boot/armbianEnv.txt ]] || fail "/boot/armbianEnv.txt not found. This installer targets Armbian/CB1."
if grep -q '^user_overlays=' /boot/armbianEnv.txt; then
    if ! grep -qE '^user_overlays=.*(^|[[:space:]])ts35_cb1([[:space:]]|$)' /boot/armbianEnv.txt; then
        sudo sed -i 's/^user_overlays=.*/& ts35_cb1/' /boot/armbianEnv.txt
    fi
else
    echo 'user_overlays=ts35_cb1' | sudo tee -a /boot/armbianEnv.txt >/dev/null
fi

log "Loading spidev and making it persistent"
sudo modprobe spidev || true
echo "spidev" | sudo tee /etc/modules-load.d/ts35-spidev.conf >/dev/null

log "Installing stable TS35 touch device rule"
sudo cp "$PROJECT_DIR/udev/99-novin3dp-ts35-touch.rules" /etc/udev/rules.d/99-novin3dp-ts35-touch.rules
sudo udevadm control --reload-rules
sudo udevadm trigger || true

log "Installing virtual touchscreen service"
sudo cp "$PROJECT_DIR/services/virtual-touch.service" /etc/systemd/system/virtual-touch.service

log "Installing HelixScreen"
if [[ -x "$USER_HOME/helixscreen/bin/helix-screen" ]]; then
    log "Existing HelixScreen detected; running official updater"
    curl -sSL https://releases.helixscreen.org/install.sh | sh -s -- --update
else
    curl -sSL https://releases.helixscreen.org/install.sh | sh
fi

log "Configuring HelixScreen for the TS35 framebuffer and touch"
HELIX_DIR="$USER_HOME/helixscreen"
[[ -d "$HELIX_DIR" ]] || HELIX_DIR="/opt/helixscreen"
[[ -d "$HELIX_DIR" ]] || fail "HelixScreen installation directory was not found."

HELIX_CONFIG="$HELIX_DIR/config/settings.json"
HELIX_ENV="$HELIX_DIR/config/helixscreen.env"
sudo mkdir -p "$HELIX_DIR/config"
sudo touch "$HELIX_ENV"

# HelixScreen renders directly to the framebuffer; X11/Xorg is intentionally not used.
if ! grep -q '^HELIX_DISPLAY_BACKEND=fbdev$' "$HELIX_ENV" 2>/dev/null; then
    echo 'HELIX_DISPLAY_BACKEND=fbdev' | sudo tee -a "$HELIX_ENV" >/dev/null
fi

# Use the stable udev symlink created for our uinput touchscreen.
if ! grep -q '^HELIX_TOUCH_DEVICE=' "$HELIX_ENV" 2>/dev/null; then
    echo 'HELIX_TOUCH_DEVICE=/dev/input/ts35-touch' | sudo tee -a "$HELIX_ENV" >/dev/null
fi

# HelixScreen's config schema documents input.touch_device. Preserve all existing settings.
if [[ -f "$HELIX_CONFIG" ]]; then
    sudo python3 - "$HELIX_CONFIG" <<'PY'
import json, sys
p=sys.argv[1]
with open(p, encoding="utf-8") as f:
    data=json.load(f)
data.setdefault("input", {})
data["input"]["touch_device"]="/dev/input/ts35-touch"
data.setdefault("display", {})
data["display"].setdefault("rotate", 0)
with open(p, "w", encoding="utf-8") as f:
    json.dump(data, f, indent=2)
    f.write("\n")
PY
fi

log "Adding HelixScreen Moonraker update manager entry"
MOONRAKER_CONF="$USER_HOME/printer_data/config/moonraker.conf"
if [[ -f "$MOONRAKER_CONF" ]] && ! grep -q '^[update_manager helixscreen]' "$MOONRAKER_CONF"; then
    cat >> "$MOONRAKER_CONF" <<EOF

[update_manager helixscreen]
type: web
channel: stable
repo: prestonbrown/helixscreen
path: $HELIX_DIR
EOF
fi

log "Installing services"
sudo systemctl daemon-reload
sudo systemctl enable virtual-touch.service

# HelixScreen normally disables competing UIs. Ensure the old UI cannot race
# with HelixScreen if it is still installed from the previous Novin3dp project.
sudo systemctl disable --now KlipperScreen.service 2>/dev/null || true
sudo systemctl stop virtual-touch.service 2>/dev/null || true

if [[ -e /dev/spidev0.2 ]]; then
    sudo systemctl start virtual-touch.service
fi

sudo systemctl restart helixscreen 2>/dev/null || sudo systemctl start helixscreen

sudo chown -R "$USER_NAME:$USER_NAME" "$HELIX_DIR/config" 2>/dev/null || true
sudo chown -R "$USER_NAME:$USER_NAME" "$INSTALL_DIR"

cat <<EOF

Installation completed.

HelixScreen:
  $HELIX_DIR

TS35 touch:
  /dev/input/ts35-touch
  Source: XPT2046 -> SPI1 CS2 -> spidev0.2 -> virtual uinput

Display:
  /dev/fb0
  Backend: fbdev

Backup:
  $BACKUP_DIR

A reboot is required to activate the Device Tree overlay:
  sudo reboot

After reboot:
  ls -l /dev/fb0 /dev/spidev0.2 /dev/input/ts35-touch
  systemctl status helixscreen --no-pager
  systemctl status virtual-touch.service --no-pager
  journalctl -u virtual-touch.service -n 50 --no-pager
EOF
