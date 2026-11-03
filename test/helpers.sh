# shellcheck shell=bash
#
# Assertions shared by the test cases. Sourced by test/run.sh into a fresh bash
# or zsh process, so everything here must work in both shells.

fail() {
	printf 'FAIL: %s\n' "$*" >&2
	if [ -s "$TEST_TMP/out" ]; then
		printf -- '--- last stdout\n' >&2
		cat "$TEST_TMP/out" >&2
	fi
	if [ -s "$TEST_TMP/err" ]; then
		printf -- '--- last stderr\n' >&2
		cat "$TEST_TMP/err" >&2
	fi
	exit 1
}

use_fixture() {
	cp "$TEST_ROOT/test/fixtures/$1/config" "$TEST_ROOT/test/fixtures/$1/credentials" "$HOME/.aws/"
}

enable_bash_completion() {
	if [ -n "${ZSH_VERSION:-}" ]; then
		autoload -U compinit && compinit -u -D
		autoload -U bashcompinit && bashcompinit
	fi
}

load_script() {
	# shellcheck source=/dev/null
	. "$TEST_SCRIPT"
}

# Runs a command in the current shell (so env changes stick), capturing
# stdout, stderr and the exit status in OUT, ERR and RC.
capture() {
	"$@" >"$TEST_TMP/out" 2>"$TEST_TMP/err"
	RC=$?
	# shellcheck disable=SC2034
	OUT=$(cat "$TEST_TMP/out")
	# shellcheck disable=SC2034
	ERR=$(cat "$TEST_TMP/err")
}

assert_eq() {
	[ "$1" = "$2" ] || fail "${3:-value}: expected [$2], got [$1]"
}

assert_rc() {
	[ "$RC" = "$1" ] || fail "exit status: expected $1, got $RC"
}

assert_contains() {
	case "$1" in
	*"$2"*) ;;
	*) fail "${3:-output} does not contain [$2]" ;;
	esac
}

assert_not_contains() {
	case "$1" in
	*"$2"*) fail "${3:-output} unexpectedly contains [$2]" ;;
	esac
}

exported_value() {
	env | sed -n "s/^$1=//p"
}

assert_exported() {
	env | grep -q "^$1=" || fail "$1 is not exported"
	assert_eq "$(exported_value "$1")" "$2" "$1"
}

assert_not_exported() {
	if env | grep -q "^$1="; then
		fail "$1 should not be exported, got [$(exported_value "$1")]"
	fi
}

assert_no_key_vars() {
	assert_not_exported AWS_ACCESS_KEY_ID
	assert_not_exported AWS_SECRET_ACCESS_KEY
	assert_not_exported AWS_SESSION_TOKEN
}

# Compares captured stdout byte-for-byte with stdin.
assert_stdout() {
	cat >"$TEST_TMP/expected"
	diff -u "$TEST_TMP/expected" "$TEST_TMP/out" >"$TEST_TMP/diff" ||
		fail "stdout differs:
$(cat "$TEST_TMP/diff")"
}

# Compares captured stdout with stdin, ignoring line order (env order varies).
assert_stdout_sorted() {
	LC_ALL=C sort >"$TEST_TMP/expected"
	LC_ALL=C sort "$TEST_TMP/out" >"$TEST_TMP/actual"
	diff -u "$TEST_TMP/expected" "$TEST_TMP/actual" >"$TEST_TMP/diff" ||
		fail "stdout lines differ:
$(cat "$TEST_TMP/diff")"
}

assert_stderr() {
	cat >"$TEST_TMP/expected"
	diff -u "$TEST_TMP/expected" "$TEST_TMP/err" >"$TEST_TMP/diff" ||
		fail "stderr differs:
$(cat "$TEST_TMP/diff")"
}

stub_calls() {
	grep -c -- "$1" "$STUB_LOG" 2>/dev/null
}

assert_stub_not_called() {
	if grep -q -- "$1" "$STUB_LOG" 2>/dev/null; then
		fail "aws was called with [$1]:
$(cat "$STUB_LOG")"
	fi
}

# Role session files owned by this user, as aws-role creates them.
role_session_files() {
	find /tmp/ -type f -name '*aws-role-session-*.json' -user "$(id -u)" 2>/dev/null
}

completions() {
	COMP_WORDS=(aws-profile "")
	COMP_CWORD=1
	COMPREPLY=()
	_aws-profile-completions
	printf '%s\n' "${COMPREPLY[@]}" | LC_ALL=C sort
}
