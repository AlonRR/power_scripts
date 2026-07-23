#Requires -Version 7.0
<#
.SYNOPSIS
    Recursively removes folders with a given name under a root path.

.DESCRIPTION
    Searches for and removes all folders whose name exactly matches the supplied
    name under the specified root path. The function supports PowerShell's
    ShouldProcess pattern, so you can use -WhatIf and -Confirm to preview or
    require confirmation before deletion.

.PARAMETER FolderName
    The folder name to look for and remove (for example: 'node_modules').

.PARAMETER RootPath
    The root path where the search begins (for example: 'C:\projects').

.EXAMPLE
    # Dry-run: show what would be removed
    Remove-FoldersByName -FolderName 'node_modules' -RootPath 'C:\projects' -WhatIf

.EXAMPLE
    # Remove with confirmation prompt
    Remove-FoldersByName -FolderName 'node_modules' -RootPath 'C:\projects' -Confirm

.NOTES
    - This is an advanced function and supports -WhatIf and -Confirm via ShouldProcess.
    - Re-import the module after editing the file: `Remove-Module MassRemove; Import-Module MassRemove -Force`
#>
function Remove-FoldersByName {
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
    param (
        [Parameter(Mandatory = $true, Position = 0)]
        [ValidateNotNullOrEmpty()]
        [string]$FolderName,

        [Parameter(Mandatory = $true, Position = 1)]
        [ValidateNotNullOrEmpty()]
        [string]$RootPath
    )

    Set-StrictMode -Version Latest

    try {
        if (-not (Test-Path -Path $RootPath)) {
            throw "Root path '$RootPath' does not exist."
        }

        Get-ChildItem -Path $RootPath -Recurse -Directory
        | Where-Object { $_.Name -eq $FolderName }
        | ForEach-Object {
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

Export-ModuleMember -Function 'Remove-FoldersByName'
