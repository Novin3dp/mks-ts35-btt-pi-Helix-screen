#!/usr/bin/env bash
set -euo pipefail

REPO_URL="https://github.com/Novin3dp/mks-ts35-helixscreen.git"
PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALL_DIR="/opt/novin3dp-ts35-helix"
USER_NAME="${SUDO_USER:-${USER}}"
USER_HOME="$(getent passwd "$USER_NAME" | cut -d: -f6)"
FLAG_FILE="$USER_HOME/beeper_enabled"
BACKUP_DIR="$USER_HOME/novin3dp-ts35-helix-backups/$(date +%Y%m%d-%H%M%S)"
BEEPER_HARDWARE="${TS35_BEEPER_HARDWARE:-1}"

log() { printf '\n[Novin3dp TS35/HelixScreen] %s\n' "$*"; }
fail() { echo "ERROR: $*" >&2; exit 1; }

[[ "$(id -u)" -ne 0 ]] || fail "Run as a normal user, not root. sudo is used when required."
[[ -d /sys/firmware/devicetree/base ]] || fail "Device Tree is not available."
sudo -v

log "Checking target hardware"
if ! grep -qiE 'sun50i-h616|CB1|bigtreetech' /proc/device-tree/compatible 2>/dev/null; then
    echo "WARNING: this system does not look like the tested CB1/H616 platform."
    read -r -p "Continue anyway? [y/N] " answer
    [[ "$answer" =~ ^[Yy]$ ]] || exit 1
fi

# Guard against reinstalling from a stale local clone: if this directory is a
# git checkout, make sure it is not behind the GitHub repo before copying
# files from it. This has previously caused an old script (missing
# calibration flags) to silently get reinstalled after a "git pull" was
# skipped.
if [[ -d "$PROJECT_DIR/.git" ]] && command -v git >/dev/null 2>&1; then
    log "Checking that this local checkout is up to date"
    if git -C "$PROJECT_DIR" fetch --quiet origin main 2>/dev/null; then
        LOCAL_HEAD="$(git -C "$PROJECT_DIR" rev-parse HEAD 2>/dev/null || echo local)"
        REMOTE_HEAD="$(git -C "$PROJECT_DIR" rev-parse origin/main 2>/dev/null || echo remote)"
        if [[ "$LOCAL_HEAD" != "$REMOTE_HEAD" ]]; then
            echo "WARNING: your local clone is behind origin/main."
            echo "  Run 'git pull' in $PROJECT_DIR before installing, or you may"
            echo "  install an outdated version of the touch driver."
            read -r -p "Continue anyway with the local copy? [y/N] " answer
            [[ "$answer" =~ ^[Yy]$ ]] || exit 1
        fi
    fi
fi

if [[ -z "${TS35_BEEPER_HARDWARE:-}" ]]; then
    echo
    read -r -p "Do you have the optional touch beeper wired to GPIO70/PC6? [y/N] " beeper_answer
    if [[ "$beeper_answer" =~ ^[Yy]$ ]]; then
        BEEPER_HARDWARE="1"
    else
        BEEPER_HARDWARE="0"
    fi
fi

log "Installing dependencies"
sudo apt-get update
sudo apt-get install -y device-tree-compiler python3-evdev python3-spidev git curl

log "Ensuring spidev kernel module is loaded"
# On some fresh Armbian images the spidev module is not auto-loaded at boot,
# which silently prevents /dev/spidev0.2 from ever appearing (touch never
# starts, even though the overlay and service are otherwise correct).
sudo modprobe spidev || true
if [[ ! -f /etc/modules-load.d/ts35-spidev.conf ]]; then
    echo "spidev" | sudo tee /etc/modules-load.d/ts35-spidev.conf >/dev/null
fi

log "Preparing project files"
sudo mkdir -p "$INSTALL_DIR/scripts" "$INSTALL_DIR/overlay"
sudo cp "$PROJECT_DIR/scripts/virtual_touch.py" "$INSTALL_DIR/scripts/"
sudo cp "$PROJECT_DIR/scripts/beeper_watcher.py" "$INSTALL_DIR/scripts/"
sudo cp "$PROJECT_DIR/overlay/ts35_cb1.dts" "$INSTALL_DIR/overlay/"
sudo chmod 755 "$INSTALL_DIR/scripts/"*.py

log "Backing up existing configuration"
sudo mkdir -p "$BACKUP_DIR"
for f in /boot/armbianEnv.txt \
         "$USER_HOME/printer_data/config/printer.cfg"; do
    if [[ -f "$f" ]]; then
        sudo cp -a "$f" "$BACKUP_DIR/$(basename "$f").bak"
    fi
done
printf '%s\n' "$BACKUP_DIR" | sudo tee "$INSTALL_DIR/last_backup" >/dev/null

log "Compiling Device Tree Overlay"
# /opt is root-owned; compile to a temporary user-writable path, then install with sudo.
TMP_DTBO="$(mktemp --suffix=.dtbo)"
trap 'rm -f "$TMP_DTBO"' EXIT
dtc -@ -I dts -O dtb -o "$TMP_DTBO" "$INSTALL_DIR/overlay/ts35_cb1.dts"
sudo mkdir -p /boot/overlay-user
sudo cp "$TMP_DTBO" /boot/overlay-user/ts35_cb1.dtbo
sudo cp "$TMP_DTBO" "$INSTALL_DIR/overlay/ts35_cb1.dtbo"

