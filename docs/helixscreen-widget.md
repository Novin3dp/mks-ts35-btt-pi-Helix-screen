# Touch Beep as a HelixScreen widget

If you installed with the beeper enabled, this project adds a
`TOGGLE_BEEPER` Klipper macro to your `printer.cfg`. HelixScreen does not
read any config from this repo automatically — add a widget by hand, once:

1. Open HelixScreen on the touchscreen (or its web UI).
2. Go to the home dashboard editor and add a **Favorite Macro** widget.
3. Bind it to the `TOGGLE_BEEPER` macro.
4. Set **Require confirmation** to off (it only toggles a flag file, nothing
   destructive) — this is optional, pick whatever you prefer.
5. Save. Tapping the widget now silently toggles the beeper flag; the Python
   touch driver re-reads that flag about once a second.

There is no separate "status" to show on the widget: HelixScreen's live
on/off indicator for a dashboard widget (LED Settings → Macro Devices)
requires a real Klipper `neopixel`/`dotstar`/`led`/WLED object, and the
beeper here has no such object (it is only controlled from Python via
sysfs GPIO) — the widget acts as a plain momentary toggle.

## Installing HelixScreen itself

This repository only provides the touch driver (and optional beeper) for
the MKS TS35. If HelixScreen is not installed yet on this machine:

```bash
curl -sSL https://raw.githubusercontent.com/prestonbrown/helixscreen/main/scripts/install.sh | sh
```

See https://github.com/prestonbrown/helixscreen for details. No X11,
xorg, or display-manager setup is required — HelixScreen renders directly
to the framebuffer and auto-detects the touch device this project creates
("ADS7846 Touchscreen"), with no recalibration step needed.
