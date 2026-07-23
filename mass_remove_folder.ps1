<#
.SYNOPSIS
    Recursively removes specified folders from a given path.

.DESCRIPTION
    Searches for and removes all folders with the specified name under the given root path.
    Uses pipeline operators at the start of lines for better readability.

.PARAMETER folderName
    The name of the folders to remove.

.PARAMETER rootPath
    The root path to start searching from.

.PARAMETER WhatIf
    Shows what would happen if the command runs.

.PARAMETER Confirm
    Prompts for confirmation before running the command.

.PARAMETER verbose
    Provides detailed output during execution.

.EXAMPLE
    .\mass_remove_folder.ps1 -folderName "node_modules" -rootPath "C:\projects"
#>
function Remove-FoldersByName {
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
    param (
        [Parameter(Mandatory = $true, Position = 0)]
        [string]$FolderName,

        [Parameter(Mandatory = $true, Position = 1)]
        [string]$RootPath
    )

    try {
        if (-not (Test-Path -Path $RootPath)) {
            throw "Root path '$RootPath' does not exist."
        }

        Get-ChildItem -Path $RootPath -Recurse -Directory |
        Where-Object { $_.Name -eq $FolderName } |
        ForEach-Object {
            $folderFull = $_.FullName
            if ($PSCmdlet.ShouldProcess($folderFull, 'Remove folder')) {
                Remove-Item -LiteralPath $folderFull -Recurse -Force -ErrorAction Stop
            }
        }
    }
    catch {
        Write-Error $_.Exception.Message
    }
}

<#
Usage:
.
# Dot-source the script to load the function into the session, then call it:
# . .\mass_remove_folder.ps1
# Remove-FoldersByName -FolderName 'node_modules' -RootPath 'C:\projects' -WhatIf
# Remove for real (with confirmation):
# Remove-FoldersByName -FolderName 'node_modules' -RootPath 'C:\projects' -Confirm
#
# Notes:
# - This is an advanced function that supports -WhatIf and -Confirm via ShouldProcess.
# - The previous incorrect `Export-Alias` line has been removed.
#>