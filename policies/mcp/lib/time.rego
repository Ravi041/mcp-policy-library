package mcp.lib

timestamp_is_valid(timestamp) if {
	is_string(timestamp)
	is_number(time.parse_rfc3339_ns(timestamp))
}

minutes_of_day(hhmm) := minutes if {
	regex.match(`^([01][0-9]|2[0-3]):[0-5][0-9]$`, hhmm)
	parts := split(hhmm, ":")
	minutes := (to_number(parts[0]) * 60) + to_number(parts[1])
}

# True when the timestamp falls in a same-day window: start inclusive, end
# exclusive, evaluated in the window's named timezone. Any invalid or missing
# value makes this undefined, so callers using `not` fail closed. A window with
# start after end never matches; overnight windows are not supported.
window_contains(timestamp, window) if {
	timestamp_is_valid(timestamp)
	timezone := window.timezone
	nanoseconds := time.parse_rfc3339_ns(timestamp)
	time.weekday([nanoseconds, timezone]) in window.days
	clock := time.clock([nanoseconds, timezone])
	now := (clock[0] * 60) + clock[1]
	now >= minutes_of_day(window.start)
	now < minutes_of_day(window.end)
}
