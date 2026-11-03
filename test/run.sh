#!/usr/bin/env bash
#
# Runs every test_* function from test/*_test.sh, each in a fresh shell with an
# isolated HOME, no inherited AWS_* variables, and the `aws` stub first on PATH.
#
#   test/run.sh [-s SCRIPT] [-k PATTERN] [SHELL ...]
#
#   -s SCRIPT   script under test (default: ./aws_profile.sh)
#   -k PATTERN  only run tests whose name matches the grep pattern
#   SHELL       shells to run the suite in (default: bash zsh)

set -u

root=$(cd "$(dirname "$0")/.." && pwd)
script="${root}/aws_profile.sh"
pattern=""

while getopts "s:k:" opt; do
	case $opt in
	s) script=$(cd "$(dirname "$OPTARG")" && pwd)/$(basename "$OPTARG") ;;
	k) pattern=$OPTARG ;;
	*) exit 2 ;;
	esac
done
shift $((OPTIND - 1))
if [ $# -eq 0 ]; then
	set -- bash zsh
fi

if ! jq_path=$(command -v jq); then
	echo "jq is required to run the tests" >&2
	exit 2
fi
test_path="${root}/test/stub:$(dirname "$jq_path"):/usr/bin:/bin:/usr/sbin:/sbin"

passed=0
failed=0
failures=""

for shell in "$@"; do
	if ! shell_path=$(command -v "$shell"); then
		echo "skipping ${shell}: not found" >&2
		continue
	fi
	case $(basename "$shell_path") in
	zsh) shell_cmd="$shell_path -f" ;;
	bash) shell_cmd="$shell_path --noprofile --norc" ;;
	*) shell_cmd="$shell_path" ;;
	esac

	for test_file in "${root}"/test/*_test.sh; do
		for test_name in $(sed -n 's/^\(test_[A-Za-z0-9_]*\)[[:space:]]*()[[:space:]]*{.*/\1/p' "$test_file"); do
			if [ -n "$pattern" ] && ! echo "$test_name" | grep -q -- "$pattern"; then
				continue
			fi
			sandbox=$(mktemp -d "${TMPDIR:-/tmp}/aws-profile-test.XXXXXX")
			mkdir -p "${sandbox}/home/.aws"
			# shellcheck disable=SC2016,SC2086
			output=$(cd "$sandbox" && env -i \
				HOME="${sandbox}/home" \
				PATH="$test_path" \
				LANG=C \
				TERM=dumb \
				STUB_LOG="${sandbox}/stub.log" \
				TEST_ROOT="$root" \
				TEST_SCRIPT="$script" \
				TEST_FILE="$test_file" \
				TEST_TMP="$sandbox" \
				$shell_cmd -c '. "$TEST_ROOT/test/helpers.sh" && . "$TEST_FILE" && '"$test_name" 2>&1)
			status=$?
			if [ $status -eq 0 ]; then
				passed=$((passed + 1))
				printf 'ok     %-5s %s\n' "$shell" "$test_name"
			else
				failed=$((failed + 1))
				failures="${failures}  ${shell} ${test_name}"$'\n'
				printf 'not ok %-5s %s\n' "$shell" "$test_name"
				printf '%s\n' "$output" | sed 's/^/       /'
			fi
			rm -rf "$sandbox"
		done
	done
done

echo
echo "${passed} passed, ${failed} failed"
if [ $failed -gt 0 ]; then
	printf 'Failed:\n%s' "$failures"
	exit 1
fi
