#Requires -Version 7.0
<#
.SYNOPSIS
    Creates a Windows .lnk shortcut whose target is stored as a path relative to the shortcut.
.DESCRIPTION
    A normal shortcut hardcodes an absolute target, so it breaks when the folder is moved or the
    drive letter changes. This writes the target as a relative path (via the shell link's
    RelativePath field) so the shortcut keeps working as long as the shortcut and target keep the
    same relative position - useful for portable folders, USB drives, and synced directories.
    Dot-source the script to load the function.
.PARAMETER TargetPath
    The file or folder the shortcut points to.
.PARAMETER ShortcutPath
    Where to write the .lnk. Must end in .lnk.
.PARAMETER Arguments
    Optional command-line arguments for the target.
.EXAMPLE
    . .\create_relative_shortcut.ps1
    New-RelativeShortcut -TargetPath .\tools\app.exe -ShortcutPath .\App.lnk
.OUTPUTS
    System.IO.FileInfo for the created shortcut.
#>
function New-RelativeShortcut {
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([System.IO.FileInfo])]
    param(
        [Parameter(Mandatory, Position = 0)]
        [ValidateScript({ Test-Path -LiteralPath $_ })]
        [string]$TargetPath,

        [Parameter(Mandatory, Position = 1)]
        [ValidatePattern('\.lnk$')]
        [string]$ShortcutPath,

        [Parameter(Position = 2)]
        [string]$Arguments = ''
    )

    Set-StrictMode -Version Latest
    $ErrorActionPreference = 'Stop'

    $absTarget = (Resolve-Path -LiteralPath $TargetPath).ProviderPath
    $absShortcut = [System.IO.Path]::GetFullPath($ShortcutPath)
    $shortcutDir = Split-Path -Parent $absShortcut
    if (-not (Test-Path -LiteralPath $shortcutDir)) {
        throw "Shortcut directory does not exist: $shortcutDir"
    }
    # Path of the target relative to the shortcut's own folder.
    $relTarget = [System.IO.Path]::GetRelativePath($shortcutDir, $absTarget)

    if (-not $PSCmdlet.ShouldProcess($absShortcut, "Create relative shortcut -> $relTarget")) {
        return
    }

    $shell = New-Object -ComObject WScript.Shell
    try {
        $shortcut = $shell.CreateShortcut($absShortcut)
        $shortcut.TargetPath = $absTarget   # absolute is required for a valid link...
        $shortcut.RelativePath = $relTarget   # ...this makes Windows prefer the relative path
        $shortcut.WorkingDirectory = Split-Path -Parent $absTarget
        if ($Arguments) { $shortcut.Arguments = $Arguments }
        $shortcut.Save()
    }
    finally {
        [void][System.Runtime.InteropServices.Marshal]::ReleaseComObject($shell)
    }

    Get-Item -LiteralPath $absShortcut
}
