#Requires -Version 7.0
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }
<#
    Pester tests for the loose utility scripts that expose a function:
    Get-DotEnvValue, New-RelativeShortcut, and Format-PipelineOperator.

    Run:  Invoke-Pester -Path .\Tests\Utilities.Tests.ps1
#>

BeforeAll {
    $script:repo = Split-Path $PSScriptRoot -Parent
    . (Join-Path $repo 'get-env-variable.ps1')
    . (Join-Path $repo 'create_relative_shortcut.ps1')
    . (Join-Path $repo 'Format-PipelineOperator.ps1')
}

Describe 'Get-DotEnvValue' {
    BeforeEach {
        $script:env = Join-Path $TestDrive '.env'
        Set-Content -LiteralPath $script:env -Value @(
            'MAC_ADDRESS:11-22-33-44-55-66'
            'HOST: example.local'
        )
    }

    It 'returns the value for a key' {
        Get-DotEnvValue -Name MAC_ADDRESS -Path $env | Should -Be '11-22-33-44-55-66'
    }

    It 'is case-insensitive on the key and trims surrounding whitespace' {
        Get-DotEnvValue -Name host -Path $env | Should -Be 'example.local'
    }

    It 'throws when the key is absent' {
        { Get-DotEnvValue -Name NOPE -Path $env } | Should -Throw
    }

    It 'throws when the file is missing' {
        { Get-DotEnvValue -Name MAC_ADDRESS -Path (Join-Path $TestDrive 'missing.env') } | Should -Throw
    }
}

Describe 'New-RelativeShortcut' {
    It 'creates a .lnk pointing at the target' {
        # Note: WScript.Shell's RelativePath is set at save time but is not readable back, so this
        # verifies the shortcut is created and resolves to the target; the relative-path handling
        # is exercised (no throw) but cannot be asserted via read-back.
        $target = Join-Path $TestDrive 'tools\app.exe'
        New-Item -ItemType Directory -Path (Split-Path $target) -Force | Out-Null
        Set-Content -LiteralPath $target -Value 'stub'
        $lnk = Join-Path $TestDrive 'App.lnk'

        $result = New-RelativeShortcut -TargetPath $target -ShortcutPath $lnk
        $result.FullName | Should -Be ([System.IO.Path]::GetFullPath($lnk))

        $lnk | Should -Exist
        $shell = New-Object -ComObject WScript.Shell
        try {
            $shell.CreateShortcut($lnk).TargetPath | Should -Be ([System.IO.Path]::GetFullPath($target))
        }
        finally {
            [void][System.Runtime.InteropServices.Marshal]::ReleaseComObject($shell)
        }
    }

    It 'rejects a shortcut path that is not a .lnk' {
        $target = Join-Path $TestDrive 'x.txt'
        Set-Content -LiteralPath $target -Value 'x'
        { New-RelativeShortcut -TargetPath $target -ShortcutPath (Join-Path $TestDrive 'bad.txt') } | Should -Throw
    }
}

Describe 'Format-PipelineOperator' {
    It 'rewrites a trailing pipe to the start of the next line' {
        $f = Join-Path $TestDrive 'trailing.ps1'
        Set-Content -LiteralPath $f -Value "Get-Process |`nWhere-Object Name"
        Format-PipelineOperator -Path $f
        (Get-Content -LiteralPath $f -Raw) | Should -Match "(?m)^\| Where-Object"
    }

    It 'leaves a file that already uses leading pipes unchanged' {
        $f = Join-Path $TestDrive 'leading.ps1'
        $original = "Get-Process`n| Where-Object Name`n"
        Set-Content -LiteralPath $f -Value $original -NoNewline
        Format-PipelineOperator -Path $f
        (Get-Content -LiteralPath $f -Raw) | Should -Be $original
    }
}
