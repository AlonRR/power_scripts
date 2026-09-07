# power_scripts

Standalone **PowerShell utilities and modules** for this Windows workstation. Not homelab
infrastructure — nothing here deploys to a server.

## Where the documentation is

This repo documents itself; there is no manual page elsewhere.

| Looking for | Go to |
|---|---|
| The conventions every script here follows | `CODING-STANDARDS.md` |
| What the analyser enforces | `PSScriptAnalyzerSettings.psd1` |
| PowerShell traps that pass silently | the `powershell-parsing-traps` and `powershell-script-encoding` skills |

## Layout

| Path | What it is |
|---|---|
| `Modules/PictureSorting/` | The largest piece — sorts photos, including DNG raws. |
| `MassRemove/` | Bulk-removal module. |
| `CustomRules/PipelineOperatorPosition/` | A **custom PSScriptAnalyzer rule** for pipeline style. |
| `Tests/` | Pester suites, one per module. |
| `*.ps1` at root | Single-purpose utilities: `wake_on_lan`, `ssh-setup`, `list_folders_size`, `show_edge_workspaces`, `shell_hist`, `get-env-variable`, `create_relative_shortcut`. |

## How to run the tests

```powershell
.\Invoke-Tests.ps1                    # whole suite
.\Invoke-Tests.ps1 -Path Tests\PictureSorting.Tests.ps1
```

> Windows ships **Pester 3.4, which cannot run these tests.** `Invoke-Tests.ps1` prefers an
> installed Pester 5+, and otherwise downloads one into a gitignored `.pester\` cache with
> `Save-Module` — no admin rights, no global install. It **exits with the number of failed tests**,
> so it doubles as a CI gate.

Requires **PowerShell 7+** (the runner declares `#Requires -Version 7.0`); individual scripts
target 5.1.

## Style, before you add a script

Read `CODING-STANDARDS.md` first — it fixes the script skeleton, and the analyser settings enforce
part of it. Format pipelines with `.\Format-PipelineOperator.ps1`.

---

_Parts of this repository were drafted with the help of an LLM agent; reviewed and verified locally._
