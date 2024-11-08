#!/usr/bin/env pwsh

# Filepath Variables
$profilePath = "$env:USERPROFILE\Documents\WindowsPowerShell\profile.ps1"
$timestampFile = "$env:USERPROFILE\.aws\mfa-login.timestamp"
$credentialsFile = "$env:USERPROFILE\.aws\credentials"
$credentialsNewFile = "$env:USERPROFILE\.aws\credentials.new"
$credentials_backup = "$env:USERPROFILE\.aws\credentials.old"

# Function to display help message
function Show-Help {
    Write-Host "Usage: .\aws-mfa-login.ps1 [options]"
    Write-Host "Options:"
    Write-Host "  --help, -h        Show this help message"
    Write-Host "  --refresh <hours> Set the refresh interval in hours (default: 8)"
    Write-Host "  --logout          Logout and remove temporary credentials"
    Write-Host "  --restore         Restore credentials file from backup"
}

# Function to check if the current token is valid
function Test-TokenValid {
    if (Test-Path $timestampFile) {
        $ts = Get-Content $timestampFile
        $now = [int][double]::Parse((Get-Date -UFormat %s))
        $age = $now - [int]$ts
        if ($age -lt $refreshSecs) {
            return $true
        }
    }
    return $false
}

# Function to save the variable to the environment
function Save-ToEnv {
    param (
        [string]$varName,
        [string]$varValue
    )

    if (-not (Test-Path $profilePath)) {
        New-Item -ItemType File -Path $profilePath -Force
    }

    if (-not (Get-Content $profilePath | Select-String -Pattern "^\s*`$global:$varName\s*=")) {
        Add-Content $profilePath "`$global:$varName = '$varValue'"
    }
    else {
        (Get-Content $profilePath) -replace "^\s*`$global:$varName\s*=.*", "`$global:$varName = '$varValue'" | Set-Content $profilePath
    }

    # Reload the environment
    . $profilePath
}

# Function to logout and remove temporary credentials
function Logout {
    if (Test-Path $credentialsFile) {
        $content = Get-Content $credentialsFile -Raw
        if ($content -match '# BEGIN TEMPORARY CREDENTIALS') {
            $content = $content -replace '(?s)# BEGIN TEMPORARY CREDENTIALS.*?# END TEMPORARY CREDENTIALS', ''
            $content | Set-Content $credentialsNewFile
            Move-Item -Path $credentialsNewFile -Destination $credentialsFile -Force
            Write-Host "Logged out and removed temporary credentials."
        }
        else {
            Write-Host "No temporary credentials found to remove."
        }
    }
    else {
        Write-Host "No credentials file found to logout."
    }
    if (Test-Path $timestampFile) {
        Remove-Item $timestampFile -ErrorAction SilentlyContinue
        Write-Host "Removed Timestamp Info"
    }
}

function Restore {
    if (Test-Path $credentials_backup) {
        Logout
        Move-Item $credentials_backup -Destination $credentialsFile -Force
        Write-Host "Restored credentials file from backup"
    }
    else {
        Write-Host "No backup found, exiting"
    }
}


# Set the AWS credentials file path
$env:AWS_SHARED_CREDENTIALS_FILE = $credentialsFile

# Check if AWS CLI is installed and callable
if (-not (Get-Command aws -ErrorAction SilentlyContinue)) {
    Write-Host "Missing module: AWS CLI"
    exit 1
}

# Parse command-line arguments
$refresh = 8
for ($i = 0; $i -lt $args.Length; $i++) {
    switch ($args[$i] -replace '--', '-') {
        '-help' { Show-Help; exit }
        '-refresh' { 
            $refresh = [int]$args[$i + 1]
            $i++  # Skip the next argument as it is the value for refresh
        }
        '-logout' { Logout; exit }
        '-restore' { Restore; exit }
        default { Write-Host "Unknown option: $($args[$i])"; Show-Help; exit 1 }
    }
}

$refreshSecs = $refresh * 3600

# Check if a valid token exists
if (Test-TokenValid) {
    Write-Host "A valid token exists. Do you want to log in as a different user? (y/n)"
    $answer = Read-Host
    if ($answer -ne 'y') {
        Write-Host "Using existing valid credentials."
        exit
    }
}

# Ask user for ARN to be used
if (-not $env:AWS_MFA_ARN) {
    $AWS_MFA_ARN = Read-Host "Please enter a valid AWS_MFA_ARN"
    $env:AWS_MFA_ARN = $AWS_MFA_ARN
    Save-ToEnv -varName "AWS_MFA_ARN" -varValue $AWS_MFA_ARN
}
else {
    $userInput = Read-Host "Enter MFA ARN ($env:AWS_MFA_ARN)"
    if ($userInput) {
        $env:AWS_MFA_ARN = $userInput
        Save-ToEnv -varName "AWS_MFA_ARN" -varValue $userInput
    }
}

# Set variables
$mfa_arn = if ($args[0]) { $args[0] } else { $env:AWS_MFA_ARN }

if (-not (Test-TokenValid)) {
    # Maximum 3 attempts before script exits
    $attempt = 0
    while ($attempt -lt 3) {
        # Prompt for MFA code
        $mfa_code = Read-Host "Please enter MFA code for ${mfa_arn}"

        # Retrieve the JSON response from AWS CLI
        $responseJson = aws --profile default sts get-session-token --serial-number $mfa_arn --token-code $mfa_code --output json

        # Convert JSON response to PowerShell object
        $response = $responseJson | ConvertFrom-Json

        if ($response) {
            # Extract the temporary credentials
            $aws_access_key_id = $response.Credentials.AccessKeyId
            $aws_secret_access_key = $response.Credentials.SecretAccessKey
            $aws_session_token = $response.Credentials.SessionToken

            # Read the current credentials file
            $content = Get-Content $credentialsFile -Raw

            # Remove any existing temporary credentials block
            $content = $content -replace '(?s)# BEGIN TEMPORARY CREDENTIALS.*?# END TEMPORARY CREDENTIALS', ''

            # Add the new temporary credentials block
            $newContent = $content + @"
# BEGIN TEMPORARY CREDENTIALS
[mfa]
aws_access_key_id=$aws_access_key_id
aws_secret_access_key=$aws_secret_access_key
aws_session_token=$aws_session_token
# END TEMPORARY CREDENTIALS
"@

            # Write the updated content to the new credentials file
            $newContent | Set-Content $credentialsNewFile

            # Take backup of current credentials, just in case
            Copy-item -Path $credentialsFile -Destination $credentials_backup -Force

            # Replace the old credentials file with the new one
            Move-Item -Path $credentialsNewFile -Destination $credentialsFile -Force

            # Update timestamp file
            $now = [int][double]::Parse((Get-Date -UFormat %s))
            $now | Out-File -FilePath $timestampFile -Force

            break
        }
        else {
            Write-Host "Failed to get session token, please try again."
            $attempt++
        }
    }
    if ($attempt -eq 3) {
        Write-Host "Maximum attempts reached. Exiting."
        exit 1
    }
}
else {
    Write-Host "Credentials are still valid."
}
