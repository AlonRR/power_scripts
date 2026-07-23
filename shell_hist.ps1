#Requires -Version 7.0
<#
.SYNOPSIS
    Searches the full PSReadLine command history for a substring.
.DESCRIPTION
    Returns the unique history lines containing the given text, oldest first. Emits the lines as
    output so they can be piped, counted, or paged (for example: hist git | Out-Host -Paging).
    Dot-source the script to load the function and its `hist` alias.
.PARAMETER Pattern
    The text to look for (matched literally, case-insensitive).
.EXAMPLE
    . .\shell_hist.ps1
    hist docker
.EXAMPLE
    Find-CommandHistory -Pattern 'git push' | Out-Host -Paging
.OUTPUTS
    System.String
#>
function Find-CommandHistory {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory, Position = 0, ValueFromRemainingArguments)]
        [ValidateNotNullOrEmpty()]
        [string[]]$Pattern
    )

    Set-StrictMode -Version Latest
    $ErrorActionPreference = 'Stop'

    $needle = ($Pattern -join ' ')
    $historyPath = (Get-PSReadLineOption).HistorySavePath
    if (-not (Test-Path -LiteralPath $historyPath)) {
        Write-Warning "History file not found: $historyPath"
        return
    }

    Write-Verbose "Searching '$historyPath' for '$needle'"
    Get-Content -LiteralPath $historyPath
    | Where-Object { $_ -like "*$needle*" }
    | Select-Object -Unique
}

Set-Alias -Name hist -Value Find-CommandHistory
