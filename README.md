# aws-profile

A bash function to read and switch AWS profiles in `~/.aws/credentials`.

See also:

- https://docs.aws.amazon.com/cli/latest/userguide/cli-configure-profiles.html
- https://docs.aws.amazon.com/cli/latest/userguide/cli-configure-envvars.html

# Usage

Source the script file (usually done by `~/.bashrc`) to have the function
available in the current shell, where it can modify the env.

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

