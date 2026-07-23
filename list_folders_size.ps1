#Requires -Version 7.0
<#
.SYNOPSIS
    Lists immediate subfolders of a path with their total size, largest first.
.DESCRIPTION
    Emits one object per subdirectory with its recursive size in bytes and MB. Emits objects rather
    than a formatted table so results can be sorted, filtered, or exported; format at the call site
    (for example: .\list_folders_size.ps1 | Format-Table -AutoSize).
.PARAMETER Path
    The parent folder whose subfolders are measured. Defaults to the current directory.
.EXAMPLE
    .\list_folders_size.ps1
.EXAMPLE
    .\list_folders_size.ps1 -Path C:\projects | Format-Table -AutoSize
.OUTPUTS
    PSCustomObject with Name, SizeMB, Bytes, and FullName properties.
#>
[CmdletBinding()]
[OutputType([pscustomobject])]
param(
    [ValidateScript({ Test-Path -LiteralPath $_ -PathType Container })]
    [string]$Path = '.'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Get-ChildItem -LiteralPath $Path -Directory
| ForEach-Object {
    $measure = Get-ChildItem -LiteralPath $_.FullName -Recurse -File -Force -ErrorAction SilentlyContinue
    | Measure-Object -Property Length -Sum
    $bytes = [long]($measure.Sum)
    [pscustomobject]@{
        Name     = $_.Name
        SizeMB   = [math]::Round($bytes / 1MB, 2)
        Bytes    = $bytes
        FullName = $_.FullName
    }
}
| Sort-Object -Property Bytes -Descending
