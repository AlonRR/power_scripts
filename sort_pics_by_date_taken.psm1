using module ./Modules/PictureSorting/PictureSorting.psm1

<#
.SYNOPSIS
    Organizes pictures into folders based on their date taken or last modified date.

.DESCRIPTION
    The Move-PicturesByDate cmdlet moves image files from a source directory to a destination directory,
    organizing them into subfolders by year and month based on either EXIF date taken or last write time.
    It supports batch processing, resume capabilities, and various validation options.

.PARAMETER SourceDirectory
    The directory containing the images to organize. Must be an existing directory.

.PARAMETER DestinationDirectory
    The root directory where organized folders will be created. Will create year/month subfolders.

.PARAMETER FileExtensions
    Array of file extensions to process. Defaults to common image formats (.jpg, .jpeg, .png, .gif, .bmp, .tiff).

.PARAMETER LogFile
    Path to the log file. Must have a .log extension. Defaults to sort_pictures.log in the script directory.

.PARAMETER ConfirmAll
    Suppresses confirmation prompts for all operations.

.PARAMETER StopOnError
    Stops processing if an error occurs. By default, continues with next file.

.PARAMETER MinDate
    Earliest valid date for images. Dates before this will use last write time instead.
    Default is 1970-01-01.

.PARAMETER MaxDate
    Latest valid date for images. Dates after this will use last write time instead.
    Default is current date.

.PARAMETER DryRun
    Shows what would happen without making actual changes.

.PARAMETER DateFormats
    Array of custom date formats to try when parsing EXIF data.

.PARAMETER MaxFileSize
    Maximum allowed file size in bytes. Default is 500MB.

.PARAMETER ResumeFile
    Path to a JSON file tracking processed files for resume capability.

.PARAMETER EnableCancel
    Enables cancellation support during processing.

.PARAMETER BatchSize
    Number of files to process in each batch. Default is 100.

.EXAMPLE
    Move-PicturesByDate -Source "C:\Photos" -Destination "D:\Organized" -DryRun
    Shows what changes would be made without moving files.

.EXAMPLE
    Move-PicturesByDate -Source "C:\Photos" -Destination "D:\Organized" -ConfirmAll
    Moves all pictures without prompting for confirmation.

.EXAMPLE
    Move-PicturesByDate -Source "C:\Photos" -Destination "D:\Organized" -FileExtensions @('.jpg','.png')
    Only processes .jpg and .png files.

.EXAMPLE
    Move-PicturesByDate -Source "C:\Photos" -Destination "D:\Organized" -ResumeFile "resume.json"
    Processes files with resume capability, storing progress in resume.json.

.INPUTS
    None. You cannot pipe objects to Move-PicturesByDate.

.OUTPUTS
    System.Int32. Returns 0 for success, 1 if errors occurred.

.NOTES
    Requires PowerShell 5.1 or later
    Uses Shell.Application COM object for EXIF data extraction
    Creates year/month folder structure: Destination\YYYY\MM-MonthName

.LINK
    https://github.com/yourusername/repository

