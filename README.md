# Prayer times

An [Omarchy](https://omarchy.org/) shell bar widget: a mosque icon that shows
the next prayer and a live countdown on hover, with a click-to-open popup
listing today's five prayer times. (Only works for Omarchy Quattro — a
waybar version can be found [here](https://github.com/husamemadH/waybar-prayer-times).)

Matches the look of the built-in wifi/sound icons
only in the bar, no inline text.

![Popup opened after left-clicking the bar icon](preview.png)

## How it works

- `prayer-fetch.sh` resolves your location the same way the built-in weather
  widget does: reuses `~/.local/state/omarchy/settings/weather.json` if set,
  otherwise IP auto-detects via `omarchy-weather-location`, then geocodes to
  coordinates with Open-Meteo. Prayer times come from the free
  [Aladhan API](https://aladhan.com/prayer-times-api), cached to
  `~/.local/state/omarchy/settings/prayer-times.json` and refreshed once a
  day (or on right/middle click).
- `BarWidget.qml` renders the bar icon (Font Awesome `fa-mosque`) and the
  popup, `Model.js` holds the countdown/formatting logic. Clicking the
  location name in the popup swaps it for a search field (with Open-Meteo
  suggestions) to manually set a location, same as the built-in weather
  widget — and since both share `weather.json`, changing it here moves the
  weather widget's location too. Useful if IP-based geolocation isn't
  enabled/accurate (e.g. behind a VPN) — just click the city name and type
  the correct one.

## Install

```
omarchy plugin add https://github.com/husamemadH/omarchy-quattro-prayer-times.git --enable
omarchy bar plugin add local.prayer-times --section right --index 0
```

`--index 0` puts the icon at the left edge of the right section. Without it the
widget is placed after the section's anchor (`omarchy.tray`), and if you don't
run a tray widget it lands at the far end of the bar instead. Move it later with
`omarchy bar plugin move local.prayer-times --section right --index <n>`.

## Uninstall

```
omarchy bar plugin remove local.prayer-times
omarchy plugin remove local.prayer-times
```

Take the widget out of the bar layout first — `omarchy plugin remove` disables
and deletes the plugin, but leaves its entry in the layout behind.

The cached times in `~/.local/state/omarchy/settings/prayer-times.json` are left
on disk; delete it if you want them gone. Leave `weather.json` alone — that one
belongs to the built-in weather widget.

## Configuration

Calculation method defaults to Muslim World League (Aladhan method `3`).
Change it by editing `METHOD` in `prayer-fetch.sh`, or override per-run with
`PRAYER_METHOD=<id>`. See the
[Aladhan docs](https://aladhan.com/calculation-methods) for method IDs.

## License

[MIT](LICENSE)
