# aws-profile

A bash function to read and switch AWS profiles in `~/.aws/credentials`.

See also:

- https://docs.aws.amazon.com/cli/latest/userguide/cli-configure-profiles.html
- https://docs.aws.amazon.com/cli/latest/userguide/cli-configure-envvars.html

## Getting Started

Source the `aws_profile.sh` file in `~/.bashrc` or similar shell-init, such
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

## Usage

When more than one AWS profile is needed, it's advised to avoid setting any `[default]` profile.
By using `aws-profile`, it is easy to activate or switch between profiles by setting the
required environment variables.

```bash
source ./aws_profile.sh
aws-profile [profile-name | clear]
```

It manages the environment variables:

```bash
AWS_DEFAULT_REGION
AWS_ACCESS_KEY_ID
AWS_SECRET_ACCESS_KEY
AWS_ACCOUNT
```

The values are drawn from `~/.aws/credentials`, which contains values like:

```ini
[profile-XX]
aws_access_key_id = AWSAccessKeyID
aws_secret_access_key = AWSSecretAccessKey
region = us-east-1
```

It will report the current settings, reset them using profile-name, or clear
them.

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
