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
METHOD="${PRAYER_METHOD:-3}" # 3 = Muslim World League

mkdir -p "$STATE_DIR"

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
  --data "method=$METHOD" \
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
