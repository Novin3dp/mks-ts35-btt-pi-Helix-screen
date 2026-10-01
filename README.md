# MKS TS35 V2 + BTT Pi / CB1 + HelixScreen

راه‌اندازی خودکار درایور تاچ **MKS TS35 V2** روی **BTT Pi / CB1** برای استفاده با **Klipper + Moonraker + HelixScreen**.

این ریپازیتوری نسخه‌ی مخصوص **HelixScreen** پروژه‌ی تاچ TS35 است: Device Tree Overlay، درایور مجازی تاچ (spidev + uinput)، HelixScreen و بیپر اختیاری را نصب می‌کند — بدون نیاز به Xorg یا KlipperScreen، چون HelixScreen مستقیماً روی framebuffer رندر می‌کند و دستگاه تاچ تولیدشده را خودش به‌صورت خودکار تشخیص می‌دهد (بدون نیاز به کالیبراسیون جداگانه).

اگر به‌دنبال نسخه‌ی KlipperScreen (X11) هستید، به این ریپازیتوری مراجعه کنید:
https://github.com/Novin3dp/mks-ts35-btt-pi-klipper-screen

## سخت‌افزار هدف

- BTT Pi v1.2 + CB1 / Allwinner H616
- MKS TS35 V2، رزولوشن 480×320، کنترلر ST7796S
- تاچ مقاومتی XPT2046 روی SPI
- Klipper + Moonraker
- **HelixScreen** (https://github.com/prestonbrown/helixscreen)
- Armbian / Debian با پشتیبانی از DT overlay و framebuffer

> **توجه:** این پروژه بر اساس یک پیکربندی واقعی و تست‌شده برای CB1 تهیه شده است. بخش Device Tree و GPIOها به سخت‌افزار هدف وابسته‌اند و نباید بدون بررسی روی برد دیگری استفاده شوند.

## نصب سریع (یک دستور)

روی BTT Pi / CB1 با کاربر معمولی (نه root) اجرا کنید:

```bash
tmp=$(mktemp -d) && git clone --depth 1 https://github.com/Novin3dp/mks-ts35-helixscreen.git "$tmp/ts35h" && bash "$tmp/ts35h/install.sh"; rc=$?; rm -rf "$tmp"; exit $rc
```

یا به‌صورت دستی:

```bash
cd ~
git clone https://github.com/Novin3dp/mks-ts35-helixscreen.git
cd mks-ts35-helixscreen
bash install.sh
```

اسکریپت نصب:
- وابستگی‌ها (`device-tree-compiler`, `python3-evdev`, `python3-spidev`) را نصب می‌کند
- ماژول کرنل `spidev` را فعال و دائمی می‌کند
- سرویس‌های KlipperScreen را متوقف، غیرفعال و mask می‌کند (HelixScreen باید تنها UI باشد)
- Device Tree Overlay را کامپایل و در `/boot/overlay-user/` نصب می‌کند و `armbianEnv.txt` را به‌روزرسانی می‌کند
- درایور مجازی تاچ (`virtual_touch.py`) را به‌عنوان سرویس systemd نصب می‌کند
- HelixScreen را با نصب‌کننده‌ی رسمی نصب می‌کند
- در صورت تایید شما، بیپر اختیاری و ماکروی `TOGGLE_BEEPER` را هم نصب می‌کند
- قبل از هر تغییر، از فایل‌های موجود backup می‌گیرد
- اگر این پوشه یک git clone باشد، قبل از نصب بررسی می‌کند که نسخه‌ی محلی عقب‌تر از GitHub نباشد (برای جلوگیری از نصب نسخه‌ی قدیمی)

**HelixScreen هم توسط همین اسکریپت نصب می‌شود** (با نصب‌کننده‌ی رسمی: `https://releases.helixscreen.org/install.sh`). جزئیات بیشتر: https://github.com/prestonbrown/helixscreen

پس از نصب این ریپازیتوری، **یک reboot لازم است** تا overlay فعال شود.

## سیم‌کشی

| MKS TS35 | BTT Pi / CB1 |
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
| BEEPER (اختیاری) | GPIO70 / PC6 |

UART0 برای ارتباط با مادربرد پرینتر (مثلاً Robin Nano V3) تغییر نمی‌کند:
- Pin 8 / PH0 = UART0 TX
- Pin 10 / PH1 = UART0 RX

### تغذیه

برای جلوگیری از نویز رنگی لحظه‌ای هنگام لمس، تغذیه‌ی ۱۲ ولت BTT Pi را **مستقیم از منبع تغذیه‌ی اصلی** وصل کنید، نه از طریق رگولاتور روی مادربرد پرینتر.

## معماری نرم‌افزار

```
XPT2046 (SPI1 CS2, PC13)
      │
      ▼
/dev/spidev0.2  ──►  virtual_touch.py (systemd: virtual-touch.service)
                          │
                          ▼
                 دستگاه ورودی مجازی uinput
                 به نام "ADS7846 Touchscreen"
                          │
                          ▼
                    HelixScreen (تشخیص خودکار evdev)
```

بیپر (اختیاری):
```
TOGGLE_BEEPER (ماکروی Klipper، به‌عنوان ویجت HelixScreen)
      │  RESPOND MSG="BEEPER_TOGGLE_EVENT"
      ▼
beeper_watcher.py (polling از Moonraker gcode_store)
      │  toggles flag file
      ▼
virtual_touch.py می‌خواند و بیپر GPIO70 را فعال/غیرفعال می‌کند
```

درایور استاندارد کرنل (`ads7846`) روی این build به‌طور قابل‌توجهی غیرقابل‌اعتماد بود (اکثر لمس‌ها رد می‌شد). به همین دلیل Overlay، touch را با `compatible = "linux,spidev"` معرفی می‌کند (هرگز به ads7846 بایند نمی‌شود) و یک اسکریپت پایتون مستقیماً از SPI می‌خواند و رویدادها را با `uinput` تولید می‌کند.

## کالیبراسیون تاچ

راه‌اندازی اولیه شامل دو نوع تنظیم است که در `scripts/virtual_touch.py` قابل تغییرند:

### ۱. جهت محورها (در صورت نیاز)

```python
SWAP_XY = False
INVERT_X = True
INVERT_Y = False
```

این سه مقدار بین واحدهای فیزیکی مختلف TS35 (و حتی گاهی بین نصب‌های مختلف روی همان واحد) می‌توانند فرق کنند. اگر لمس معکوس/آینه‌ای/چرخیده بود:

1. سرویس را متوقف کنید: `sudo systemctl stop virtual-touch.service`
2. اجرای تشخیصی: `sudo python3 -c "..."` یا استفاده از `evtest` روی `/dev/input/eventX` برای مشاهده‌ی مقادیر خام هنگام لمس ۴ گوشه‌ی صفحه (بالا-چپ، بالا-راست، پایین-چپ، پایین-راست)
3. بر اساس نتیجه، مقادیر `SWAP_XY`/`INVERT_X`/`INVERT_Y` را تنظیم کنید
4. سرویس را دوباره راه‌اندازی کنید: `sudo systemctl restart virtual-touch.service`

### ۲. بازه‌ی خام ADC (در صورت نیاز)

اگر لمس در وسط صفحه دقیق ولی نزدیک لبه‌ها چند میلی‌متر خطا دارد (نه معکوس، فقط مقیاس اشتباه)، این مقادیر را تنظیم کنید:

```python
X_RAW_MIN = 200
X_RAW_MAX = 3900
Y_RAW_MIN = 200
Y_RAW_MAX = 3900
```

این مقادیر پیش‌فرض روی چند واحد فیزیکی تست و تایید شده‌اند، ولی ممکن است نیاز به تنظیم جزئی روی واحد شما داشته باشد.

> HelixScreen نیازی به کالیبراسیون جداگانه در خودش ندارد — همین مقادیر در پایتون کافی است.

## بیپر لمس (اختیاری) و ویجت HelixScreen

اگر هنگام نصب به سوال بیپر پاسخ "y" بدهید، ماکروی `TOGGLE_BEEPER` به `printer.cfg` اضافه می‌شود. برای افزودن دکمه‌ی روشن/خاموش بیپر به داشبورد HelixScreen، مراحل کامل در `docs/helixscreen-widget.md` آمده است (خلاصه: یک ویجت از نوع **Favorite Macro** اضافه کنید و آن را به ماکروی `TOGGLE_BEEPER` متصل کنید).

## رفع نصب (Uninstall)

```bash
cd mks-ts35-helixscreen
bash uninstall.sh
```

سرویس‌ها، overlay و فایل‌های نصب‌شده را حذف می‌کند. Klipper و HelixScreen دست‌نخورده باقی می‌مانند. برای بازگردانی `printer.cfg`، از backup زیر استفاده کنید:
```
~/novin3dp-ts35-helix-backups/
```

## عیب‌یابی

### تاچ هیچ واکنشی ندارد

```bash
systemctl status virtual-touch.service --no-pager
journalctl -u virtual-touch.service -n 50 --no-pager
ls /dev/spidev0.2   # باید وجود داشته باشد؛ اگر نه، reboot و بررسی armbianEnv.txt و ماژول spidev
```

### تاچ معکوس/چرخیده است

بخش «کالیبراسیون تاچ» بالا را دنبال کنید.

### بعد از نصب مجدد (reinstall)، تنظیمات قدیمی برگشت

اگر این پوشه یک `git clone` قدیمی است، حتماً قبل از `bash install.sh` یک بار `git pull` بزنید. اسکریپت نصب این حالت را تشخیص می‌دهد و هشدار می‌دهد، ولی تایید نهایی با شماست.

### بیپر صدا نمی‌دهد

```bash
systemctl status beeper-watcher.service --no-pager
cat ~/beeper_enabled   # باید 1 باشد
```

اگر بیپر هنگام نصب انتخاب نشده بود، سرویس `beeper-watcher.service` اصلاً نصب نمی‌شود — `bash install.sh` را دوباره اجرا کنید و این بار به سوال بیپر پاسخ "y" بدهید.

## ساختار فایل‌ها

```
overlay/ts35_cb1.dts          Device Tree Overlay (LCD @48MHz، تاچ @2MHz spidev)
scripts/virtual_touch.py      درایور مجازی تاچ + کالیبراسیون + بیپر اختیاری
scripts/beeper_watcher.py     polling از Moonraker برای toggle کردن بیپر
services/virtual-touch.service
services/beeper-watcher.service
klipper/toggle_beeper.cfg     ماکروی TOGGLE_BEEPER
docs/helixscreen-widget.md    راهنمای افزودن ویجت در HelixScreen
install.sh / uninstall.sh
```

## تنظیمات نهایی تست‌شده

| پارامتر | مقدار |
|---|---|
| LCD SPI speed | 48 MHz |
| Touch SPI speed | 2 MHz |
| SWAP_XY / INVERT_X / INVERT_Y | False / True / False (ممکن است نیاز به تنظیم مجدد روی واحد شما باشد) |
| X/Y raw rescale | 200–3900 |
| تغذیه BTT Pi | مستقیم ۱۲ ولت از منبع اصلی (نه از رگولاتور مادربرد پرینتر) |

## منبع فنی

این پروژه حاصل عیب‌یابی مستقیم روی سخت‌افزار واقعی (نه صرفاً مستندات) است: رد شدن درایور استاندارد `ads7846` به دلیل غیرقابل‌اعتماد بودن (تایید روی ۵ از ۵۰ واحد فیزیکی)، جایگزینی با یک درایور spidev+uinput سفارشی، و رفع جداگانه‌ی کندی رندر (افزایش SPI نمایشگر به ۴۸ مگاهرتز) و نویز رنگی لمس (منبع تغذیه‌ی مستقل).
