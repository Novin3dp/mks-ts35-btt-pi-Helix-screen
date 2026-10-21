# نصب آفلاین

`install.sh` به اینترنت نیاز دارد (apt و نصب‌کننده‌ی HelixScreen). برای نصب بدون اینترنت مراحل زیر را دستی انجام دهید.

## ۱. آماده‌سازی (روی سیستمی با اینترنت)

۱. سورس این ریپازیتوری را دانلود کنید (ZIP یا `git clone`).

۲. بسته‌های لازم را دانلود کنید. این کار باید روی یک CB1 با **همان ایمیج Armbian** انجام شود:
```bash
mkdir ~/ts35-debs && cd ~/ts35-debs
sudo apt-get update
sudo apt-get install --download-only -y device-tree-compiler python3-evdev python3-spidev
cp /var/cache/apt/archives/*.deb .
```

۳. نسخه‌ی `aarch64` / `arm64` مربوط به HelixScreen را از صفحه‌ی Releases دانلود کنید:
https://github.com/prestonbrown/helixscreen/releases

۴. پوشه‌ی ریپازیتوری، پوشه‌ی `ts35-debs` و فایل HelixScreen را با فلش یا `scp` به `~` روی BTT Pi منتقل کنید.

## ۲. نصب (روی BTT Pi، با کاربر معمولی)

```bash
cd ~/mks-ts35-btt-pi-Helix-screen
INSTALL_DIR=/opt/novin3dp-ts35-helix
FLAG_FILE=$HOME/beeper_enabled
```

**بسته‌ها**
```bash
sudo dpkg -i ~/ts35-debs/*.deb
```

**ماژول spidev**
```bash
sudo modprobe spidev
echo spidev | sudo tee /etc/modules-load.d/ts35-spidev.conf
```

**کپی فایل‌ها**
```bash
sudo mkdir -p $INSTALL_DIR/scripts $INSTALL_DIR/overlay
sudo cp scripts/*.py $INSTALL_DIR/scripts/
sudo cp overlay/ts35_cb1.dts $INSTALL_DIR/overlay/
sudo chmod 755 $INSTALL_DIR/scripts/*.py
```

**بکاپ**
```bash
mkdir -p ~/novin3dp-ts35-helix-backups
cp /boot/armbianEnv.txt ~/printer_data/config/printer.cfg ~/novin3dp-ts35-helix-backups/
```

**Overlay**
```bash
dtc -@ -I dts -O dtb -o /tmp/ts35_cb1.dtbo overlay/ts35_cb1.dts
sudo mkdir -p /boot/overlay-user
sudo cp /tmp/ts35_cb1.dtbo /boot/overlay-user/
```
فایل `/boot/armbianEnv.txt` را باز کنید و `ts35_cb1` را به خط `user_overlays=` اضافه کنید. اگر این خط وجود ندارد، این خط را بنویسید:
```
user_overlays=ts35_cb1
```

**غیرفعال‌کردن KlipperScreen**
```bash
for s in KlipperScreen klipperscreen; do sudo systemctl stop $s; sudo systemctl disable $s; sudo systemctl mask $s; done 2>/dev/null
```

**نصب HelixScreen**

فایل دانلودشده را طبق راهنمای همان نسخه نصب کنید:
https://github.com/prestonbrown/helixscreen

**سرویس تاچ**

اگر بیپر ندارید، در دستور زیر `BEEP=0` بگذارید:
```bash
BEEP=1
sed -e "s#__TS35_BEEPER_FLAG__#$FLAG_FILE#g" -e "s#__TS35_BEEPER_HARDWARE__#$BEEP#g" \
    services/virtual-touch.service | sudo tee /etc/systemd/system/virtual-touch.service >/dev/null
echo 1 > $FLAG_FILE
sudo chown -R $USER:$USER $INSTALL_DIR
```

**بیپر (فقط اگر `BEEP=1`)**
```bash
sed -e "s#__TS35_USER__#$USER#g" -e "s#__TS35_BEEPER_FLAG__#$FLAG_FILE#g" \
    services/beeper-watcher.service | sudo tee /etc/systemd/system/beeper-watcher.service >/dev/null
grep -q '^\[gcode_macro TOGGLE_BEEPER\]' ~/printer_data/config/printer.cfg || \
    { echo; cat klipper/toggle_beeper.cfg; } >> ~/printer_data/config/printer.cfg
sudo systemctl enable beeper-watcher.service
```

**فعال‌سازی و ری‌استارت**
```bash
sudo systemctl daemon-reload
sudo systemctl enable virtual-touch.service
sudo reboot
```

## ۳. بررسی

```bash
ls /dev/spidev0.2
systemctl status virtual-touch.service --no-pager
systemctl status helixscreen --no-pager
```

اگر تاچ برعکس بود، `SWAP_XY` و `INVERT_X` و `INVERT_Y` را در `/opt/novin3dp-ts35-helix/scripts/virtual_touch.py` تغییر دهید و بعد این دستور را اجرا کنید:
```bash
sudo systemctl restart virtual-touch
```
