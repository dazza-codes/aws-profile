# shellcheck shell=bash
#
# Characterization tests: the static-key behavior of aws-profile and aws-role,
# written against the script before SSO support and kept as a contract.

test_static_activation_exports_profile_env() {
	use_fixture static
	load_script
	capture aws-profile static-a
	assert_rc 0
	assert_exported AWS_DEFAULT_PROFILE static-a
	assert_exported TF_VAR_aws_default_profile static-a
	assert_exported AWS_DEFAULT_REGION us-west-2
	assert_exported AWS_ACCESS_KEY_ID AKIASTATICA0000001
	assert_exported AWS_SECRET_ACCESS_KEY staticasecret0000001
	assert_exported AWS_ACCOUNT 111111111111
	assert_not_exported AWS_SESSION_TOKEN
	assert_not_exported AWS_PROFILE
}

test_static_activation_displays_masked_env() {
	use_fixture static
	load_script
	capture aws-profile static-a
	assert_stdout_sorted <<-'EOF'

		AWS_DEFAULT_PROFILE=static-a
		AWS_DEFAULT_REGION=us-west-2
		AWS_ACCOUNT=111111111111
		AWS_ACCESS_KEY_ID=...00001
		AWS_SECRET_ACCESS_KEY=...00001

	EOF
}

test_static_session_token_exported_when_present() {
	use_fixture static
	load_script
	capture aws-profile static-token
	assert_exported AWS_DEFAULT_REGION us-east-2
	assert_exported AWS_ACCESS_KEY_ID ASIASTATICTOKEN001
	assert_exported AWS_SECRET_ACCESS_KEY statictokensecret001
	assert_exported AWS_SESSION_TOKEN statictokensession0001
	assert_contains "$OUT" "AWS_SESSION_TOKEN=...n0001"
}

test_static_switch_drops_previous_session_token() {
	use_fixture static
	load_script
	capture aws-profile static-token
	capture aws-profile static-a
	assert_exported AWS_ACCESS_KEY_ID AKIASTATICA0000001
	assert_not_exported AWS_SESSION_TOKEN
}

test_default_profile_when_no_name_given() {
	use_fixture static
	load_script
	capture aws-profile
	assert_rc 0
	assert_exported AWS_DEFAULT_PROFILE default
	assert_exported AWS_DEFAULT_REGION us-east-1
	assert_exported AWS_ACCESS_KEY_ID AKIADEFAULT0000001
}

test_clear_unsets_profile_env() {
	use_fixture static
	load_script
	capture aws-profile static-token
	capture aws-profile clear
	assert_rc 0
	assert_stdout <<-'EOF'
		WARNING: clearing profile settings


	EOF
	for var in AWS_ACCOUNT AWS_DEFAULT_PROFILE AWS_DEFAULT_REGION AWS_ACCESS_KEY_ID \
		AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN AWS_ROLE_SESSION_FILE TF_VAR_aws_default_profile; do
		assert_not_exported "$var"
	done
}

test_unknown_profile_message() {
	use_fixture static
	load_script
	capture aws-profile nope
	assert_rc 0
	assert_stdout <<-'EOF'
		WARNING: nope is not available
		Available profiles:
		default
		static-a
		static-token
		'clear' will unset any current active profile
		'default' is used when no profile is specified


	EOF
}

test_unknown_profile_keeps_current_env() {
	use_fixture static
	load_script
	capture aws-profile static-a
	capture aws-profile nope
	assert_exported AWS_DEFAULT_PROFILE static-a
	assert_exported AWS_ACCESS_KEY_ID AKIASTATICA0000001
}

test_suppressed_env_prints_nothing() {
	use_fixture static
	load_script
	_AWS_SUPPRESS_ENV=true
	capture aws-profile static-a
	assert_eq "$OUT" "" "stdout"
	assert_exported AWS_DEFAULT_PROFILE static-a
}

test_role_requires_arn() {
	use_fixture static
	load_script
	capture aws-role
	assert_rc 1
	assert_eq "$OUT" "Undefined role ''" "stdout"
}

test_role_assume_from_static_profile() {
	use_fixture static
	load_script
	capture aws-profile static-a
	capture aws-role arn:aws:iam::333333333333:role/stub-role
	assert_rc 0
	assert_contains "$OUT" "Assuming role 'arn:aws:iam::333333333333:role/stub-role'"
	assert_exported AWS_DEFAULT_PROFILE static-a
	assert_exported AWS_ACCESS_KEY_ID ASIAROLE0000000001
	assert_exported AWS_SECRET_ACCESS_KEY rolesecret0000000001
	assert_exported AWS_SESSION_TOKEN rolesessiontoken0001
	session_file=$(exported_value AWS_ROLE_SESSION_FILE)
	case "$session_file" in
	/tmp/aws-role-session-*.json) ;;
	*) fail "unexpected AWS_ROLE_SESSION_FILE [$session_file]" ;;
	esac
	[ -s "$session_file" ] || fail "role session file is missing or empty"
	assert_eq "$(stub_calls 'sts assume-role --role-arn=arn:aws:iam::333333333333:role/stub-role --role-session-name aws-role-session-')" 1 "assume-role calls"
	rm -f "$session_file"
}

