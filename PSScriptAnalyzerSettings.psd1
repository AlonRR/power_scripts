# PSScriptAnalyzer configuration for this repo.
#
# NOTE on CustomRulePath: PSScriptAnalyzer resolves it relative to the *current working
# directory* of the run, not to this file. Run the analyzer from the repo root so it resolves:
#   Invoke-ScriptAnalyzer -Path . -Recurse -Settings .\PSScriptAnalyzerSettings.psd1
@{
    # Keep the full built-in rule set alongside the repo's custom rule.
    IncludeDefaultRules = $true
    CustomRulePath      = '.\CustomRules\PipelineOperatorPosition\PipelineOperatorPosition.psd1'

    # House style the default rules don't enforce.
    #
    # PSUseConsistentIndentation / PSUseConsistentWhitespace are deliberately NOT enabled: their
    # formatter does not understand the repo's leading-pipe continuation style (enforced by the
    # custom Measure-PipelineOperatorPosition rule) and would flag every continuation line. The
    # custom rule owns pipeline layout; PSPlaceOpenBrace covers brace placement.
    Rules = @{
        PSPlaceOpenBrace = @{ Enable = $true; OnSameLine = $true }
    }
}
