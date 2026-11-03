# aws-profile

A bash function to read and switch AWS profiles: static keys in `~/.aws/credentials`
and AWS IAM Identity Center (SSO) profiles in `~/.aws/config`.

See also:

- https://docs.aws.amazon.com/cli/latest/userguide/cli-configure-profiles.html
- https://docs.aws.amazon.com/cli/latest/userguide/cli-configure-envvars.html
- https://docs.aws.amazon.com/cli/latest/userguide/cli-configure-sso.html

## Getting Started

Install [jq](https://stedolan.github.io/jq/download/).  It is used to query
JSON outputs from AWS CLI.

Source the `aws_profile.sh` file in `~/.bashrc`, `~/.zshrc` or similar shell-init, such
as copy the file to `/etc/profile.d/aws_profile.sh`.

For example:

```sh
sudo curl -sSL https://raw.githubusercontent.com/dazza-codes/aws-profile/main/aws_profile.sh > /etc/profile.d/aws_profile.sh
```

For a user installation, use `~/bin/aws_profile.sh`.  For example:

```sh
mkdir -p  ~/bin
curl -sSL https://raw.githubusercontent.com/dazza-codes/aws-profile/main/aws_profile.sh > ~/bin/aws_profile.sh
```

Ensure the shell init includes `~/bin/` in the `$PATH` (it often does already).
Add the following to `~/.bashrc` (or similar shell init file).

```sh
if ! echo "$PATH" | grep -Eq "(^|:)${HOME}/bin($|:)"; then
    export PATH="${HOME}/bin:${PATH}"
fi

if [ -f ~/bin/aws_profile.sh ]; then
    source ~/bin/aws_profile.sh
fi
```

In zsh, tab completion of profile names needs bash completion support loaded
before sourcing the script; without it the script still works, just without
completion:

```sh
autoload -U compinit && compinit
autoload -U bashcompinit && bashcompinit
```

## Usage

When more than one AWS profile is needed, it's advised to avoid setting any `[default]` profile.
By using `aws-profile`, it is easy to activate or switch between profiles by setting the
required environment variables.

```bash
source ./aws_profile.sh
aws-profile [profile-name | clear]
```

The profiles are defined in `~/.aws/credentials`, e.g.:

```ini
[default]
aws_access_key_id = AWSAccessKeyID
aws_secret_access_key = AWSSecretAccessKey
region = us-east-1

[profile-XX]
aws_access_key_id = AWSAccessKeyID
aws_secret_access_key = AWSSecretAccessKey
region = us-east-1
```

It will report the current settings, reset them using profile-name, or clear
them.  It assumes a `default` profile is defined, but it is not required.
For example

```shell

$ aws-profile your-profile-name

AWS_DEFAULT_PROFILE=your-profile-name
AWS_DEFAULT_REGION=us-east-1
AWS_ACCOUNT=999999999
AWS_ACCESS_KEY_ID=...blahblah
AWS_SECRET_ACCESS_KEY=...blahblah

$ aws-role arn:aws:iam::999999999:role/your-aws-role

Assuming role 'arn:aws:iam::999999999:role/your-aws-role'

AWS_DEFAULT_PROFILE=your-profile-name
AWS_DEFAULT_REGION=us-east-1
AWS_ACCOUNT=999999999
AWS_ROLE_SESSION_FILE=/tmp/aws-role-session-11972.json
AWS_ACCESS_KEY_ID=...blahblah
AWS_SECRET_ACCESS_KEY=...blahblah
AWS_SESSION_TOKEN=...blahblah
```

## SSO profiles

Profiles in `~/.aws/config` with `sso_session` or `sso_start_url` are SSO profiles, e.g.:

```ini
[sso-session my-sso]
sso_start_url = https://my-sso.awsapps.com/start
sso_region = us-east-1
sso_registration_scopes = sso:account:access

[profile your-sso-profile]
sso_session = my-sso
sso_account_id = 999999999
sso_role_name = Developer
region = us-east-1
```

When the SSO session is valid (`aws sts get-caller-identity --profile NAME` succeeds),
`aws-profile NAME` sets `AWS_PROFILE` and does not export any access keys; the AWS CLI
and SDKs resolve and refresh the SSO credentials themselves.

```shell
$ aws sso login --sso-session my-sso
$ aws-profile your-sso-profile

AWS_PROFILE=your-sso-profile
AWS_DEFAULT_PROFILE=your-sso-profile
AWS_DEFAULT_REGION=us-east-1
AWS_ACCOUNT=999999999
```

When the SSO session is not available:

- if `[NAME]` is also in `~/.aws/credentials`, its static keys are used, with a warning
  on stderr to run `aws sso login --profile NAME`;
- otherwise only the login hint is printed and `aws-profile` returns 1.

`aws-profile` never starts `aws sso login` itself, so it is safe in scripts and
non-interactive shells.

Set `AWS_PROFILE_DISABLE_SSO=1` to ignore SSO settings and always use `~/.aws/credentials`,
exactly as before SSO support.

`aws-role` works from either kind of profile; in SSO mode the role is assumed with the
SSO credentials and its keys take precedence over `AWS_PROFILE` until `aws-role clear`.

The `AWS_SHARED_CREDENTIALS_FILE` and `AWS_CONFIG_FILE` environment variables are
honored, as they are by the AWS CLI.

## AWS EKS Configuration

This is an example of using bash (zsh) functions to manage EKS configurations.

```bash
#!/usr/bin/env bash

# shellcheck disable=SC1090
source ~/bin/aws_profile.sh

aws-cluster-eks-kubeconfig () {

        if [ "$AWS_DEFAULT_PROFILE" != "aws-cluster-eks-profile-e1" ]; then
                aws-profile aws-cluster-eks-profile-e1
        fi

        ## If the update-kubeconfig below works, should not need to assume a role
        #aws-role arn:aws:iam::999999999999:role/aws-cluster-eks-admin

        if [ ! -s ~/.kube/aws-cluster-eks-config.yaml ]; then
                aws eks update-kubeconfig \
                        --name aws-cluster-eks-config \
                        --alias aws-cluster-eks-config \
                        --profile aws-cluster-eks-profile-e1 \
                        --role-arn=arn:aws:iam::999999999999:role/aws-cluster-eks-admin \
                        --kubeconfig ~/.kube/aws-cluster-eks-config.yaml  
        fi
        
        export KUBECONFIG=~/.kube/aws-cluster-eks-config.yaml
        kubectl config use-context aws-cluster-eks-config
}
```

## Terraform Integration

Note that if terraform scripts use a common variable like this:

```terraform
variable "aws_default_profile" {
  default = "default"
}
```

The `aws-profile` function is also setting a useful override for that variable, i.e.

```shell
export TF_VAR_aws_default_profile="${profile_name}"
```

## Tests

The tests use fixture config files and an `aws` stub on the `PATH`, so they need no
network or real credentials (only `jq`). Each test runs in a fresh shell with an
isolated `HOME`:

```sh
test/run.sh                # bash and zsh
test/run.sh /bin/bash      # a specific shell
test/run.sh -k sso         # tests matching a pattern
```

Like `aws-role` itself, the role tests create and remove `/tmp/aws-role-session-*.json`.