#>
function Move-PicturesByDate {
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High', DefaultParameterSetName = 'Default')]
    [OutputType([System.Int32])]
    param (
        [Parameter(Mandatory = $true, Position = 0)]
        [ValidateScript({ 
                if (!(Test-Path $_ -PathType Container)) {
                    throw "Source directory not found: $_"
                }
                return $true
            })]
        [Alias('Source')]
        [string]$SourceDirectory,

        [Parameter(Mandatory = $true, Position = 1)]
        [ValidateNotNullOrEmpty()]
        [Alias('Destination')]
        [string]$DestinationDirectory,

        [Parameter()]
        [ValidateScript({
                $invalidExtensions = $_ | Where-Object { $_ -notmatch '^\.[a-zA-Z0-9]+$' }
                if ($invalidExtensions) {
                    throw "Invalid file extensions: $($invalidExtensions -join ', ')"
                }
                return $true
            })]
        [string[]]$FileExtensions = @('.jpg', '.jpeg', '.png', '.gif', '.bmp', '.tiff'),

        [Parameter()]
        [ValidateScript({
                if ([string]::IsNullOrWhiteSpace($_)) {
                    throw 'LogFile path cannot be empty'
                }
                if ($_ -notmatch '\.log$') {
                    throw 'Log file must have .log extension'
                }
                return $true
            })]
        [string]$LogFile = "sort_pictures.log",

        [Parameter(ParameterSetName = 'NoConfirm')]
        [switch]$ConfirmAll,

        [Parameter()]
        [switch]$StopOnError,

        [Parameter()]
        [ValidateScript({
                if ($_ -gt (Get-Date)) {
                    throw 'MinDate cannot be in the future'
                }
                return $true
            })]
        [DateTime]$MinDate = '1970-01-01',
        
        [Parameter()]
        [ValidateScript({
                if ($_ -lt $MinDate) {
                    throw 'MaxDate must be greater than MinDate'
                }
                return $true
            })]
        [DateTime]$MaxDate = (Get-Date),

        [Parameter()]
        [switch]$DryRun,

        [Parameter()]
        [string[]]$DateFormats,

        [Parameter()]
        [ValidateRange(0, [long]::MaxValue)]
        [long]$MaxFileSize = 500MB,

        [Parameter()]
        [string]$ResumeFile,

        [Parameter()]
        [switch]$EnableCancel,
        
        [Parameter()]
        [int]$BatchSize = 100
    )

    begin {
        # Initialize module state
        Remove-Variable -Name DateTakenIndex -Scope Script -ErrorAction SilentlyContinue
        
        # Resolve relative path to absolute path
        $resolvedLogPath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($LogFile)
        $logDirectory = Split-Path -Path $resolvedLogPath -Parent

        # Ensure log directory exists
        if (-not (Test-Path -Path $logDirectory)) {
            $null = New-Item -ItemType Directory -Path $logDirectory -Force
            Write-Verbose "Created log directory: $logDirectory"
        }
        
        # Set the resolved log path
        $Script:CurrentLogFile = $resolvedLogPath
        
        # Initialize log file if needed
        if (-not $WhatIfPreference -and -not (Test-Path -Path $resolvedLogPath)) {
            $null = New-Item -ItemType File -Path $resolvedLogPath -Force
            Write-Verbose "Created log file at: $resolvedLogPath"
        }

        Write-ProcessLog -Message 'Script started' -LogFile $resolvedLogPath

        # Initialize
        $ErrorActionPreference = 'Stop'
        $InformationPreference = 'Continue'
        $errors = @()
        $processedCount = $skipCount = $errorCount = 0

        # Get shell COM object
        $shell = try {
            New-Object -ComObject Shell.Application
        } catch {
            Write-Error "Failed to initialize Shell.Application: $_"
            return
        }

        if (-not (Test-Path -Path $DestinationDirectory)) {
            throw "Destination directory not found: $DestinationDirectory"
        }

        # Initialize metrics with proper types
        $script:metrics = @{
            DateTakenUsed       = [int]0
            LastWriteTimeUsed   = [int]0
            InvalidDates        = [int]0
            TotalProcessingTime = [double]0
            FileCount           = [int]0
            StartTime          = [DateTime]::Now
            MemoryPeak         = [double]0
            ErrorsByCategory    = @{
                AccessDenied    = [int]0
                InvalidData     = [int]0
                InvalidResult   = [int]0
                OperationFailed = [int]0
            }
        }

        if ($DryRun) {
            Write-Warning 'Running in dry-run mode. No files will be moved.'
            $WhatIfPreference = $true
        }

        $processedFiles = @{}
        if ($ResumeFile -and (Test-Path $ResumeFile)) {
            $processedFiles = Get-Content $ResumeFile | ConvertFrom-Json -AsHashtable
            Write-Verbose "Loaded $(($processedFiles.Keys).Count) processed files from resume file"
        }

        $cancellationSource = if ($EnableCancel) {
            New-Object System.Threading.CancellationTokenSource
        }

        # Add start time to metrics
        $script:metrics['StartTime'] = Get-Date
        $script:metrics['MemoryPeak'] = 0
        $script:totalItems = 0
        $script:errors = @()
        $script:processedCount = $script:skipCount = $script:errorCount = 0

        # Add LogFile to process parameters
        $processParams = @{
            DestinationDirectory = $DestinationDirectory
            Shell                = $shell
            MinDate              = $MinDate
            MaxDate              = $MaxDate
            DateFormats          = $DateFormats
            MaxFileSize          = $MaxFileSize
            CancellationToken    = $cancellationSource?.Token
            WhatIf               = $WhatIfPreference
            StopOnError          = $StopOnError
            LogFile              = $resolvedLogPath  # Ensure this is set
        }
    }

    process {
        try {
            $items = @(Get-ChildItem -Path $SourceDirectory -File -Recurse | 
                Where-Object { $FileExtensions -contains $_.Extension.ToLower() })

            $script:totalItems = $items.Count
            Write-ProcessLog -Message "Found $($items.Count) matching files to process" -LogFile $resolvedLogPath

            # Confirm batch processing
            if (-not $ConfirmAll -and -not $PSCmdlet.ShouldProcess("$($items.Count) files", 'Process all')) {
                Write-Verbose 'Operation cancelled by user'
                # Update metrics even when cancelled in WhatIf mode
                $script:metrics['EndTime'] = Get-Date
                return 0
            }

            # Process files in batches
            for ($i = 0; $i -lt $items.Count; $i += $BatchSize) {
                $batch = $items | Select-Object -Skip $i -First $BatchSize
                $batchParams = $processParams.Clone()
                $batchParams['LogFile'] = $resolvedLogPath
                Invoke-ImageBatch -Items $batch -ProcessParams $batchParams -ProcessedFiles $processedFiles -ResumeFile $ResumeFile
                [System.GC]::Collect()
                Start-Sleep -Milliseconds 100
            }

            # Final summary
            Write-Information @"
Processing Summary:
Files processed: $processedCount
Files skipped: $skipCount
Errors encountered: $errorCount
"@

            if ($errors) {
                Write-Warning 'The following errors occurred:'
                $errors | ForEach-Object { Write-Warning $_ }
                return 1
            }
            return 0
        } finally {
            if ($cancellationSource) {
                $cancellationSource.Cancel()
                $cancellationSource.Dispose()
            }
            if ($shell) {
                [System.Runtime.Interopservices.Marshal]::ReleaseComObject($shell)
                [System.GC]::Collect()
                [System.GC]::WaitForPendingFinalizers()
            }
            Write-Progress -Activity 'Sorting Pictures' -Completed
            Write-ProcessLog -Message 'Script completed' -LogFile $resolvedLogPath
            
            # Ensure metrics has EndTime set
            if (-not $script:metrics.ContainsKey('EndTime')) {
                $script:metrics['EndTime'] = Get-Date
            }
        }
    }

    end {
        Write-Information (Get-MetricsSummary -Metrics $metrics `
                -IsDryRun $DryRun `
                -ProcessedFilesCount $processedFiles.Count)

        # Cleanup script-scope variables
        Remove-Variable -Name CurrentLogFile, DateTakenIndex -Scope Script -ErrorAction SilentlyContinue
    }
}

# Create aliases for backward compatibility and convenience
New-Alias -Name Sort-Pictures -Value Move-PicturesByDate
New-Alias -Name Sort_Pictures_By_Date_Taken -Value Move-PicturesByDate

Export-ModuleMember -Function Move-PicturesByDate -Alias Sort-Pictures, Sort_Pictures_By_Date_Taken