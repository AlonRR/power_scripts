#Requires -Version 7.0
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }
<#
    Pester tests for ssh-setup.ps1 (Add-SshPublicKeyToRemote).

    The default key must be the caller's OWN public key. It used to be a key file shipped in this
    repo, so anyone who ran the script without -PublicKeyPath authorised the repo owner's key on
    their own host. Nothing here opens an SSH connection: the default is read from the parameter
    block and evaluated, never passed to ssh.

    Run:  Invoke-Pester -Path .\Tests\SshSetup.Tests.ps1
#>

BeforeAll {
    $script:repo = Split-Path $PSScriptRoot -Parent
    . (Join-Path $repo 'ssh-setup.ps1')
    $param = (Get-Command Add-SshPublicKeyToRemote).ScriptBlock.Ast.Body.ParamBlock.Parameters
        | Where-Object { $_.Name.VariablePath.UserPath -eq 'PublicKeyPath' }
    $script:defaultText = $param.DefaultValue.Extent.Text
}

Describe 'Add-SshPublicKeyToRemote default key' {
    It 'is not a file inside the repository' {
        $defaultText | Should -Not -Match 'PSScriptRoot'
    }

    It "resolves to the caller's own ~/.ssh/id_ed25519.pub" {
        & ([scriptblock]::Create($defaultText))
            | Should -Be (Join-Path -Path $HOME -ChildPath '.ssh' -AdditionalChildPath 'id_ed25519.pub')
    }

    It 'ships no public key file in the repository' {
        Get-ChildItem -LiteralPath $repo -Filter '*.pub' -File | Should -BeNullOrEmpty
    }
}
