# PowerShell coding standards

The conventions this repo's scripts are held to. Distilled from the
[PoshCode PowerShell Practice and Style guide](https://github.com/PoshCode/PowerShellPracticeAndStyle)
and a [2025 enterprise best-practices guide](https://dstreefkerk.github.io/2025-06-powershell-scripting-best-practices/),
scoped to the small utility scripts kept here. Enforced by `PSScriptAnalyzerSettings.psd1`.

## Script skeleton

Every non-trivial script follows this order:

```powershell
#Requires -Version 5.1
<#
.SYNOPSIS  One line.
.DESCRIPTION  What it does and why.
.PARAMETER Name  Each parameter.
.EXAMPLE  A real invocation.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]$Thing
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ... body ...
```

- **`#Requires -Version`** — fail fast if the host is too old. Add `#Requires -RunAsAdministrator`
  when elevation is mandatory, `#Requires -Modules X` for dependencies.
- **Comment-based help** — so `Get-Help` works. Documents intent, not mechanics.
- **`param()` block** — always present, right after help, before any code.
- **`Set-StrictMode -Version Latest`** — the "Option Explicit" of PowerShell; catches typos and
  use-before-assign.
- **`$ErrorActionPreference = 'Stop'`** — make errors terminating by default so `try/catch` works.

## Naming

- Functions: **approved Verb-Noun** only (`Get-Verb`), singular noun — `Remove-EmptyFolder`, not
  `mass_remove_folder` or `Cleanup-Folders`.
- PascalCase for functions and parameters; camelCase for locals. Descriptive, not `$x`.
- No aliases in scripts: `Where-Object` not `?`, `ForEach-Object` not `%`, `Get-ChildItem` not `ls`.
  Full parameter names, not positional.

## Parameters

- Validate at the boundary: `[ValidateNotNullOrEmpty()]`, `[ValidateSet()]`, `[ValidateRange()]`,
  `[ValidateScript()]` — let PowerShell reject bad input before the body runs.
- `[Parameter(Mandatory)]` instead of `Read-Host` prompts, so scripts stay automatable.
- Switches: `[switch]$Force`, never `[switch]$Force = $false`.
- Counts that can't go negative: `[uint32]`.
- Treat parameters as read-only; copy to a local if you must transform.

## State changes and safety

- Any destructive function: `[CmdletBinding(SupportsShouldProcess)]`, and gate the action with
  `if ($PSCmdlet.ShouldProcess($target, $action)) { ... }`. This gives `-WhatIf` and `-Confirm` for
  free. Set `ConfirmImpact = 'High'` on genuinely dangerous ones (bulk delete, remote power).

## Errors

- Wrap risky work in `try/catch`, with `finally` for cleanup (dispose handles, reset preferences).
- Convert non-terminating errors with `-ErrorAction Stop` (or the scope-wide preference) or a `catch`
  never fires.
- Capture `$err = $_` first thing in a catch; `$_` mutates.
- Never swallow silently — no empty `catch {}`. Log with `Write-Error`/`Write-Warning`, or rethrow.
- `Write-Error` for non-fatal, `throw` / `$PSCmdlet.ThrowTerminatingError()` for fatal.

## Output

- Emit **objects** (`[pscustomobject]`), not formatted text. No `Format-Table`/`Format-List` inside a
  script — let the caller decide.
- `Write-Host` only for genuinely interactive messages, never for data. `Write-Verbose` for progress,
  `Write-Output` (or bare output) for results.

## Performance

- Filter at the source (`-Filter`, `Get-WinEvent -FilterHashtable`), not `... | Where-Object` after
  pulling everything.
- Never `$array += $x` in a loop (O(n²)); use `[System.Collections.Generic.List[object]]::new()` +
  `.Add()`, or capture the loop's output directly.

## Security

- No `Invoke-Expression` on anything derived from input — command injection.
- No hardcoded secrets, not even in comments (they end up in git history and backups). Passwords are
  `[pscredential]`, not `[string]`; pull from SecretManagement / Credential Manager. Keep `.env`
  gitignored.
- Least privilege — don't require admin unless the task genuinely needs it.

## Portability

- `Join-Path` / `[System.IO.Path]::Combine()` for paths, never string concatenation with `\`.
- Prefer `Get-CimInstance` over `Get-WmiObject`.
- Files saved UTF-8 (no BOM); repo normalizes to LF via `.gitattributes`.

## Layout

- 4-space indent, no tabs. Lines ≤ ~120 chars. Break long pipelines with `|` starting the next line.
- Comment **why**, not what.
- Keep functions focused; split anything past a few hundred lines. Reusable logic goes in a module
  under `Modules/` with a `.psd1` manifest, not a loose root `.ps1`.
- Run **PSScriptAnalyzer** before committing; address the findings.

## Testing

- Tests live in `Tests/` as Pester files (`*.Tests.ps1`) and require **Pester 5+**
  (Windows ships 3.4, which won't run them). Install with
  `Install-Module Pester -Scope CurrentUser -Force -SkipPublisherCheck`, or `Save-Module` it to a
  local path and import that.
- Run the suite from the repo root: `Invoke-Pester -Path .\Tests`.
- Use `$TestDrive` for scratch files (Pester auto-cleans it), `InModuleScope` to reach a module's
  private functions, and real fixtures over mocks where practical — the picture-sorting tests build
  actual JPEGs (some with injected EXIF) rather than mocking the Shell COM layer, which is how they
  caught bugs a mock would have hidden.
