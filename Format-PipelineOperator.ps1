#Requires -Version 7.0
<#
.SYNOPSIS
    Rewrites trailing pipeline operators to the leading-pipe style this repo uses.
.DESCRIPTION
    Rewrites a script so that a '|' left at the end of a line moves to the start of the next line,
    matching the style enforced by the Measure-PipelineOperatorPosition custom rule. Only rewrites
    a file when its content actually changes. Dot-source the script to load the function.
.PARAMETER Path
    One or more .ps1/.psm1 files to reformat. Accepts pipeline input.
.EXAMPLE
    . .\Format-PipelineOperator.ps1
    Get-ChildItem -Path *.ps1 -Recurse | Format-PipelineOperator -Verbose
.EXAMPLE
    Format-PipelineOperator -Path .\wake_on_lan.ps1 -WhatIf
#>
function Format-PipelineOperator {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [ValidateNotNullOrEmpty()]
        [Alias('FullName')]
        [string]$Path
    )

    begin {
        Set-StrictMode -Version Latest
        $ErrorActionPreference = 'Stop'
    }

    process {
        if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
            Write-Error "File not found: $Path"
            return
        }

        $content = Get-Content -LiteralPath $Path -Raw
        # Move a pipe left at end of a line to the start of the next line.
        $newContent = $content -replace '([^\s])\s*\|\s*\r?\n\s*', "`$1`n| "

        if ($newContent -ne $content) {
            if ($PSCmdlet.ShouldProcess($Path, 'Rewrite trailing pipes to leading style')) {
                $newContent | Set-Content -LiteralPath $Path -NoNewline
                Write-Verbose "Updated pipeline operators in $Path"
            }
        }
    }
}
