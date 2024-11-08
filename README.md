# aws-mfa-login

Prompt for AWS MFA code and retrieve temporary credentials.

Using the CLI (or any AWS SDK) with MFA

Your usual IAM credentials exist in the "default" profile and only allow you to manage your password and MFA. You need to actually authenticate with MFA to gain all of the permissions granted to your account, even when using the CLI (or any AWS SDK). To do that, you can use aws-mfa-login:

```bash
mkdir ~/bin
brew install jq
curl https://raw.githubusercontent.com/jhorwitz75/aws-mfa-login/master/aws-mfa-login > ~/bin/aws-mfa-login
chmod 755 ~/bin/aws-mfa-login
export PATH=$HOME/bin:$PATH # also add this to .bash_profile
export AWS_MFA_ARN=arn:aws:iam::YOUR_AWS_ACCOUNT_ID_HERE:mfa/YOUR_USERNAME_HERE # replace with your aws account id and username, also add this to .bash_profile
aws-mfa-login
```

You should be prompted for your MFA code. Enter it and it will create a new profile called "mfa" with your new temporary credentials. You will need to re-run `aws-mfa-login` every 12 hours.
