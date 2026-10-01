# MKS TS35 V2 + BTT Pi / CB1 + KlipperScreen

راه‌اندازی خودکار نمایشگر **MKS TS35 V2** روی **BTT Pi / CB1** برای استفاده با **Klipper + Mainsail + KlipperScreen**.

## سخت‌افزار هدف

- BTT Pi / CB1 با Allwinner H616
- MKS TS35 V2، رزولوشن 480×320، کنترلر ST7796S
- تاچ مقاومتی XPT2046
- Klipper + Moonraker + Mainsail
- KlipperScreen با backend X11
- Armbian / Debian با Device Tree Overlay و framebuffer

## نصب

روی BTT Pi / CB1 با کاربر معمولی:

```bash
cd ~
git clone https://github.com/Novin3dp/mks-ts35-btt-pi-Helix-screen.git
cd mks-ts35-btt-pi-Helix-screen
bash install.sh
```

نصب‌کننده Device Tree Overlay، spidev، framebuffer/Xorg، KlipperScreen، virtual touchscreen و Touch Beep را تنظیم می‌کند و قبل از تغییر فایل‌های موجود backup می‌سازد.

**بعد از نصب reboot لازم است.**

> اگر repository را قبلاً clone کرده‌ای، قبل از نصب مجدد حتماً `git pull` بزن. نصب‌کننده فایل‌ها را از checkout محلی کپی می‌کند.

## Touch calibration

کالیبراسیون در `scripts/virtual_touch.py` قرار دارد:

```python
SWAP_XY = False
INVERT_X = False
INVERT_Y = False

X_RAW_MIN = 200
X_RAW_MAX = 3900
Y_RAW_MIN = 200
Y_RAW_MAX = 3900
```

برای بررسی مقادیر خام:

```bash
cat /proc/bus/input/devices | grep -A5 -i ADS7846
sudo evtest /dev/input/eventX
```

اگر محورهای X/Y جابه‌جا هستند، `SWAP_XY` را تغییر دهید. اگر یک محور معکوس است، `INVERT_X` یا `INVERT_Y` را تغییر دهید. اگر مرکز دقیق است ولی لبه‌ها عقب می‌مانند، محدوده‌ی RAW را با مقادیر واقعی پنل تنظیم کنید.

## Touch Beep

ماکروی Klipper:

```ini
[gcode_macro TOGGLE_BEEPER]
gcode:
    RESPOND MSG="BEEPER_TOGGLE_EVENT"
```

پیام توسط `beeper_watcher.py` از Moonraker دریافت می‌شود و وضعیت `beeper_enabled` را تغییر می‌دهد.

## سرویس‌ها

```bash
systemctl status KlipperScreen --no-pager
systemctl status virtual-touch.service --no-pager
systemctl status beeper-watcher.service --no-pager
```

تاچ مجازی با نام `ADS7846 Touchscreen` از طریق evdev/uinput در اختیار KlipperScreen قرار می‌گیرد.

## تنظیمات سخت‌افزار

- LCD SPI: **48 MHz**
- Touch SPI: **2 MHz**
- Touch sampling: حدود **30 Hz**
- Touch IRQ: GPIO74 / PC10
- Beeper: GPIO70 / PC6
- framebuffer: `/dev/fb0`
- Touch: `/dev/spidev0.2`

برای کاهش نویز تصویر، BTT Pi را از ورودی اختصاصی تغذیه کنید.

## حذف

```bash
cd ~/mks-ts35-btt-pi-Helix-screen
bash uninstall.sh
```

این اسکریپت Klipper و KlipperScreen را حذف نمی‌کند.

## ساختار

```text
.
├── install.sh
├── uninstall.sh
├── overlay/ts35_cb1.dts
├── scripts/virtual_touch.py
├── scripts/beeper_watcher.py
├── services/virtual-touch.service
├── services/beeper-watcher.service
├── xorg/99-ts35-fbdev.conf
├── klipper/toggle_beeper.cfg
└── klipperscreen/touch_beep.conf
```

## License

MIT — see LICENSE.
