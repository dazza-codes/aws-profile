# shellcheck shell=bash
#
# SSO (IAM Identity Center) profiles from the config file, preferred when the
# SSO session is valid.

test_resolve_mode_reports_each_mode() {
	use_fixture sso
	load_script
	export STUB_SSO_SESSIONS="sso-only"
	assert_eq "$(_aws-profile-resolve-mode sso-only)" sso "sso-only"
	assert_eq "$(_aws-profile-resolve-mode static-b)" static "static-b"
	assert_eq "$(_aws-profile-resolve-mode sso-fallback 2>/dev/null)" static "sso-fallback"
	assert_eq "$(_aws-profile-resolve-mode nope)" none "nope"
	assert_eq "$(_aws-profile-resolve-mode sso-legacy 2>/dev/null)" none "sso-legacy"
}

test_sso_valid_session_activates_sso_profile() {
	use_fixture sso
	load_script
	export STUB_SSO_SESSIONS="sso-only"
	capture aws-profile sso-only
	assert_rc 0
	assert_eq "$ERR" "" "stderr"
	assert_exported AWS_PROFILE sso-only
	assert_exported AWS_DEFAULT_PROFILE sso-only
	assert_exported TF_VAR_aws_default_profile sso-only
	assert_exported AWS_DEFAULT_REGION us-west-1
	assert_exported AWS_ACCOUNT 222222222222
	assert_no_key_vars
	assert_stdout_sorted <<-'EOF'

		AWS_PROFILE=sso-only
		AWS_DEFAULT_PROFILE=sso-only
		AWS_DEFAULT_REGION=us-west-1
		AWS_ACCOUNT=222222222222

	EOF
	assert_eq "$(stub_calls 'sts get-caller-identity')" 1 "identity calls"
	assert_stub_not_called "sso login"
}

test_sso_start_url_profile_activates_sso_profile() {
	use_fixture sso
	load_script
	export STUB_SSO_SESSIONS="sso-legacy"
	capture aws-profile sso-legacy
	assert_rc 0
	assert_exported AWS_PROFILE sso-legacy
	assert_exported AWS_DEFAULT_REGION ap-southeast-2
	assert_no_key_vars
}

test_sso_activation_replaces_static_keys() {
	use_fixture sso
	load_script
	export STUB_SSO_SESSIONS="sso-only"
	capture aws-profile static-b
	capture aws-profile sso-only
	assert_exported AWS_PROFILE sso-only
	assert_no_key_vars
}

test_static_activation_after_sso_unsets_aws_profile() {
	use_fixture sso
	load_script
	export STUB_SSO_SESSIONS="sso-only"
	capture aws-profile sso-only
	capture aws-profile static-b
	assert_not_exported AWS_PROFILE
	assert_exported AWS_DEFAULT_PROFILE static-b
	assert_exported AWS_ACCESS_KEY_ID AKIASTATICB0000001
}

test_sso_expired_session_falls_back_to_credentials() {
	use_fixture sso
	load_script
	capture aws-profile sso-fallback
	assert_rc 0
	assert_stderr <<-'EOF'
		SSO session for sso-fallback unavailable; falling back to ~/.aws/credentials.
		Run: aws sso login --profile sso-fallback
	EOF
	assert_not_exported AWS_PROFILE
	assert_exported AWS_DEFAULT_PROFILE sso-fallback
	assert_exported AWS_DEFAULT_REGION eu-west-1
	assert_exported AWS_ACCESS_KEY_ID AKIAFALLBACK000001
	assert_exported AWS_SECRET_ACCESS_KEY fallbacksecret000001
	assert_exported AWS_ACCOUNT 111111111111
	assert_stub_not_called "sso login"
}

test_sso_expired_session_without_credentials_prints_login_hint() {
	use_fixture sso
	load_script
	capture aws-profile static-b
	capture aws-profile sso-only
	assert_rc 1
	assert_stderr <<-'EOF'
		SSO session for sso-only unavailable.
		Run: aws sso login --profile sso-only
	EOF
	assert_not_contains "$OUT" "is not available" "stdout"
	assert_exported AWS_DEFAULT_PROFILE static-b
	assert_not_exported AWS_PROFILE
	assert_stub_not_called "sso login"
}

