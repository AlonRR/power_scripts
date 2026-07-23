#Requires -Version 7.0
<#
.SYNOPSIS
    Lists Microsoft Edge workspaces (name and id).
.DESCRIPTION
    Reads Edge's WorkspacesCache JSON and emits one object per workspace. Emits objects rather than
    formatted text so the output can be piped, filtered, or exported; format it at the call site
    (for example: .\show_edge_workspaces.ps1 | Format-Table -AutoSize).
.PARAMETER Path
    The WorkspacesCache file. Defaults to the current user's Edge Default profile.
.EXAMPLE
    .\show_edge_workspaces.ps1
.EXAMPLE
    .\show_edge_workspaces.ps1 | Format-Table -AutoSize
.OUTPUTS
    PSCustomObject with Name and Id properties.
#>
[CmdletBinding()]
[OutputType([pscustomobject])]
param(
    [ValidateNotNullOrEmpty()]
    [string]$Path = (Join-Path $env:USERPROFILE 'AppData\Local\Microsoft\Edge\User Data\Default\Workspaces\WorkspacesCache')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if (-not (Test-Path -LiteralPath $Path)) {
    Write-Warning "Edge WorkspacesCache not found: $Path"
    return
}

try {
    $cache = Get-Content -LiteralPath $Path -Raw
    | ConvertFrom-Json
}
catch {
    throw "Failed to parse Edge WorkspacesCache '$Path': $($_.Exception.Message)"
}

if (-not $cache -or -not $cache.workspaces) {
    Write-Warning 'No Edge workspaces found.'
    return
}

foreach ($workspace in $cache.workspaces) {
    [pscustomobject]@{
        Name = $workspace.name
        Id = $workspace.id
    }
}
