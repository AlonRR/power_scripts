using namespace Microsoft.Windows.PowerShell.ScriptAnalyzer.Generic

function Measure-PipelineOperatorPosition {
    <#
    .SYNOPSIS
        Ensures that where a pipeline is split across lines, the '|' starts the continuation line.

    .DESCRIPTION
        When a pipeline spans multiple lines, the pipe operator should lead the continuation line
        rather than trail the previous one. Single-line pipelines are not flagged - only a pipeline
        that is already broken across lines with a trailing '|' is a violation.

    .PARAMETER ast
        The script block AST being analyzed.

    .EXAMPLE
        # Good (leading '|'):
        Get-Process
        | Where-Object { $_.CPU -gt 10 }
        | Sort-Object CPU

        # Good (single line):
        Get-Process | Sort-Object CPU

        # Bad (trailing '|'):
        Get-Process |
        Where-Object { $_.CPU -gt 10 }

    .NOTES
        Rule Name: PipelineOperatorPosition
        Severity: Warning
    #>
    [CmdletBinding()]
    [OutputType([Microsoft.Windows.PowerShell.ScriptAnalyzer.Generic.DiagnosticRecord[]])]
    param (
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [System.Management.Automation.Language.ScriptBlockAst]
        $ast
    )

    $results = [System.Collections.Generic.List[DiagnosticRecord]]::new()

    try {
        # Source lines, indexed so that file line N is $lines[N - 1]. Prefer the file on disk;
        # fall back to the AST's own text (offset by where the AST starts) for in-memory analysis.
        if ($ast.Extent.File -and (Test-Path -LiteralPath $ast.Extent.File)) {
            $lines = Get-Content -LiteralPath $ast.Extent.File
            $lineOffset = 0
        }
        else {
            $lines = $ast.Extent.Text -split "\r?\n"
            $lineOffset = $ast.Extent.StartLineNumber - 1
        }

        $pipelineAsts = $ast.FindAll({
                param($node) $node -is [System.Management.Automation.Language.PipelineAst]
            }, $true)

        foreach ($pipeline in $pipelineAsts) {
            $elements = $pipeline.PipelineElements
            for ($i = 1; $i -lt $elements.Count; $i++) {
                $prevEndLine = $elements[$i - 1].Extent.EndLineNumber
                $curStartLine = $elements[$i].Extent.StartLineNumber

                # Only multi-line pipelines can violate this rule; single-line pipes are fine.
                if ($curStartLine -le $prevEndLine) { continue }

                $idx = $prevEndLine - 1 - $lineOffset
                if ($idx -lt 0 -or $idx -ge $lines.Count) { continue }

                # Trailing '|' means the previous element's line ends with the operator.
                if ($lines[$idx].TrimEnd().EndsWith('|')) {
                    $results.Add([DiagnosticRecord]::new(
                            "Pipeline operator '|' should start the continuation line, not trail the previous one",
                            $elements[$i].Extent,
                            'Measure-PipelineOperatorPosition',
                            [DiagnosticSeverity]::Warning,
                            $ast.Extent.File
                        ))
                }
            }
        }
    }
    catch {
        $PSCmdlet.ThrowTerminatingError($PSItem)
    }

    return $results
}

Export-ModuleMember -Function Measure-PipelineOperatorPosition
