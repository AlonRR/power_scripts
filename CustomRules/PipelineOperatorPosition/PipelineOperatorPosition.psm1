using namespace Microsoft.Windows.PowerShell.ScriptAnalyzer.Generic

function Measure-PipelineOperatorPosition {
    <#
    .SYNOPSIS
        Ensures pipeline operators are at the start of lines.

    .DESCRIPTION
        This rule checks PowerShell scripts to ensure that pipeline operators (|)
        appear at the start of lines rather than at the end of lines.

    .PARAMETER ast
        The AST (Abstract Syntax Tree) of the script being analyzed.

    .EXAMPLE
        # Good:
        Get-Process
        | Where-Object { $_.CPU -gt 10 }
        | Sort-Object CPU

        # Bad:
        Get-Process |
        Where-Object { $_.CPU -gt 10 } |
        Sort-Object CPU

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

    # Initialize results array
    $results = [System.Collections.Generic.List[DiagnosticRecord]]::new()

    try {
        $pipelineAsts = $ast.FindAll({
                param($node) $node -is [System.Management.Automation.Language.PipelineAst]
            }, $true)

        foreach ($pipeline in $pipelineAsts) {
            $elements = $pipeline.PipelineElements
            for ($i = 1; $i -lt $elements.Count; $i++) {
                if ($elements[$i].Extent.StartLineNumber -eq $elements[$i - 1].Extent.EndLineNumber) {
                    $results.Add([DiagnosticRecord]::new(
                            "Pipeline operator '|' must be at the start of a new line",
                            $elements[$i].Extent,
                            'Measure-PipelineOperatorPosition',
                            [DiagnosticSeverity]::Warning,
                            $ast.Extent.File
                        ))
                }
            }
        }
    } catch {
        $PSCmdlet.ThrowTerminatingError($PSItem)
    }

    return $results
}

Export-ModuleMember -Function Measure-PipelineOperatorPosition
