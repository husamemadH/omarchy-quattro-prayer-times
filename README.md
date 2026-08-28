# Prayer times

An [Omarchy](https://omarchy.org/) shell bar widget: a mosque icon that shows
the next prayer and a live countdown on hover, with a click-to-open popup
listing today's five prayer times. (Only works for Omarchy Quattro — a
waybar version can be found [here](https://github.com/husamemadH/waybar-prayer-times).)

Matches the look of the built-in wifi/sound icons
only in the bar, no inline text.

<img width="229" height="353" alt="image" src="https://github.com/user-attachments/assets/0cade9d1-1937-40bd-a4b1-6f4d4047abda" />


 
<img width="286" height="59" alt="image" src="https://github.com/user-attachments/assets/8dd5317f-e25a-494a-9891-608e6e72b04c" />


## Install

```
omarchy plugin add https://github.com/husamemadH/omarchy-quattro-prayer-times.git --enable
```

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

**Reinstalling to get an update?** Run `omarchy restart shell` afterwards.
`rescanPlugins` only refreshes the plugin registry, not an already-loaded
widget's code, so a long-lived shell session keeps running the old version
until it restarts.

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
- When a prayer time arrives, the widget fires a desktop notification
  ("It's time for Asr") plus a chime, and the toast dismisses itself after 8
  seconds. It polls every 10 seconds and notifies each prayer at most once per
  day, and it won't replay a prayer that already passed before the shell
  started. The **Alerts** and **Sound** toggles at the bottom of the popup
  turn them off; both are stored in
  `~/.local/state/omarchy/settings/prayer-alerts.json` (separate from the
  cached times, which `prayer-fetch.sh` rewrites wholesale).

## Configuration

Calculation method defaults to Muslim World League (Aladhan method `3`).
Change it by editing `METHOD` in `prayer-fetch.sh`, or override per-run with
`PRAYER_METHOD=<id>`. See the
[Aladhan docs](https://aladhan.com/calculation-methods) for method IDs.

The arrival toast is sent at `normal` urgency, which the Omarchy shell shows
for 8 seconds in its regular accent. The other tiers are worse fits: `critical`
never auto-dismisses (it sits there until clicked), and `low` allows a shorter
5-second toast but renders in the dim "unimportant" styling, which is easy to
miss entirely. Pass `-t <ms>` in `notifyPrayer()` in `BarWidget.qml` to stretch
it up to 30s, the shell's cap.

The chime is `paplay` on `/usr/share/sounds/freedesktop/stereo/bell.oga`.
Point `soundPath` at any other file to change it — `ls
/usr/share/sounds/freedesktop/stereo/` for what ships with freedesktop's
sound theme.

## License

[MIT](LICENSE)
