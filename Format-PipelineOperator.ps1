function Format-PipelineOperator {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [string]$Path
    )

    process {
        $content = Get-Content -Path $Path -Raw

        # Replace pipe at end of line with pipe at start of next line
        $newContent = $content -replace '([^\s])\s*\|\s*\r?\n\s*', "`$1`n| "

        # Only write if content changed
        if ($newContent -ne $content) {
            $newContent
            | Set-Content -Path $Path -NoNewline
            Write-Verbose "Updated pipeline operators in $Path"
        }
    }
}

# Example usage:
# Get-ChildItem -Path *.ps1 -Recurse | Format-PipelineOperator -Verbose
