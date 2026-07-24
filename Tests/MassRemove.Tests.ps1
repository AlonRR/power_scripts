#Requires -Version 7.0
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }
<#
    Pester tests for the MassRemove module (Remove-FoldersByName).

    Run:  Invoke-Pester -Path .\Tests\MassRemove.Tests.ps1
#>

BeforeAll {
    Import-Module (Join-Path (Split-Path $PSScriptRoot -Parent) 'MassRemove\MassRemove.psd1') -Force
}

AfterAll {
    Remove-Module MassRemove -Force -ErrorAction SilentlyContinue
}

Describe 'Remove-FoldersByName' {
    BeforeEach {
        # tree:  root/{a/node_modules, b/c/node_modules, keep, node_modules_not}
        $script:root = Join-Path $TestDrive 'tree'
        New-Item -ItemType Directory -Force -Path @(
            (Join-Path $root 'a\node_modules')
            (Join-Path $root 'b\c\node_modules')
            (Join-Path $root 'keep')
            (Join-Path $root 'node_modules_not')
        ) | Out-Null
        # a file inside one target, to prove recursive removal
        Set-Content -LiteralPath (Join-Path $root 'a\node_modules\pkg.txt') -Value 'x'
    }
    AfterEach {
        Remove-Item -LiteralPath $script:root -Recurse -Force -ErrorAction SilentlyContinue
    }

    It 'removes every folder that exactly matches the name, recursively' {
        Remove-FoldersByName -FolderName 'node_modules' -RootPath $root -Confirm:$false

        Join-Path $root 'a\node_modules'   | Should -Not -Exist
        Join-Path $root 'b\c\node_modules' | Should -Not -Exist
    }

    It 'leaves non-matching folders untouched' {
        Remove-FoldersByName -FolderName 'node_modules' -RootPath $root -Confirm:$false

        Join-Path $root 'keep'             | Should -Exist
        Join-Path $root 'node_modules_not' | Should -Exist   # name does not match exactly
    }

    It 'removes nothing under -WhatIf' {
        Remove-FoldersByName -FolderName 'node_modules' -RootPath $root -WhatIf

        Join-Path $root 'a\node_modules'   | Should -Exist
        Join-Path $root 'b\c\node_modules' | Should -Exist
    }

    It 'writes an error when the root path does not exist' {
        Remove-FoldersByName -FolderName 'node_modules' -RootPath (Join-Path $TestDrive 'missing') -Confirm:$false -ErrorVariable err -ErrorAction SilentlyContinue
        $err | Should -Not -BeNullOrEmpty
    }
}
