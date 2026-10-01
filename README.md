# MKS TS35 V2 + BTT Pi / CB1 + HelixScreen

راه‌اندازی **HelixScreen** روی **BTT Pi v1.2 / CB1 (Allwinner H616)** با نمایشگر **MKS TS35 V2 480×320** و تاچ مقاومتی **XPT2046**.

این پروژه HelixScreen رسمی را جایگزین KlipperScreen می‌کند، اما لایه سخت‌افزاری تست‌شده MKS TS35 را حفظ می‌کند:

- LCD: ST7796S روی SPI1 CS1، حدود 48MHz
- Touch: XPT2046 روی SPI1 CS2، حدود 2MHz
- Touch IRQ: PC10 / GPIO74
- Touch input: virtual uinput device named ADS7846 Touchscreen
- Framebuffer: /dev/fb0
- HelixScreen backend: fbdev
- Touch mapping: SWAP_XY=False, INVERT_X=True, INVERT_Y=False

HelixScreen مستقیماً روی framebuffer کار می‌کند و برای این معماری به X11/Xorg نیاز ندارد. مستندات رسمی HelixScreen، fbdev را به‌عنوان backend سازگار و BTT CB1 را به‌عنوان پلتفرم پشتیبانی‌شده معرفی می‌کنند. citeturn1search0turn2search1

## نصب

روی BTT Pi با کاربر معمولی:

```bash
cd ~
git clone https://github.com/Novin3dp/mks-ts35-btt-pi-Helix-screen.git
cd mks-ts35-btt-pi-Helix-screen
bash install.sh
```

سپس:

```bash
sudo reboot
```

اسکریپت رسمی HelixScreen از `releases.helixscreen.org` استفاده می‌شود؛ installer رسمی platform را تشخیص می‌دهد، HelixScreen را نصب می‌کند و UI رقیب را غیرفعال می‌کند. citeturn0search0turn2search1

## سیم‌کشی TS35

| TS35 | BTT Pi / CB1 |
|---|---|
| MOSI | Pin 19 / PH7 |
| MISO | Pin 21 / PH8 |
| SCK | Pin 23 / PH6 |
| LCD_CS | Pin 7 / PC7 → SPI1 CS1 |
| LCD_DC | Pin 11 / PC14 |
| LCD_RST | Pin 13 / PC12 |
| T_CS | Pin 12 / PC13 → SPI1 CS2 |
| T_IRQ | Pin 15 / PC10 |
| 5V | Pin 2 یا 4 |
| GND | Pin 6 |

## معماری تاچ

```
MKS TS35 XPT2046
      │
      ├── SPI1 CS2
      │
      └── /dev/spidev0.2
              │
              └── virtual_touch.py
                      │
                      └── uinput
                           │
                           └── /dev/input/ts35-touch
                                  │
                                  └── HelixScreen / evdev
```

HelixScreen از evdev برای ورودی تاچ استفاده می‌کند و می‌توان device را در `input.touch_device` مشخص کرد. این پروژه برای جلوگیری از تغییر شماره eventX یک symlink پایدار `/dev/input/ts35-touch` می‌سازد. citeturn2search0

## کالیبراسیون محورهای تاچ

در `scripts/virtual_touch.py`:

```python
SWAP_XY = False
INVERT_X = True
INVERT_Y = False
```

این همان mapping تست‌شده پروژه قبلی Novin3dp است.

اگر لمس جابه‌جا یا معکوس بود، این سه مقدار را تغییر دهید. علاوه بر آن، HelixScreen خودش Touch Calibration دارد و می‌تواند کالیبراسیون affine را روی ورودی مقاومتی انجام دهد. citeturn2search0

برای تست:

```bash
ls -l /dev/input/ts35-touch
cat /proc/bus/input/devices | grep -A6 -i ADS7846
sudo evtest /dev/input/ts35-touch
```

## بررسی LCD

بعد از reboot:

```bash
ls -l /dev/fb0
ls -l /dev/spidev0.2
fbset -i -fb /dev/fb0
```

وضعیت:

```bash
systemctl status helixscreen --no-pager
systemctl status virtual-touch.service --no-pager
journalctl -u helixscreen -n 100 --no-pager
journalctl -u virtual-touch.service -n 50 --no-pager
```

در صورت نیاز HelixScreen را مستقیماً روی framebuffer نگه دارید:

```bash
cat ~/helixscreen/config/helixscreen.env
```

باید شامل این باشد:

```text
HELIX_DISPLAY_BACKEND=fbdev
HELIX_TOUCH_DEVICE=/dev/input/ts35-touch
```

مستندات HelixScreen نیز برای نمایشگرهای framebuffer استفاده از backend `fbdev` را توصیه/پشتیبانی می‌کنند. citeturn1search0

## نکته مهم درباره KlipperScreen

این repository هیچ بخشی از Python/X11/requirements مربوط به KlipperScreen را نصب نمی‌کند.

اگر KlipperScreen قبلاً روی دستگاه وجود داشته باشد، installer آن را متوقف و disable می‌کند تا با HelixScreen روی /dev/fb0 رقابت نکند. HelixScreen نیز در installer رسمی خود UIهای رقیب را غیرفعال می‌کند. citeturn2search1

## به‌روزرسانی

برای HelixScreen:

```bash
curl -sSL https://releases.helixscreen.org/install.sh | sh -s -- --update
```

Moonraker update_manager نیز توسط این installer برای `prestonbrown/helixscreen` تنظیم می‌شود. citeturn0search1

برای به‌روزرسانی لایه TS35:

```bash
cd ~/mks-ts35-btt-pi-Helix-screen
git pull
bash install.sh
sudo reboot
```

## License

این repository برای لایه اختصاصی Novin3dp و integration سخت‌افزار TS35 ارائه شده است. HelixScreen مستقل است و تحت GPL-3.0 منتشر می‌شود.
