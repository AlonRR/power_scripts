#Requires -Version 7.0
<#
.SYNOPSIS
    Installs a local SSH public key into a remote Windows host's authorized_keys.
.DESCRIPTION
    Reads a public key file and appends it to ~/.ssh/authorized_keys on a remote Windows OpenSSH
    server over SSH, creating the .ssh directory if needed. Idempotent: the key is only added if it
    is not already present. Requires the OpenSSH client (ssh.exe) on PATH and an existing means of
    authenticating the first connection (password or an already-trusted key).
.PARAMETER UserAtHost
    The SSH target, e.g. 'user@host'.
.PARAMETER PublicKeyPath
    Path to the .pub key to install. Defaults to your own key, ~/.ssh/id_ed25519.pub.
.EXAMPLE
    . .\ssh-setup.ps1
    Add-SshPublicKeyToRemote -UserAtHost 'user@host'
.EXAMPLE
    Add-SshPublicKeyToRemote -UserAtHost 'user@host' -PublicKeyPath C:\keys\id_ed25519.pub -WhatIf
#>
function Add-SshPublicKeyToRemote {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    param(
        [Parameter(Mandatory, Position = 0)]
        [ValidateNotNullOrEmpty()]
        [string]$UserAtHost,

        [Parameter(Position = 1)]
        [ValidateScript({ Test-Path -LiteralPath $_ -PathType Leaf })]
        [string]$PublicKeyPath = (Join-Path -Path $HOME -ChildPath '.ssh' -AdditionalChildPath 'id_ed25519.pub')
    )

    Set-StrictMode -Version Latest
    $ErrorActionPreference = 'Stop'

    if (-not (Get-Command ssh -ErrorAction SilentlyContinue)) {
        throw 'ssh.exe not found on PATH. Install the OpenSSH client.'
    }

    $publicKey = (Get-Content -LiteralPath $PublicKeyPath -Raw).Trim()
    if ([string]::IsNullOrWhiteSpace($publicKey)) {
        throw "Public key file is empty: $PublicKeyPath"
    }

    # Remote PowerShell: create ~/.ssh, then append the key only if it is not already there.
    # Single-quote the key so nothing in it is re-interpreted remotely.
    $remoteScript = @"
`$ErrorActionPreference = 'Stop'
`$sshDir = Join-Path `$HOME '.ssh'
`$keys   = Join-Path `$sshDir 'authorized_keys'
New-Item -ItemType Directory -Force -Path `$sshDir | Out-Null
`$key = '$publicKey'
if (-not (Test-Path `$keys) -or -not (Select-String -LiteralPath `$keys -SimpleMatch -Quiet -Pattern `$key)) {
    Add-Content -Path `$keys -Value `$key
    'ADDED'
} else {
    'ALREADY_PRESENT'
}
"@

    if (-not $PSCmdlet.ShouldProcess($UserAtHost, 'Install SSH public key into authorized_keys')) {
        return
    }

    $result = $remoteScript | ssh $UserAtHost 'powershell -NoProfile -Command -'
    if ($LASTEXITCODE -ne 0) {
        throw "Remote key install failed (ssh exit $LASTEXITCODE)."
    }
    Write-Verbose "Remote reported: $result"
    [pscustomobject]@{ Target = $UserAtHost; Result = ($result | Select-Object -Last 1) }
}
