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

if (typeof module !== "undefined") {
  module.exports = {
    PRAYER_ORDER: PRAYER_ORDER,
    PRAYERS: PRAYERS,
    parseCache: parseCache,
    timeToDate: timeToDate,
    nextPrayer: nextPrayer,
    formatTime12: formatTime12,
    timeRemaining: timeRemaining,
    countdownLabel: countdownLabel
  }
}