log "Enabling TS35 overlay"
[[ -f /boot/armbianEnv.txt ]] || fail "/boot/armbianEnv.txt not found. This installer targets Armbian/CB1."
if grep -q '^user_overlays=' /boot/armbianEnv.txt; then
    if ! grep -qE '^user_overlays=.*(^|[[:space:]])ts35_cb1([[:space:]]|$)' /boot/armbianEnv.txt; then
        sudo sed -i 's/^user_overlays=.*/& ts35_cb1/' /boot/armbianEnv.txt
    fi
else
    echo 'user_overlays=ts35_cb1' | sudo tee -a /boot/armbianEnv.txt >/dev/null
fi

log "Removing legacy touchscreen calibration files (if any)"
# Leftover from older X11/KlipperScreen setups: if an evdev "Calibration"
# InputClass for "ADS7846 Touchscreen" exists, it would double-apply a
# transform on top of the one already done in virtual_touch.py. HelixScreen
# itself does not use Xorg, but we still clean this up in case the same
# machine previously ran a KlipperScreen/X11-based install of this project.
for f in /usr/share/X11/xorg.conf.d/99-touch-evdev.conf /etc/X11/xorg.conf.d/99-touch-evdev.conf; do
    if [[ -f "$f" ]] && grep -q "ADS7846" "$f" 2>/dev/null; then
        sudo cp -a "$f" "$BACKUP_DIR/$(basename "$f").bak"
        sudo rm -f "$f"
        log "Removed legacy calibration file: $f"
    fi
done

log "Disabling conflicting KlipperScreen services"
# HelixScreen must be the only UI owning the framebuffer/input stack.
# Different KlipperScreen installs may use either capitalization.
for svc in KlipperScreen.service klipperscreen.service; do
    if systemctl list-unit-files --full --no-legend "$svc" 2>/dev/null | grep -q . || systemctl is-active --quiet "$svc" 2>/dev/null; then
        sudo systemctl stop "$svc" 2>/dev/null || true
        sudo systemctl disable "$svc" 2>/dev/null || true
        sudo systemctl mask "$svc" 2>/dev/null || true
        log "Disabled and masked $svc"
    fi
done
sudo systemctl daemon-reload

log "Installing HelixScreen"
# The official HelixScreen installer detects the platform, installs the
# matching release and configures its systemd service.
curl -fsSL https://releases.helixscreen.org/install.sh | sh

log "Installing virtual-touch service"
sed -e "s#__TS35_BEEPER_FLAG__#$FLAG_FILE#g" \
    -e "s#__TS35_BEEPER_HARDWARE__#$BEEPER_HARDWARE#g" \
    "$PROJECT_DIR/services/virtual-touch.service" | sudo tee /etc/systemd/system/virtual-touch.service >/dev/null

if [[ "$BEEPER_HARDWARE" == "1" ]]; then
    log "Installing beeper watcher service"
    sed -e "s#__TS35_USER__#$USER_NAME#g" -e "s#__TS35_BEEPER_FLAG__#$FLAG_FILE#g" \
        "$PROJECT_DIR/services/beeper-watcher.service" | sudo tee /etc/systemd/system/beeper-watcher.service >/dev/null
fi

sudo chown -R "$USER_NAME:$USER_NAME" "$INSTALL_DIR"
printf '1\n' | sudo tee "$FLAG_FILE" >/dev/null
sudo chown "$USER_NAME:$USER_NAME" "$FLAG_FILE"

if [[ "$BEEPER_HARDWARE" == "1" ]]; then
    log "Installing Klipper Touch Beep macro"
    PRINTER_CFG="$USER_HOME/printer_data/config/printer.cfg"
    if [[ -f "$PRINTER_CFG" ]] && ! grep -q '^\[gcode_macro TOGGLE_BEEPER\]' "$PRINTER_CFG"; then
        printf '\n' | sudo tee -a "$PRINTER_CFG" >/dev/null
        sudo tee -a "$PRINTER_CFG" < "$PROJECT_DIR/klipper/toggle_beeper.cfg" >/dev/null
        sudo chown "$USER_NAME:$USER_NAME" "$PRINTER_CFG"
    fi
fi

log "Enabling services"
sudo systemctl daemon-reload
if [[ "$BEEPER_HARDWARE" == "1" ]]; then
    sudo systemctl enable virtual-touch.service beeper-watcher.service
    sudo systemctl restart beeper-watcher.service
else
    sudo systemctl enable virtual-touch.service
fi
if [[ -e /dev/spidev0.2 ]]; then
    sudo systemctl restart virtual-touch.service
fi

cat <<EOF

Installation completed.

Backup:
  $BACKUP_DIR

A reboot is required to activate the Device Tree overlay:
  sudo reboot

After reboot:
  systemctl status virtual-touch.service --no-pager
EOF
if [[ "$BEEPER_HARDWARE" == "1" ]]; then
cat <<EOF
  systemctl status beeper-watcher.service --no-pager

HelixScreen widget:
  In HelixScreen, add a "Favorite Macro" widget bound to TOGGLE_BEEPER
  (see docs/helixscreen-widget.md for the exact steps).
EOF
fi

cat <<EOF

This project installed the TS35 touch driver (and optional beeper) and HelixScreen.
Touch is auto-detected by HelixScreen; no recalibration step is needed there.
EOF
