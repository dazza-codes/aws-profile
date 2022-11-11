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
#
#   Source this script file in ~/.bashrc to have the function
#   available in the current shell, where it can modify the env.

unset _AWS_SUPPRESS_ENV

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
	profile_name=${1:-default}
	if grep -q "\[${profile_name}\]" ~/.aws/credentials; then

		aws-env-clear

		export AWS_DEFAULT_PROFILE="${profile_name}"
		export TF_VAR_aws_default_profile="${profile_name}" # for terraform

		AWS_DEFAULT_REGION=$(aws configure --profile "$AWS_DEFAULT_PROFILE" get region)
		AWS_ACCESS_KEY_ID=$(aws configure --profile "$AWS_DEFAULT_PROFILE" get aws_access_key_id)
		AWS_SECRET_ACCESS_KEY=$(aws configure --profile "$AWS_DEFAULT_PROFILE" get aws_secret_access_key)
		AWS_ACCOUNT=$(aws sts get-caller-identity | grep 'Account' | sed 's/[^0-9]//g')

		export AWS_DEFAULT_REGION
		export AWS_ACCESS_KEY_ID
		export AWS_SECRET_ACCESS_KEY
		export AWS_ACCOUNT

	elif [ "$profile_name" = "clear" ]; then
		echo "WARNING: clearing profile settings"
		aws-env-clear

	else
		echo "WARNING: ${profile_name} is not available"
		echo "Available profiles:"
		sed -n -e 's/^\[\(.*\)\]$/\1/p' ~/.aws/credentials
		echo "'clear' will unset any current active profile"
		echo "'default' is used when no profile is specified"
	fi

	aws-env
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
		aws-profile "${AWS_DEFAULT_PROFILE}"
		unset _AWS_SUPPRESS_ENV
	else
		if ! grep -q "\[default\]" ~/.aws/credentials; then
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
	profiles=$(sed -n -e 's/^\[\(.*\)\]$/\1/p' ~/.aws/credentials)
	command_options="clear ${profiles}"
	COMPREPLY=($(compgen -W "${command_options}" "${COMP_WORDS[1]}"))
}

complete -F _aws-profile-completions aws-profile
