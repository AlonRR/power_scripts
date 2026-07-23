@{
    ModuleVersion      = '1.0.0'
    Author             = 'Script Author'
    Description        = 'Functions for sorting and organizing pictures'
    PowerShellVersion  = '5.1'
    RootModule         = 'PictureSorting.psm1'
    RequiredAssemblies = @('System.Drawing')
    FunctionsToExport  = @(
        'Get-DateTakenPropertyIndex',
        'Get-FileDate',
        'Get-MemoryUsage',
        'Get-UniqueFilePath',
        'Get-MetricsSummary',
        'Get-FileLock',
        'Confirm-ImageFile',
        'Wait-FileOperation',
        'Write-ProcessLog',
        'Write-ProcessError',
        'Write-ProgressStatus',
        'Move-PictureToDateFolder',
        'Invoke-ImageBatch'
    )
}