test_role_from_sso_profile_then_clear_returns_to_sso() {
	use_fixture sso
	load_script
	export STUB_SSO_SESSIONS="sso-only"
	capture aws-profile sso-only
	capture aws-role arn:aws:iam::333333333333:role/stub-role
	assert_rc 0
	assert_contains "$OUT" "Assuming role 'arn:aws:iam::333333333333:role/stub-role'"
	assert_exported AWS_PROFILE sso-only
	assert_exported AWS_ACCESS_KEY_ID ASIAROLE0000000001
	assert_exported AWS_SESSION_TOKEN rolesessiontoken0001
	session_file=$(exported_value AWS_ROLE_SESSION_FILE)
	[ -s "$session_file" ] || fail "role session file is missing or empty"

	capture aws-role clear
	assert_rc 0
	[ ! -e "$session_file" ] || fail "role session file was not removed"
	assert_not_exported AWS_ROLE_SESSION_FILE
	assert_exported AWS_PROFILE sso-only
	assert_exported AWS_DEFAULT_PROFILE sso-only
	assert_exported AWS_ACCOUNT 222222222222
	assert_no_key_vars
}

test_role_reassume_from_sso_profile() {
	use_fixture sso
	load_script
	export STUB_SSO_SESSIONS="sso-only"
	capture aws-profile sso-only
	capture aws-role arn:aws:iam::333333333333:role/stub-role
	capture aws-role arn:aws:iam::333333333333:role/stub-role
	assert_rc 0
	assert_exported AWS_PROFILE sso-only
	assert_exported AWS_ACCESS_KEY_ID ASIAROLE0000000001
	rm -f "$(exported_value AWS_ROLE_SESSION_FILE)"
}

test_role_with_expired_sso_session_fails() {
	use_fixture sso
	load_script
	export STUB_SSO_SESSIONS="sso-only"
	capture aws-profile sso-only
	unset STUB_SSO_SESSIONS
	capture aws-role arn:aws:iam::333333333333:role/stub-role
	assert_rc 1
	assert_contains "$ERR" "Run: aws sso login --profile sso-only"
	assert_stub_not_called "assume-role"
}

test_role_without_active_profile_accepts_default_sso_profile() {
	use_fixture sso
	load_script
	export STUB_SSO_SESSIONS="default"
	capture aws-role arn:aws:iam::333333333333:role/stub-role
	assert_rc 0
	assert_exported AWS_ACCESS_KEY_ID ASIAROLE0000000001
	rm -f "$(exported_value AWS_ROLE_SESSION_FILE)"
}

test_clear_unsets_aws_profile() {
	use_fixture sso
	load_script
	export STUB_SSO_SESSIONS="sso-only"
	capture aws-profile sso-only
	capture aws-profile clear
	assert_not_exported AWS_PROFILE
	assert_not_exported AWS_DEFAULT_PROFILE
	assert_not_exported AWS_ACCOUNT
}

test_unknown_profile_lists_profiles_from_both_files() {
	use_fixture sso
	load_script
	capture aws-profile nope
	assert_rc 0
	assert_stdout <<-'EOF'
		WARNING: nope is not available
		Available profiles:
		sso-fallback
		static-b
		default
		sso-only
		sso-legacy
		'clear' will unset any current active profile
		'default' is used when no profile is specified


	EOF
}

test_completion_lists_profiles_from_both_files() {
	use_fixture sso
	enable_bash_completion
	load_script
	assert_eq "$(completions)" "$(printf '%s\n' clear default sso-fallback sso-legacy sso-only static-b)" "completions"
}

test_completion_is_registered_when_available() {
	use_fixture sso
	enable_bash_completion
	load_script
	complete -p | grep -q _aws-profile-completions || fail "completion is not registered"
}

test_sourcing_without_bashcompinit_is_quiet() {
	use_fixture sso
	capture load_script
	assert_rc 0
	assert_eq "$ERR" "" "stderr"
}

test_profile_without_config_section_skips_sso_probes() {
	use_fixture static
	load_script
	capture aws-profile static-token
	assert_exported AWS_ACCESS_KEY_ID ASIASTATICTOKEN001
	assert_stub_not_called "configure get sso_"
	assert_stub_not_called "get-caller-identity --profile"
}

test_file_locations_from_env() {
	mkdir -p "$TEST_TMP/alt"
	cp "$TEST_ROOT/test/fixtures/sso/config" "$TEST_ROOT/test/fixtures/sso/credentials" "$TEST_TMP/alt/"
	export AWS_CONFIG_FILE="$TEST_TMP/alt/config"
	export AWS_SHARED_CREDENTIALS_FILE="$TEST_TMP/alt/credentials"
	load_script
	export STUB_SSO_SESSIONS="sso-only"
	capture aws-profile sso-only
	assert_exported AWS_PROFILE sso-only
	capture aws-profile static-b
	assert_exported AWS_ACCESS_KEY_ID AKIASTATICB0000001
	capture aws-profile sso-fallback
	assert_contains "$ERR" "falling back to $TEST_TMP/alt/credentials."
}
