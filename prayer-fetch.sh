#!/bin/bash
# Fetches today's prayer times for the user's current location and caches
# them for the bar widget. Location resolution mirrors the weather widget:
# ~/.local/state/omarchy/settings/weather.json when set (owned by
# omarchy-weather-location), otherwise IP auto-detect via the same command,
# geocoded to coordinates with Open-Meteo.
set -uo pipefail

STATE_DIR="$HOME/.local/state/omarchy/settings"
WEATHER_LOC="$STATE_DIR/weather.json"
CACHE_FILE="$STATE_DIR/prayer-times.json"
SETTINGS_FILE="$STATE_DIR/prayer-alerts.json"
METHOD="${PRAYER_METHOD:-3}" # 3 = Muslim World League

mkdir -p "$STATE_DIR"

# Which madhhab sets Asr. Aladhan calls it `school`: 0 = Standard (Shafi'i,
# Maliki, Hanbali -- Asr once an object's shadow equals its own length), 1 =
# Hanafi (twice its length, which puts Asr roughly an hour later). Everything
# else in the timetable is identical between the two.
#
# The widget passes its toggle in as $1 so a fetch fired the instant the
# toggle flips cannot race the settings-file write. A bare run -- cron, a
# terminal, the right-click refresh -- has no argument and falls back to the
# stored preference.
case "${1:-}" in
hanafi) SCHOOL=1 ;;
standard) SCHOOL=0 ;;
"") SCHOOL="${PRAYER_SCHOOL:-}" ;;
*)
  echo "prayer-fetch: unknown madhhab '$1' (want 'hanafi' or 'standard')" >&2
  exit 2
  ;;
esac

if [[ -z $SCHOOL && -f $SETTINGS_FILE ]]; then
  SCHOOL=$(jq -r 'if .hanafiAsr == true then 1 else 0 end' "$SETTINGS_FILE" 2>/dev/null)
fi

[[ $SCHOOL == 1 ]] || SCHOOL=0

name="" lat="" lon=""

if [[ -f $WEATHER_LOC ]]; then
  name=$(jq -r '.name // "" | if type == "string" then . else "" end' "$WEATHER_LOC" 2>/dev/null)
  lat=$(jq -r '.latitude // empty' "$WEATHER_LOC" 2>/dev/null)
  lon=$(jq -r '.longitude // empty' "$WEATHER_LOC" 2>/dev/null)
fi

if [[ -z $name ]]; then
  name=$(omarchy-weather-location 2>/dev/null)
fi

if { [[ -z $lat ]] || [[ -z $lon ]]; } && [[ -n $name ]]; then
  geo=$(curl -fsS --max-time 5 -G \
    --data-urlencode "name=$name" \
    --data "count=1&language=en&format=json" \
    "https://geocoding-api.open-meteo.com/v1/search" 2>/dev/null)
  lat=$(jq -r '.results[0].latitude // empty' <<<"$geo" 2>/dev/null)
  lon=$(jq -r '.results[0].longitude // empty' <<<"$geo" 2>/dev/null)
fi

if [[ -z $lat || -z $lon ]]; then
  echo '{"error":"location unavailable"}'
  exit 1
fi

response=$(curl -fsS --max-time 8 -G \
  --data-urlencode "latitude=$lat" \
  --data-urlencode "longitude=$lon" \
  --data "method=$METHOD&school=$SCHOOL" \
  "https://api.aladhan.com/v1/timings/$(date +%d-%m-%Y)" 2>/dev/null)

if [[ -z $response ]]; then
  echo '{"error":"fetch failed"}'
  exit 1
fi

parsed=$(jq --arg name "${name:-Current location}" '
  if .code == 200 then {
    location: $name,
    date: .data.date.readable,
    hijri: (.data.date.hijri.day + " " + .data.date.hijri.month.en + " " + .data.date.hijri.year + "H"),
    school: (.data.meta.school // ""),
    timings: {
      Fajr: (.data.timings.Fajr | split(" ")[0]),
      Sunrise: (.data.timings.Sunrise | split(" ")[0]),
      Dhuhr: (.data.timings.Dhuhr | split(" ")[0]),
      Asr: (.data.timings.Asr | split(" ")[0]),
      Maghrib: (.data.timings.Maghrib | split(" ")[0]),
      Isha: (.data.timings.Isha | split(" ")[0])
    }
  } else {"error": "api error"} end
' <<<"$response" 2>/dev/null)

if [[ -z $parsed ]]; then
  echo '{"error":"parse failed"}'
  exit 1
fi

echo "$parsed" >"$CACHE_FILE.tmp" && mv "$CACHE_FILE.tmp" "$CACHE_FILE"
cat "$CACHE_FILE"
