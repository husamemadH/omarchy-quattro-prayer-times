# Prayer times

An [Omarchy](https://omarchy.org/) shell bar widget: a mosque icon that shows
the next prayer and a live countdown on hover, with a click-to-open popup
listing today's five prayer times.

## Install

```
omarchy plugin add https://github.com/husamemadH/omarchy-quattro-prayer-times.git --enable
```
PS run 'omarchy restart shell' if you reinstalled to get the latest update 

## Uninstall

```
omarchy plugin remove local.prayer-times
```
## Configuration

<img width="1920" height="1080" alt="image" src="https://github.com/user-attachments/assets/a10196f3-69bc-4f59-bdbd-9edd664901cc" />

Everything is set from the popup, left-click the mosque icon to open it.
Preferences are stored in `~/.local/state/omarchy/settings/prayer-alerts.json`,
separately from the cached times, which are rewritten on every refresh.

**The city name** — click it to search for somewhere else. The location is
shared with the built-in weather widget (both read `weather.json`), so changing
it here moves the weather too. Worth doing if IP geolocation puts you in the
wrong place, which it will behind a VPN.

**Alerts** — a desktop notification as each prayer time lands, which clears
itself after 8 seconds.

**Sound** — a chime alongside the toast. Off leaves the notification silent.
Hidden while Alerts is off, since it would control nothing.

**Bar countdown** — paints the next prayer beside the icon (`Dhuhr in 1h 20m`)
instead of keeping it on hover. It turns the bar's urgent colour with ten
minutes or less to go, and is left out on a vertical bar, where there is no room
for it — the tooltip still has it there.

**Hanafi Asr** — starts Asr when an object's shadow is twice its length rather
than once. The times come from the API rather than being shifted locally, so flipping this re-fetches, if that fetch fails the popup says so in red.

### Calculation method

Calculation method defaults to Muslim World League (Aladhan method `3`).
Change it by editing `METHOD` in `prayer-fetch.sh`, or override per-run with
`PRAYER_METHOD=<id>`. See the
[Aladhan docs](https://aladhan.com/calculation-methods) for method IDs.


The chime is `paplay` on `/usr/share/sounds/freedesktop/stereo/bell.oga`.
Point `soundPath` at any other file to change it — `ls
/usr/share/sounds/freedesktop/stereo/` for what ships with freedesktop's
sound theme.

## License

[MIT](LICENSE)
