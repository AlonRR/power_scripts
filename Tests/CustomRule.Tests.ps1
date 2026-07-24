#Requires -Version 7.0
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }
<#
    Pester tests for the custom PSScriptAnalyzer rule Measure-PipelineOperatorPosition.

    It should flag a pipeline broken across lines with a trailing '|', and NOT flag single-line
    pipelines or ones already using the leading-'|' style.

    Run:  Invoke-Pester -Path .\Tests\CustomRule.Tests.ps1
#>

BeforeAll {
    $script:rulePsd1 = Join-Path (Split-Path $PSScriptRoot -Parent) 'CustomRules\PipelineOperatorPosition\PipelineOperatorPosition.psd1'

    function Get-RuleFindingCount {
        param([string]$Code)
        $tmp = Join-Path $TestDrive ([guid]::NewGuid().ToString('N') + '.ps1')
        Set-Content -LiteralPath $tmp -Value $Code -NoNewline
        @(Invoke-ScriptAnalyzer -Path $tmp -CustomRulePath $script:rulePsd1 -IncludeRule Measure-PipelineOperatorPosition -ErrorAction SilentlyContinue).Count
    }
}

Describe 'Measure-PipelineOperatorPosition' {
    It 'flags a trailing-pipe multi-line pipeline' {
        Get-RuleFindingCount "Get-Process |`nWhere-Object Name |`nSort-Object CPU" | Should -BeGreaterThan 0
    }

    It 'does not flag a leading-pipe multi-line pipeline' {
        Get-RuleFindingCount "Get-Process`n| Where-Object Name`n| Sort-Object CPU" | Should -Be 0
    }

    It 'does not flag a single-line pipeline' {
        Get-RuleFindingCount 'Get-Process | Sort-Object CPU | Select-Object -First 1' | Should -Be 0
    }
}
