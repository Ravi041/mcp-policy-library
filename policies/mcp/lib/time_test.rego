package mcp.lib_test

import data.mcp.lib

weekdays := ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday"]

utc_window := {"timezone": "UTC", "days": weekdays, "start": "09:00", "end": "17:00"}

# 2026-11-05 is a Thursday and 2026-11-07 is a Saturday.

test_inside_window if lib.window_contains("2026-11-05T12:00:00Z", utc_window)

test_at_window_start_is_inside if lib.window_contains("2026-11-05T09:00:00Z", utc_window)

test_at_window_end_is_outside if not lib.window_contains("2026-11-05T17:00:00Z", utc_window)

test_before_window if not lib.window_contains("2026-11-05T08:59:59Z", utc_window)

test_wrong_day if not lib.window_contains("2026-11-07T12:00:00Z", utc_window)

test_offset_is_honored if lib.window_contains("2026-11-05T17:30:00+05:30", utc_window)

test_named_timezone_converts if {
	window := object.union(utc_window, {"timezone": "Asia/Kolkata"})
	lib.window_contains("2026-11-05T04:00:00Z", window)
	not lib.window_contains("2026-11-05T12:00:00Z", window)
}

test_timezone_can_change_the_day if {
	window := object.union(utc_window, {"timezone": "Asia/Kolkata", "start": "00:00", "end": "23:59"})
	not lib.window_contains("2026-11-06T20:00:00Z", window)
}

test_unknown_timezone_fails_closed if {
	not lib.window_contains("2026-11-05T12:00:00Z", object.union(utc_window, {"timezone": "Mars/Olympus"}))
}

test_missing_timezone_fails_closed if {
	not lib.window_contains("2026-11-05T12:00:00Z", object.remove(utc_window, ["timezone"]))
}

test_invalid_start_fails_closed if {
	not lib.window_contains("2026-11-05T12:00:00Z", object.union(utc_window, {"start": "9am"}))
}

test_out_of_range_end_fails_closed if {
	not lib.window_contains("2026-11-05T12:00:00Z", object.union(utc_window, {"end": "24:00"}))
}

test_overnight_window_never_matches if {
	window := object.union(utc_window, {"start": "22:00", "end": "06:00"})
	not lib.window_contains("2026-11-05T23:00:00Z", window)
	not lib.window_contains("2026-11-05T01:00:00Z", window)
}

test_invalid_timestamp_fails_closed if not lib.window_contains("yesterday", utc_window)

test_non_string_timestamp_fails_closed if not lib.window_contains(1762425000, utc_window)

test_valid_timestamp if lib.timestamp_is_valid("2026-11-05T12:00:00Z")

test_invalid_timestamp if not lib.timestamp_is_valid("2026-13-45")

test_non_string_timestamp if not lib.timestamp_is_valid(5)