test_role_failure_restores_profile() {
	use_fixture static
	load_script
	capture aws-profile static-a
	capture aws-role arn:aws:iam::333333333333:role/denied
	assert_rc 1
	assert_contains "$OUT" "Assuming role 'arn:aws:iam::333333333333:role/denied' failed"
	assert_not_exported AWS_ROLE_SESSION_FILE
	assert_exported AWS_DEFAULT_PROFILE static-a
	assert_exported AWS_ACCESS_KEY_ID AKIASTATICA0000001
	assert_not_exported AWS_SESSION_TOKEN
	# The empty session file from the failed call is left behind until the
	# next aws-role call removes it.
	files=$(role_session_files)
	assert_eq "$(printf '%s\n' "$files" | grep -c .)" 1 "role session files"
	[ ! -s "$files" ] || fail "failed role session file should be empty"
	rm -f "$files"
}

test_role_clear_restores_profile_and_removes_file() {
	use_fixture static
	load_script
	capture aws-profile static-a
	capture aws-role arn:aws:iam::333333333333:role/stub-role
	session_file=$(exported_value AWS_ROLE_SESSION_FILE)
	capture aws-role clear
	assert_rc 0
	assert_contains "$OUT" "WARNING: clearing role settings"
	[ ! -e "$session_file" ] || fail "role session file was not removed"
	assert_not_exported AWS_ROLE_SESSION_FILE
	assert_exported AWS_DEFAULT_PROFILE static-a
	assert_exported AWS_ACCESS_KEY_ID AKIASTATICA0000001
	assert_not_exported AWS_SESSION_TOKEN
}

test_role_reassume_replaces_session_file() {
	use_fixture static
	load_script
	capture aws-profile static-a
	capture aws-role arn:aws:iam::333333333333:role/stub-role
	first_file=$(exported_value AWS_ROLE_SESSION_FILE)
	capture aws-role arn:aws:iam::333333333333:role/stub-role
	second_file=$(exported_value AWS_ROLE_SESSION_FILE)
	assert_rc 0
	[ -s "$second_file" ] || fail "new role session file is missing"
	if [ "$first_file" != "$second_file" ] && [ -e "$first_file" ]; then
		fail "previous role session file was not removed"
	fi
	assert_eq "$(role_session_files)" "$second_file" "role session files"
	rm -f "$second_file"
}

test_role_without_active_profile_uses_default_credentials() {
	use_fixture static
	load_script
	capture aws-role arn:aws:iam::333333333333:role/stub-role
	assert_rc 0
	assert_not_exported AWS_DEFAULT_PROFILE
	assert_exported AWS_ACCESS_KEY_ID ASIAROLE0000000001
	rm -f "$(exported_value AWS_ROLE_SESSION_FILE)"
}

test_role_without_active_profile_or_default_fails() {
	printf '[static-a]\naws_access_key_id = AKIASTATICA0000001\naws_secret_access_key = x\n' >"$HOME/.aws/credentials"
	load_script
	capture aws-role arn:aws:iam::333333333333:role/stub-role
	assert_rc 1
	assert_eq "$OUT" "There is no active profile that can assume any role" "stdout"
	assert_stub_not_called "assume-role"
}

test_disable_sso_forces_static_for_sso_profile() {
	use_fixture sso
	load_script
	export AWS_PROFILE_DISABLE_SSO=1
	export STUB_SSO_SESSIONS="sso-fallback"
	capture aws-profile sso-fallback
	assert_rc 0
	assert_exported AWS_DEFAULT_PROFILE sso-fallback
	assert_exported AWS_DEFAULT_REGION eu-west-1
	assert_exported AWS_ACCESS_KEY_ID AKIAFALLBACK000001
	assert_exported AWS_ACCOUNT 111111111111
	assert_not_exported AWS_PROFILE
	assert_stub_not_called "get-caller-identity --profile"
}

test_disable_sso_without_credentials_entry_is_not_available() {
	use_fixture sso
	load_script
	export AWS_PROFILE_DISABLE_SSO=1
	export STUB_SSO_SESSIONS="sso-only"
	capture aws-profile sso-only
	assert_contains "$OUT" "WARNING: sso-only is not available"
	assert_not_exported AWS_DEFAULT_PROFILE
	assert_not_exported AWS_PROFILE
}

test_completion_lists_credentials_profiles() {
	use_fixture static
	enable_bash_completion
	load_script
	assert_eq "$(completions)" "$(printf '%s\n' clear default static-a static-token)" "completions"
}
