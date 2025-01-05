param (
    [string]$folderName,
    [string]$rootPath,
    [switch]$WhatIf,
    [switch]$Confirm
)
try {
    # Check if folderName or rootPath were not specified
    if (-not $folderName) {
        throw "Error: folderName parameter is required."
    }

    if (-not $rootPath) {
        throw "Error: rootPath parameter is required."
    }

    # Find the folders and remove them
    Get-ChildItem -Path $rootPath -Recurse -Directory | Where-Object { $_.Name -eq $folderName } | ForEach-Object {
        Remove-Item -Path $_.FullName -Recurse -Force -Verbose -ErrorAction Stop -WhatIf:$WhatIf -Confirm:$Confirm
    }
}
catch {
    Write-Host $_.Exception.Message
}