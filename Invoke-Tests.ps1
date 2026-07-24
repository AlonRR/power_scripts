#Requires -Version 7.0
<#
.SYNOPSIS
    Runs the repo's Pester test suite, bootstrapping Pester 5+ if the host only has the old 3.4.
.DESCRIPTION
    Windows ships Pester 3.4, which cannot run these tests. This prefers an already-available
    Pester 5+, and otherwise downloads one into a gitignored local cache (.pester\) with
    Save-Module - so it needs no admin rights and no global install. Exits with the number of
    failed tests, so it doubles as a CI gate.
.PARAMETER Path
    Test path(s) to run. Defaults to the repo's Tests folder.
.PARAMETER Output
    Pester output verbosity. Default 'Detailed'.
.EXAMPLE
    .\Invoke-Tests.ps1
.EXAMPLE
    .\Invoke-Tests.ps1 -Path .\Tests\MassRemove.Tests.ps1 -Output Normal
#>
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '', Justification = 'Interactive test-runner console output.')]
[CmdletBinding()]
param(
    [string]$Path = (Join-Path $PSScriptRoot 'Tests'),
    [ValidateSet('None', 'Normal', 'Detailed', 'Diagnostic')]
    [string]$Output = 'Detailed'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$minVersion = [version]'5.0.0'

function Resolve-ModernPester {
    [CmdletBinding()]
    param([version]$MinimumVersion)

    # Already imported and new enough?
    $loaded = Get-Module Pester | Where-Object { $_.Version -ge $MinimumVersion } | Select-Object -First 1
    if ($loaded) { return $loaded.Path }

    # Installed somewhere on the module path?
    $installed = Get-Module -ListAvailable Pester
    | Where-Object { $_.Version -ge $MinimumVersion }
    | Sort-Object Version -Descending
    | Select-Object -First 1
    if ($installed) { return $installed.Path }

    # Fall back to a gitignored local cache, downloading once.
    $cache = Join-Path $PSScriptRoot '.pester'
    $find = {
        Get-ChildItem (Join-Path $cache 'Pester') -Filter 'Pester.psd1' -Recurse -ErrorAction SilentlyContinue
        | Sort-Object { [version]$_.Directory.Name } -Descending
        | Select-Object -First 1
    }
    $cached = & $find
    if (-not $cached) {
        Write-Host "Pester $MinimumVersion+ not found; downloading into $cache ..." -ForegroundColor Yellow
        New-Item -ItemType Directory -Path $cache -Force | Out-Null
        Save-Module -Name Pester -MinimumVersion $MinimumVersion -Path $cache -Force
        $cached = & $find
    }
    if (-not $cached) { throw 'Could not obtain Pester 5+.' }
    return $cached.FullName
}

$pesterPath = Resolve-ModernPester -MinimumVersion $minVersion
Get-Module Pester | Where-Object { $_.Version -lt $minVersion } | Remove-Module -Force
Import-Module $pesterPath -Force
Write-Host "Using Pester $((Get-Module Pester).Version)" -ForegroundColor Cyan

$config = New-PesterConfiguration
$config.Run.Path = $Path
$config.Run.PassThru = $true
$config.Output.Verbosity = $Output
$result = Invoke-Pester -Configuration $config

exit $result.FailedCount
