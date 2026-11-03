#!/usr/bin/env bash

# Copyright 2020-2022 Darren Weber
#
# Licensed under the Apache License, Version 2.0 (the "License"). You may not
# use this file except in compliance with the License. A copy of the License is
# located at
#
#      http://aws.amazon.com/apache2.0/
#
# or in the "license" file accompanying this file. This file is distributed on
# an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express
# or implied. See the License for the specific language governing permissions
# and limitations under the License.

#   FILE:  aws_profile.sh
#
#   USAGE:
#          source aws_profile.sh
#          aws-profile [profile-name | clear]
#
#   DESCRIPTION:  Bash function to list or activate AWS credentials from profile
#   names, see also:
#
#   - https://docs.aws.amazon.com/cli/latest/userguide/cli-configure-profiles.html
#   - https://docs.aws.amazon.com/cli/latest/userguide/cli-configure-envvars.html
#   - https://docs.aws.amazon.com/cli/latest/userguide/cli-configure-sso.html
#
#   An SSO (IAM Identity Center) profile in ~/.aws/config is activated by
#   setting AWS_PROFILE when its SSO session is valid; otherwise the static keys
#   for the profile in ~/.aws/credentials are exported. Set
#   AWS_PROFILE_DISABLE_SSO=1 to always use ~/.aws/credentials.
#
#   Source this script file in ~/.bashrc to have the function
#   available in the current shell, where it can modify the env.

unset _AWS_SUPPRESS_ENV

_aws-profile-credentials-file() {
	echo "${AWS_SHARED_CREDENTIALS_FILE:-$HOME/.aws/credentials}"
}

_aws-profile-config-file() {
	echo "${AWS_CONFIG_FILE:-$HOME/.aws/config}"
}

# Profile names from the credentials file, then any others from the config file.
_aws-profile-list() {
	{
		sed -n -e 's/^\[\(.*\)\]$/\1/p' "$(_aws-profile-credentials-file)" 2>/dev/null
		sed -n -e 's/^\[profile \(.*\)\]$/\1/p' -e 's/^\[default\]$/default/p' "$(_aws-profile-config-file)" 2>/dev/null
	} | awk '!seen[$0]++'
}

_aws-profile-in-credentials() {
	grep -q "\[${1}\]" "$(_aws-profile-credentials-file)" 2>/dev/null
}

_aws-profile-is-sso() {
	local profile_name=$1
	local config_file
	config_file=$(_aws-profile-config-file)

	# Each `aws configure get` costs a CLI startup, so skip profiles that have no
	# config section and cannot be SSO profiles.
	if ! grep -qFx "[profile ${profile_name}]" "$config_file" 2>/dev/null; then
		if [[ "$profile_name" != "default" ]] || ! grep -qFx "[default]" "$config_file" 2>/dev/null; then
			return 1
		fi
	fi

	[[ -n "$(aws configure get sso_session --profile "$profile_name" 2>/dev/null)" ]] ||
		[[ -n "$(aws configure get sso_start_url --profile "$profile_name" 2>/dev/null)" ]]
}

# Prints the activation mode for a profile: sso, static or none. It also sets
# _AWS_PROFILE_MODE and, for sso, _AWS_PROFILE_SSO_IDENTITY, so aws-profile can
# call it without a subshell and reuse the identity lookup.
_aws-profile-resolve-mode() {
	local profile_name=$1
	local identity credentials_label

	_AWS_PROFILE_MODE=none
	_AWS_PROFILE_SSO_IDENTITY=""

	if [[ -z "${AWS_PROFILE_DISABLE_SSO:-}" ]] && _aws-profile-is-sso "$profile_name"; then
		if identity=$(aws sts get-caller-identity --profile "$profile_name" 2>/dev/null); then
			_AWS_PROFILE_MODE=sso
			_AWS_PROFILE_SSO_IDENTITY=$identity
		elif _aws-profile-in-credentials "$profile_name"; then
			_AWS_PROFILE_MODE=static
			# shellcheck disable=SC2088
			credentials_label='~/.aws/credentials'
			if [[ -n "${AWS_SHARED_CREDENTIALS_FILE:-}" ]]; then
				credentials_label=$AWS_SHARED_CREDENTIALS_FILE
			fi
			echo "SSO session for ${profile_name} unavailable; falling back to ${credentials_label}." >&2
			echo "Run: aws sso login --profile ${profile_name}" >&2
		else
			echo "SSO session for ${profile_name} unavailable." >&2
			echo "Run: aws sso login --profile ${profile_name}" >&2
			echo "${_AWS_PROFILE_MODE}"
			return 1
		fi
	elif _aws-profile-in-credentials "$profile_name"; then
		_AWS_PROFILE_MODE=static
	fi

	echo "${_AWS_PROFILE_MODE}"
}

