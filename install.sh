#!/usr/bin/env bash
set -euo pipefail
PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALL_DIR="/opt/novin3dp-ts35"
USER_NAME="${SUDO_USER:-${USER}}"
USER_HOME="$(getent passwd "$USER_NAME" | cut -d: -f6)"
FLAG_FILE="$USER_HOME/beeper_enabled"
BACKUP_DIR="$USER_HOME/novin3dp-ts35-backups/$(date +%Y%m%d-%H%M%S)"

log(){ printf '\n[Novin3dp TS35] %s\n' "$*"; }
fail(){ echo "ERROR: $*" >&2; exit 1; }
[[ "$(id -u)" -ne 0 ]] || fail "Run as a normal user, not root."
[[ -d /sys/firmware/devicetree/base ]] || fail "Device Tree is not available."
sudo -v

if [[ -d "$PROJECT_DIR/.git" ]]; then
  git -C "$PROJECT_DIR" fetch --quiet origin main 2>/dev/null || true
  LOCAL_HEAD="$(git -C "$PROJECT_DIR" rev-parse HEAD 2>/dev/null || true)"
  REMOTE_HEAD="$(git -C "$PROJECT_DIR" rev-parse origin/main 2>/dev/null || true)"
  if [[ -n "$LOCAL_HEAD" && -n "$REMOTE_HEAD" && "$LOCAL_HEAD" != "$REMOTE_HEAD" ]]; then
    echo "WARNING: local checkout is behind origin/main."
    read -r -p "Continue with this local copy? [y/N] " REPLY
    [[ "$REPLY" =~ ^[Yy]$ ]] || fail "Aborted. Run git pull and retry."
  fi
fi

log "Installing dependencies"
sudo apt-get update
sudo apt-get install -y device-tree-compiler python3-evdev python3-spidev git curl
sudo modprobe spidev || true
echo spidev | sudo tee /etc/modules-load.d/ts35-spidev.conf >/dev/null

log "Installing project files"
sudo mkdir -p "$INSTALL_DIR/scripts" "$INSTALL_DIR/overlay"
sudo cp "$PROJECT_DIR/scripts/virtual_touch.py" "$INSTALL_DIR/scripts/"
sudo cp "$PROJECT_DIR/scripts/beeper_watcher.py" "$INSTALL_DIR/scripts/"
sudo cp "$PROJECT_DIR/overlay/ts35_cb1.dts" "$INSTALL_DIR/overlay/"
sudo chmod 755 "$INSTALL_DIR/scripts/"*.py

sudo mkdir -p "$BACKUP_DIR"
for f in /boot/armbianEnv.txt /etc/X11/xorg.conf.d/99-ts35-fbdev.conf "$USER_HOME/printer_data/config/printer.cfg"; do
  [[ -f "$f" ]] && sudo cp -a "$f" "$BACKUP_DIR/$(basename "$f").bak"
done
printf '%s\n' "$BACKUP_DIR" | sudo tee "$INSTALL_DIR/last_backup" >/dev/null

log "Compiling Device Tree Overlay"
TMP_DTBO="$(mktemp --suffix=.dtbo)"
trap 'rm -f "$TMP_DTBO"' EXIT
dtc -@ -I dts -O dtb -o "$TMP_DTBO" "$INSTALL_DIR/overlay/ts35_cb1.dts"
sudo mkdir -p /boot/overlay-user
sudo cp "$TMP_DTBO" /boot/overlay-user/ts35_cb1.dtbo
sudo cp "$TMP_DTBO" "$INSTALL_DIR/overlay/ts35_cb1.dtbo"

if grep -q '^user_overlays=' /boot/armbianEnv.txt; then
  grep -qE '^user_overlays=.*(^|[[:space:]])ts35_cb1([[:space:]]|$)' /boot/armbianEnv.txt || sudo sed -i 's/^user_overlays=.*/& ts35_cb1/' /boot/armbianEnv.txt
else
  echo 'user_overlays=ts35_cb1' | sudo tee -a /boot/armbianEnv.txt >/dev/null
fi

log "Installing HelixScreen"
# HelixScreen is the only touchscreen UI installed by this project.
# Its official installer detects the platform, installs the correct release,
# configures the systemd service, and disables competing touchscreen UIs.
curl -fsSL https://releases.helixscreen.org/install.sh | sh

sed -e "s#__TS35_BEEPER_FLAG__#$FLAG_FILE#g" "$PROJECT_DIR/services/virtual-touch.service" | sudo tee /etc/systemd/system/virtual-touch.service >/dev/null
sed -e "s#__TS35_USER__#$USER_NAME#g" -e "s#__TS35_BEEPER_FLAG__#$FLAG_FILE#g" "$PROJECT_DIR/services/beeper-watcher.service" | sudo tee /etc/systemd/system/beeper-watcher.service >/dev/null
sudo chown -R "$USER_NAME:$USER_NAME" "$INSTALL_DIR"
printf '1\n' | sudo tee "$FLAG_FILE" >/dev/null
sudo chown "$USER_NAME:$USER_NAME" "$FLAG_FILE"

PRINTER_CFG="$USER_HOME/printer_data/config/printer.cfg"
if [[ -f "$PRINTER_CFG" ]] && ! grep -q '^\[gcode_macro TOGGLE_BEEPER\]' "$PRINTER_CFG"; then
  printf '\n' | sudo tee -a "$PRINTER_CFG" >/dev/null
  sudo tee -a "$PRINTER_CFG" < "$PROJECT_DIR/klipper/toggle_beeper.cfg" >/dev/null
  sudo chown "$USER_NAME:$USER_NAME" "$PRINTER_CFG"
fi

sudo systemctl daemon-reload
sudo systemctl enable virtual-touch.service beeper-watcher.service
sudo systemctl restart beeper-watcher.service
[[ -e /dev/spidev0.2 ]] && sudo systemctl restart virtual-touch.service || true

cat <<EOF

Installation completed.
Backup: $BACKUP_DIR
A reboot is required to activate the Device Tree overlay:
  sudo reboot
EOF
