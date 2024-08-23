#!/usr/bin/env pwsh

# Set the AWS credentials file path
$env:AWS_SHARED_CREDENTIALS_FILE = "$HOME/.aws/credentials"

# Check if AWS CLI is installed and callable
if (-not (Get-Command aws -ErrorAction SilentlyContinue)) {
    Write-Host "Missing module: AWS CLI"
    exit 1
}

# Check if JQ is installed and callable
if (-not (Get-Command jq -ErrorAction SilentlyContinue)) {
    Write-Host "Missing module: jq json library"
    exit 1
}

# Ask user for ARN to be used
if (-not $env:AWS_MFA_ARN) {
    $AWS_MFA_ARN = Read-Host "Please enter a valid AWS_MFA_ARN"
    $env:AWS_MFA_ARN = $AWS_MFA_ARN
} else {
    Write-Host "The environment variable AWS_MFA_ARN is set to $env:AWS_MFA_ARN."
}

# set variables
$mfa_arn = if ($args[0]) { $args[0] } else { $env:AWS_MFA_ARN }
$refresh = if ($args[1]) { [int]$args[1] } else { 8 }
$refresh_secs = $refresh * 3600
$now = [int][double]::Parse((Get-Date -UFormat %s))
$timestampFile = "$HOME\.aws-mfa-login.timestamp"
if (Test-Path $timestampFile) {
    $ts = Get-Content $timestampFile
    $age = $now - [int]$ts
} else {
    $age = 0
}

if ($age -eq 0 -or $age -gt $refresh_secs) {
    # Maximum 3 attempts before script exits
    $attempt = 0
    while ($attempt -lt 3) {
        # Prompt for MFA code
        $mfa_code = Read-Host "Please enter MFA code for ${mfa_arn}"

        # Retrieve the JSON response from AWS CLI
        $responseJson = aws --profile default sts get-session-token --serial-number $mfa_arn --token-code $mfa_code --output json | jq -r '.Credentials'

        # Convert JSON response to PowerShell object
        $response = $responseJson | ConvertFrom-Json

        if ($response) {
            # extract the temporary credentials
            $aws_access_key_id = $response.AccessKeyId
            $aws_secret_access_key = $response.SecretAccessKey
            $aws_session_token = $response.SessionToken

            # Update AWS credentials file
            $credentialsFile = "$HOME\.aws\credentials"
            $credentialsNewFile = "$HOME\.aws\credentials.new"
            $credentialsOldFile = "$HOME\.aws\credentials.old"

            Copy-Item -Path $credentialsFile -Destination $credentialsNewFile
            (Get-Content $credentialsNewFile) -replace '# BEGIN TEMPORARY CREDENTIALS.*# END TEMPORARY CREDENTIALS', '' | Set-Content $credentialsNewFile
            Add-Content -Path $credentialsNewFile -Value (
                "`n# BEGIN TEMPORARY CREDENTIALS`n" +
                "[mfa]`n" +
                "aws_access_key_id=$aws_access_key_id`n" +
                "aws_secret_access_key=$aws_secret_access_key`n" +
                "aws_session_token=$aws_session_token`n" +
                "# END TEMPORARY CREDENTIALS"
            )

            Copy-Item -Path $credentialsFile -Destination $credentialsOldFile
            Move-Item -Path $credentialsNewFile -Destination $credentialsFile -Force

            # Update timestamp file
            $now | Out-File -FilePath $timestampFile -Force
            break
        } else {
            Write-Host "Failed to get session token, please try again."
            $attempt++
        }
    }
    if ($attempt -eq 3) {
        Write-Host "Maximum attempts reached. Exiting."
        exit 1
    }
} else {
    Write-Host "Credentials are still valid."
}