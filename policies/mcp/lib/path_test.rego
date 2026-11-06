package mcp.lib_test

import data.mcp.lib

test_segments_drop_empty_and_dot if {
	lib.path_segments("/srv//app/./x/") == ["srv", "app", "x"]
}

test_absolute_path_is_safe if lib.path_is_safe("/srv/app/file.txt")

test_relative_path_is_not_safe if not lib.path_is_safe("srv/app")

test_home_path_is_not_safe if not lib.path_is_safe("~/secrets")

test_empty_path_is_not_safe if not lib.path_is_safe("")

test_non_string_path_is_not_safe if not lib.path_is_safe(42)

test_null_path_is_not_safe if not lib.path_is_safe(null)

test_dot_dot_segment_is_traversal if lib.path_has_traversal("/srv/app/../../etc/passwd")

test_trailing_dot_dot_is_traversal if lib.path_has_traversal("/srv/app/..")

test_dot_dot_inside_name_is_not_traversal if not lib.path_has_traversal("/srv/app/a..b")

test_backslash_is_traversal if lib.path_has_traversal(`/srv/app\..\etc`)

test_encoded_dot_is_traversal if lib.path_has_traversal("/srv/app/%2e%2e/etc")

test_encoded_dot_uppercase_is_traversal if lib.path_has_traversal("/srv/app/%2E%2E/etc")

test_encoded_slash_is_traversal if lib.path_has_traversal("/srv/app/..%2Fetc")

test_plain_percent_is_not_traversal if not lib.path_has_traversal("/srv/app/100%.txt")

test_control_character_is_invalid if lib.path_has_invalid_chars("/srv/app/a\u0000b")

test_newline_is_invalid if lib.path_has_invalid_chars("/srv/app/a\nb")

test_normal_path_has_no_invalid_chars if not lib.path_has_invalid_chars("/srv/app/a b.txt")

test_proc_self_root_is_indirection if lib.path_has_indirection("/proc/self/root/etc/passwd")

test_proc_pid_cwd_is_indirection if lib.path_has_indirection("/proc/1234/cwd/x")

test_dev_fd_is_indirection if lib.path_has_indirection("/dev/fd/3")

test_proc_listing_is_not_indirection if not lib.path_has_indirection("/proc/cpuinfo")

test_within_exact_directory if lib.path_within("/srv/app", "/srv/app")

test_within_child if lib.path_within("/srv/app/a/b.txt", "/srv/app")

test_within_with_trailing_slash_on_dir if lib.path_within("/srv/app/a", "/srv/app/")

test_within_normalizes_dot_and_double_slash if lib.path_within("/srv//app/./a", "/srv/app")

test_within_stops_at_segment_boundary if not lib.path_within("/srv/app-secrets/a", "/srv/app")

test_within_rejects_parent if not lib.path_within("/srv", "/srv/app")

test_within_rejects_traversal_escape if not lib.path_within("/srv/app/../../etc/passwd", "/srv/app")

test_within_root_allows_any_safe_path if lib.path_within("/etc/hosts", "/")

test_within_rejects_unsafe_configured_dir if not lib.path_within("/srv/app/x", "/srv/app/../app")

test_within_rejects_relative_configured_dir if not lib.path_within("/srv/app/x", "srv/app")

test_within_is_case_sensitive if not lib.path_within("/SRV/app/x", "/srv/app")

test_within_any_matches_second_entry if lib.path_within_any("/b/x", ["/a", "/b"])

test_within_any_empty_list if not lib.path_within_any("/b/x", [])

test_glob_matches_at_depth if lib.path_matches_glob("/srv/app/.env", "**/.env")

test_glob_matches_directory_contents if lib.path_matches_glob("/home/u/.ssh/id_rsa", "**/.ssh/**")

test_glob_matches_directory_itself if lib.path_matches_glob("/home/u/.ssh", "**/.ssh/**")

test_glob_is_case_insensitive if lib.path_matches_glob("/srv/app/.ENV", "**/.env")

test_glob_normalizes_before_matching if lib.path_matches_glob("/srv//app/./.env", "**/.env")

test_glob_no_match if not lib.path_matches_glob("/srv/app/main.go", "**/.env")

test_glob_any_matches_second_entry if lib.path_matches_any_glob("/srv/.env", ["**/x", "**/.env"])

# path_within is the containment check every filesystem rule relies on, so it refuses unsafe
# paths itself rather than counting on each caller to check them first.
test_within_refuses_control_characters if not lib.path_within("/srv/app/a\u0000b", "/srv/app")

test_within_refuses_kernel_links if {
	not lib.path_within("/proc/self/root/srv/app/a", "/proc/self/root/srv/app")
	not lib.path_within("/dev/fd/3", "/dev")
}