_aws-profile-activate-static() {
	local profile_name=$1

	aws-env-clear

	export AWS_DEFAULT_PROFILE="${profile_name}"
	export TF_VAR_aws_default_profile="${profile_name}" # for terraform

	AWS_DEFAULT_REGION=$(aws configure --profile "$AWS_DEFAULT_PROFILE" get region)
	AWS_ACCESS_KEY_ID=$(aws configure --profile "$AWS_DEFAULT_PROFILE" get aws_access_key_id)
	AWS_SECRET_ACCESS_KEY=$(aws configure --profile "$AWS_DEFAULT_PROFILE" get aws_secret_access_key)
	AWS_SESSION_TOKEN=$(aws configure --profile "$AWS_DEFAULT_PROFILE" get aws_session_token)

	export AWS_DEFAULT_REGION
	export AWS_ACCESS_KEY_ID
	export AWS_SECRET_ACCESS_KEY
	if [[ -n "${AWS_SESSION_TOKEN}" ]]; then
		export AWS_SESSION_TOKEN
	fi

	AWS_ACCOUNT=$(aws sts get-caller-identity | grep 'Account' | sed 's/[^0-9]//g')
	export AWS_ACCOUNT
}

# No keys are exported: the CLI and SDKs resolve and refresh SSO credentials
# from AWS_PROFILE themselves.
_aws-profile-activate-sso() {
	local profile_name=$1
	local identity=${2:-}

	aws-env-clear

	export AWS_PROFILE="${profile_name}"
	export AWS_DEFAULT_PROFILE="${profile_name}"
	export TF_VAR_aws_default_profile="${profile_name}" # for terraform

	AWS_DEFAULT_REGION=$(aws configure --profile "$AWS_DEFAULT_PROFILE" get region)
	export AWS_DEFAULT_REGION

	if [[ -z "${identity}" ]]; then
		identity=$(aws sts get-caller-identity --profile "$AWS_DEFAULT_PROFILE")
	fi
	AWS_ACCOUNT=$(printf '%s\n' "${identity}" | grep 'Account' | sed 's/[^0-9]//g')
	export AWS_ACCOUNT
}

aws-env() {
	if [[ -z "${_AWS_SUPPRESS_ENV}" ]]; then
		echo
		env | grep AWS_ | grep -v KEY | grep -v TOKEN
		env | grep -E 'AWS_.*KEY' | sed -e '/KEY/s/\(.*=\).*\(.....\)$/\1...\2/'
		env | grep -E 'AWS_.*TOKEN' | sed -e '/TOKEN/s/\(.*=\).*\(.....\)$/\1...\2/'
		echo
	fi
}

aws-env-clear() {
	unset AWS_ACCOUNT
	unset AWS_PROFILE
	unset AWS_DEFAULT_PROFILE
	unset AWS_DEFAULT_REGION
	unset AWS_ACCESS_KEY_ID
	unset AWS_SECRET_ACCESS_KEY
	unset AWS_SESSION_TOKEN
	rm -f "/tmp/aws-role-session-*"
	unset AWS_ROLE_SESSION_FILE
	unset TF_VAR_aws_default_profile
}

