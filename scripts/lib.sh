# Shared by check-fixtures.sh and e2e.sh. Source it; do not run it.

# Print the opa query that a decision document (as input) must satisfy for a
# fixture with the given file stem. Returns 1 when the name has no known prefix.
expected_outcome_query() {
	case "$1" in
	allow_*)
		echo 'input.allow == true; input.require_approval == false; count(input.deny) == 0'
		;;
	approve_*)
		echo 'input.allow == false; input.require_approval == true; count(input.deny) == 0'
		;;
	deny_*)
		_code="${1#deny_}"
		_code="${_code%%--*}"
		echo "input.allow == false; input.require_approval == false; some d in input.deny; d.code == \"$_code\""
		;;
	*)
		return 1
		;;
	esac
}
