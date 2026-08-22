// Prayer names shown in the popup, in daily order (Sunrise is informational,
// not something you pray, so it's excluded from PRAYERS below).
var PRAYER_ORDER = ["Fajr", "Sunrise", "Dhuhr", "Asr", "Maghrib", "Isha"]
var PRAYERS = ["Fajr", "Dhuhr", "Asr", "Maghrib", "Isha"]

function parseCache(raw) {
  try {
    var data = JSON.parse(String(raw || "{}"))
    return data && typeof data === "object" ? data : null
  } catch (e) {
    return null
  }
}

function timeToDate(hhmm, base) {
  var parts = String(hhmm || "").split(":")
  if (parts.length < 2) return null
  var h = parseInt(parts[0], 10)
  var m = parseInt(parts[1], 10)
  if (isNaN(h) || isNaN(m)) return null
  return new Date(base.getFullYear(), base.getMonth(), base.getDate(), h, m, 0, 0)
}

// First prayer still ahead of `now` today; if all five have passed, rolls
// over to tomorrow's Fajr.
function nextPrayer(timings, now) {
  if (!timings) return null
  for (var i = 0; i < PRAYERS.length; i++) {
    var name = PRAYERS[i]
    var t = timeToDate(timings[name], now)
    if (t && t.getTime() > now.getTime()) return { name: name, time: timings[name], date: t }
  }
  var tomorrow = new Date(now.getFullYear(), now.getMonth(), now.getDate() + 1)
  var fajr = timeToDate(timings["Fajr"], tomorrow)
  return fajr ? { name: "Fajr", time: timings["Fajr"], date: fajr } : null
}

// The prayer whose time has just arrived: within `windowMs` before `now`.
// The arrival notification polls on a coarse timer, so it needs a window
// rather than an exact match; the caller de-dupes with prayerKey().
function duePrayer(timings, now, windowMs) {
  if (!timings) return null
  for (var i = 0; i < PRAYERS.length; i++) {
    var name = PRAYERS[i]
    var t = timeToDate(timings[name], now)
    if (!t) continue
    var elapsed = now.getTime() - t.getTime()
    if (elapsed >= 0 && elapsed < windowMs) return { name: name, time: timings[name], date: t }
  }
  return null
}

// Stable per-day identity for a prayer, so each one notifies at most once.
function prayerKey(prayer) {
  if (!prayer || !prayer.date) return ""
  var d = prayer.date
  return d.getFullYear() + "-" + (d.getMonth() + 1) + "-" + d.getDate() + " " + prayer.name
}

// Alerts preference file -> bool. Missing/corrupt file means alerts on, so a
// first run (or a file we can't read) still notifies.
function parseAlertsEnabled(raw) {
  try {
    var data = JSON.parse(String(raw || "{}"))
    if (data && typeof data.alerts === "boolean") return data.alerts
  } catch (e) {}
  return true
}

// "HH:MM" (24h, as returned by the API) -> "h:MM AM/PM" for display.
function formatTime12(hhmm) {
  var parts = String(hhmm || "").split(":")
  if (parts.length < 2) return String(hhmm || "")
  var h = parseInt(parts[0], 10)
  var m = parts[1]
  if (isNaN(h)) return String(hhmm || "")
  var period = h >= 12 ? "PM" : "AM"
  var h12 = h % 12
  if (h12 === 0) h12 = 12
  return h12 + ":" + m + " " + period
}

// Bare "Xh Ym" (or "Ym") span until `next`, no prayer name attached.
function timeRemaining(next, now) {
  if (!next || !next.date) return ""
  var diffMs = next.date.getTime() - now.getTime()
  if (diffMs <= 0) return "now"
  var totalMin = Math.round(diffMs / 60000)
  var h = Math.floor(totalMin / 60)
  var m = totalMin % 60
  return h > 0 ? (h + "h " + m + "m") : (m + "m")
}

function countdownLabel(next, now) {
  if (!next) return ""
  return next.name + " " + timeRemaining(next, now)
}

// Open-Meteo geocoding response -> suggestion rows for the location search.
function parseGeocodingResults(raw) {
  try {
    var data = JSON.parse(String(raw || "{}"))
    var results = data.results
    if (!results || !results.length) return []

    var out = []
    for (var i = 0; i < results.length; i++) {
      var r = results[i]
      if (!r || !r.name || r.latitude === undefined || r.longitude === undefined) continue
      var region = [r.admin1, r.country].filter(function(part) { return !!part }).join(", ")
      out.push({
        name: String(r.name),
        description: region,
        latitude: r.latitude,
        longitude: r.longitude
      })
    }
    return out
  } catch (e) {
    return []
  }
}

function locationCommit(text, suggestions, selectedIndex) {
  var name = String(text || "").replace(/^\s+|\s+$/g, "")
  if (name === "") return { name: "", latitude: null, longitude: null }

  var choices = suggestions || []
  var index = Math.max(0, Math.min(parseInt(selectedIndex, 10) || 0, choices.length - 1))
  var suggestion = choices[index]
  if (suggestion) return suggestion

  return { name: name, latitude: null, longitude: null }
}

if (typeof module !== "undefined") {
  module.exports = {
    PRAYER_ORDER: PRAYER_ORDER,
    PRAYERS: PRAYERS,
    parseCache: parseCache,
    timeToDate: timeToDate,
    nextPrayer: nextPrayer,
    duePrayer: duePrayer,
    prayerKey: prayerKey,
    parseAlertsEnabled: parseAlertsEnabled,
    formatTime12: formatTime12,
    timeRemaining: timeRemaining,
    countdownLabel: countdownLabel,
    parseGeocodingResults: parseGeocodingResults,
    locationCommit: locationCommit
  }
}