aws-env-clear-role() {
	unset AWS_ACCESS_KEY_ID
	unset AWS_SECRET_ACCESS_KEY
	unset AWS_SESSION_TOKEN
	rm -f "$AWS_ROLE_SESSION_FILE"
	unset AWS_ROLE_SESSION_FILE

	if [[ -n "${AWS_DEFAULT_PROFILE}" ]]; then
		# reset the env-vars for the active profile
		aws-profile "${AWS_DEFAULT_PROFILE}"
	fi
}

aws-profile() {
	local profile_name=${1:-default}
	local rc=0

	if [ "$profile_name" = "clear" ]; then
		echo "WARNING: clearing profile settings"
		aws-env-clear

	else
		_aws-profile-resolve-mode "${profile_name}" >/dev/null || rc=1

		case "${_AWS_PROFILE_MODE}" in
		sso)
			_aws-profile-activate-sso "${profile_name}" "${_AWS_PROFILE_SSO_IDENTITY}"
			;;
		static)
			_aws-profile-activate-static "${profile_name}"
			;;
		*)
			if [[ $rc -eq 0 ]]; then
				echo "WARNING: ${profile_name} is not available"
				echo "Available profiles:"
				_aws-profile-list
				echo "'clear' will unset any current active profile"
				echo "'default' is used when no profile is specified"
			fi
			;;
		esac
		unset _AWS_PROFILE_MODE _AWS_PROFILE_SSO_IDENTITY
	fi

	aws-env
	return $rc
}

aws-role() {
	role_arn=$1
	if [ "${role_arn}" = "" ]; then
		echo "Undefined role '${role_arn}'"
		return 1
	fi

	if [ "$role_arn" = "clear" ]; then
		echo "WARNING: clearing role settings"
		aws-env-clear-role
		return 0
	fi

	if [[ -n "${AWS_ROLE_SESSION_FILE}" ]]; then
		# reset the env-vars for the active profile
		unset AWS_ROLE_SESSION_FILE
	fi

	if [[ -n "${AWS_DEFAULT_PROFILE}" ]]; then
		# reset the env-vars for the active profile
		export _AWS_SUPPRESS_ENV=true
		if ! aws-profile "${AWS_DEFAULT_PROFILE}"; then
			unset _AWS_SUPPRESS_ENV
			return 1
		fi
		unset _AWS_SUPPRESS_ENV
	else
		if ! _aws-profile-in-credentials default && ! _aws-profile-is-sso default; then
			echo "There is no active profile that can assume any role"
			return 1
		fi
	fi

	role_session="aws-role-session-${RANDOM}"
	role_session_file="/tmp/${role_session}.json"

	find /tmp/ -type f -name '*aws-role-session-*.json' -exec rm {} +
	aws sts assume-role --role-arn="${role_arn}" --role-session-name ${role_session} >"${role_session_file}"

	if [[ -s "${role_session_file}" ]]; then
		echo "Assuming role '${role_arn}'"
		AWS_ROLE_SESSION_FILE="${role_session_file}"
		export AWS_ROLE_SESSION_FILE
		AWS_ACCESS_KEY_ID=$(jq -r '.Credentials.AccessKeyId' "${AWS_ROLE_SESSION_FILE}")
		AWS_SECRET_ACCESS_KEY=$(jq -r '.Credentials.SecretAccessKey' "${AWS_ROLE_SESSION_FILE}")
		AWS_SESSION_TOKEN=$(jq -r '.Credentials.SessionToken' "${AWS_ROLE_SESSION_FILE}")
		export AWS_ACCESS_KEY_ID
		export AWS_SECRET_ACCESS_KEY
		export AWS_SESSION_TOKEN
	else
		echo "Assuming role '${role_arn}' failed"
		aws-env-clear-role
		return 1
	fi

	aws-env
}

_aws-profile-completions() {
	profiles=$(_aws-profile-list)
	command_options="clear ${profiles}"
	COMPREPLY=($(compgen -W "${command_options}" "${COMP_WORDS[1]}"))
}

# zsh only has `complete` after `autoload -U bashcompinit && bashcompinit`.
if command -v complete >/dev/null 2>&1; then
	complete -F _aws-profile-completions aws-profile
fi
