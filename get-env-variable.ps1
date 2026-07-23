#Requires -Version 7.0
<#
.SYNOPSIS
    Reads a single value from a KEY:value .env file.
.DESCRIPTION
    The .env files in this repo store one entry per line as `KEY:value` (for example
    `MAC_ADDRESS:11-22-33-44-55-66`). This returns the value for a given key, or throws if the
    key is absent. Dot-source the script to load the function, then call Get-DotEnvValue.
.PARAMETER Name
    The key to look up (case-insensitive).
.PARAMETER Path
    The .env file to read. Defaults to '.env' in the current directory.
.EXAMPLE
    . .\get-env-variable.ps1
    Get-DotEnvValue -Name MAC_ADDRESS
.EXAMPLE
    Get-DotEnvValue MAC_ADDRESS -Path C:\secrets\.env
.OUTPUTS
    System.String
#>
function Get-DotEnvValue {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory, Position = 0)]
        [ValidateNotNullOrEmpty()]
        [string]$Name,

        [Parameter(Position = 1)]
        [ValidateNotNullOrEmpty()]
        [string]$Path = '.env'
    )

    Set-StrictMode -Version Latest
    $ErrorActionPreference = 'Stop'

    if (-not (Test-Path -LiteralPath $Path)) {
        throw "Env file not found: $Path"
    }

    # Match "KEY:value" at the start of a line; tolerate whitespace around the value.
    $pattern = '^\s*' + [regex]::Escape($Name) + '\s*:\s*(.*?)\s*$'
    foreach ($line in Get-Content -LiteralPath $Path) {
        $m = [regex]::Match($line, $pattern, 'IgnoreCase')
        if ($m.Success) {
            return $m.Groups[1].Value
        }
    }

    throw "Key '$Name' not found in $Path"
}
