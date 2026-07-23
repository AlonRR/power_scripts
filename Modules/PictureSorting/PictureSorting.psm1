#Requires -Version 7.0

Set-StrictMode -Version Latest

# Initialize script-scope variables with proper types
$script:metrics = @{
    DateTakenUsed       = [int]0
    LastWriteTimeUsed   = [int]0
    InvalidDates        = [int]0
    TotalProcessingTime = [double]0
    FileCount           = [int]0
    StartTime           = [DateTime]::Now
    MemoryPeak          = [double]0
    ErrorsByCategory    = @{
        AccessDenied    = [int]0
        InvalidData     = [int]0
        InvalidResult   = [int]0
        OperationFailed = [int]0
    }
}
$script:DateTakenIndex = $null
$script:CurrentLogFile = $null
$script:totalItems = 0
$script:errors = @()
$script:processedCount = $script:skipCount = $script:errorCount = 0

<#
.SYNOPSIS
    Retries a file operation multiple times before failing.
.DESCRIPTION
    Executes the provided action scriptblock, retrying on failure up to the specified number of attempts.
.PARAMETER Action
    The scriptblock containing the file operation to execute.
.PARAMETER OperationName
    Name of the operation for logging purposes.
.PARAMETER MaxAttempts
    Maximum number of retry attempts. Default is 3.
.PARAMETER DelaySeconds
    Delay between retry attempts in seconds. Default is 2.
.OUTPUTS
    The result of the Action scriptblock if successful.
#>
function Wait-FileOperation {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][scriptblock]$Action,
        [Parameter(Mandatory)][string]$OperationName,
        [Parameter()][int]$MaxAttempts = 3,
        [Parameter()][int]$DelaySeconds = 2
    )

    $attempt = 1
    $lastError = $null
    $exponentialBackoff = $DelaySeconds

    do {
        try {
            $result = & $Action
            return $result
        } catch [System.IO.IOException] {
            $lastError = $_
            Write-Verbose "$($OperationName) - File access error on attempt $($attempt) of $($MaxAttempts): $_"
            if ($attempt -lt $MaxAttempts) {
                Start-Sleep -Seconds $exponentialBackoff
                $exponentialBackoff *= 2
            }
        } catch {
            $lastError = $_
            Write-Verbose "$($OperationName) - Error on attempt $($attempt) of $($MaxAttempts): $($_)"
            if ($attempt -lt $MaxAttempts) {
                Start-Sleep -Seconds $DelaySeconds
            }
        }
        $attempt++
    } while ($attempt -le $MaxAttempts)

    throw "Failed $OperationName after $MaxAttempts attempts: $lastError"
}

<#
.SYNOPSIS
    Checks if a file is locked by another process.
.OUTPUTS
    System.Boolean. True if file is locked, false otherwise.
#>
function Get-FileLock {
    [CmdletBinding()]
    [OutputType([System.Boolean])]
    param([Parameter(Mandatory)][string]$Path)

    try {
        $fileStream = $null
        try {
            $fileStream = [System.IO.File]::Open($Path, 'Open', 'Read', 'None')
            return $false
        } finally {
            if ($fileStream) {
                $fileStream.Dispose()
            }
        }
    } catch [System.UnauthorizedAccessException] {
        Write-Verbose "Access denied to file: $Path"
        return $true
    } catch [System.IO.IOException] {
        Write-Verbose "File is locked: $Path"
        return $true
    } catch {
        Write-Verbose "Error checking file lock: $_"
        return $true
    }
}

<#
.SYNOPSIS
    Generates a unique file path by appending a counter if needed.
.OUTPUTS
    System.String. The unique file path.
#>
function Get-UniqueFilePath {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)][string]$BasePath,
        [Parameter(Mandatory)][string]$FileName
    )

    $targetPath = Join-Path -Path $BasePath -ChildPath $FileName
    $counter = 1
    $baseName = [System.IO.Path]::GetFileNameWithoutExtension($FileName)
    $extension = [System.IO.Path]::GetExtension($FileName)

    while (Test-Path -Path $targetPath) {
        $newName = "{0}_{1}{2}" -f $baseName, $counter, $extension
        $targetPath = Join-Path -Path $BasePath -ChildPath $newName
        $counter++
    }

    return $targetPath
}

<#
.SYNOPSIS
    Processes a batch of image files.
#>
function Invoke-ImageBatch {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)][array]$Items,
        [Parameter(Mandatory)][hashtable]$ProcessParams,
        [Parameter()][hashtable]$ProcessedFiles,
        [Parameter()][string]$ResumeFile
    )

    if (-not $ProcessParams.ContainsKey('LogFile')) {
        throw "ProcessParams must contain a LogFile parameter"
    }

    foreach ($item in $Items) {
        if ($ProcessedFiles.ContainsKey($item.FullName)) {
            Write-Verbose "Skipping previously processed file: $($item.Name)"
            $script:skipCount++
            continue
        }

        try {
            Write-ProgressStatus -Item $item
            Move-PictureToDateFolder @ProcessParams -Item $item

            if ($ResumeFile) {
                $ProcessedFiles[$item.FullName] = [DateTime]::Now
                $ProcessedFiles | ConvertTo-Json | Set-Content -Path $ResumeFile -Force
            }
        } catch {
            Write-ProcessError -Item $item -ErrorRecord $_ -LogFile $ProcessParams.LogFile
            if ($ProcessParams.StopOnError) {
                break
            }
        }
    }
}

<#
.SYNOPSIS
    Updates the progress bar for picture processing.
#>
function Write-ProgressStatus {
    [CmdletBinding()]
    param([Parameter(Mandatory)][System.IO.FileInfo]$Item)

    try {
        $startTime = [DateTime]($script:metrics.StartTime)
        $elapsed = New-TimeSpan -Start $startTime -End ([DateTime]::Now)
        $remainingCount = $script:totalItems - ($script:processedCount + $script:skipCount + $script:errorCount)
        $avgTimePerFile = if ($script:processedCount -gt 0) {
            $elapsed.TotalSeconds / $script:processedCount
        } else {
            0
        }

        $estimatedRemaining = [TimeSpan]::FromSeconds($avgTimePerFile * $remainingCount)
        $percentComplete = ($script:processedCount + $script:skipCount + $script:errorCount) * 100 / $script:totalItems

        $progress = @{
            Activity         = 'Sorting Pictures'
            Status           = "Processing $($Item.Name)"
            PercentComplete  = $percentComplete
            CurrentOperation = "Estimated time remaining: $([math]::Round($estimatedRemaining.TotalMinutes, 1)) minutes"
        }
        Write-Progress @progress
    } catch {
        Write-Warning "Error updating progress: $_"
    }
}

<#
.SYNOPSIS
    Handles and logs processing errors.
#>
function Write-ProcessError {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][System.IO.FileInfo]$Item,
        [Parameter(Mandatory)][System.Management.Automation.ErrorRecord]$ErrorRecord,
        [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$LogFile
    )
    $errorMsg = "Error processing $($Item.FullName): $ErrorRecord"
    $script:errors += $errorMsg
    $script:errorCount++
    Write-Error $errorMsg
    Write-ProcessLog -Message $errorMsg -LogFile $LogFile
}

<#
.SYNOPSIS
    Gets the index of the "Date taken" property from Shell.Application.
.OUTPUTS
    System.Int32. The index of the date taken property, or -1 if not found.
#>
function Get-DateTakenPropertyIndex {
    [CmdletBinding()]
    [OutputType([System.Int32])]
    param([Parameter(Mandatory)][System.__ComObject]$Folder)

    if ($script:DateTakenIndex -and $script:DateTakenIndex -gt 0) {
        return $script:DateTakenIndex
    }
    for ($i = 0; $i -lt 300; $i++) {
        try {
            if ($folder.GetDetailsOf($null, $i) -eq "Date taken") {
                $script:DateTakenIndex = $i
                return $i
            }
        } catch {
            Write-Verbose "Error checking index $($i): $_"
            continue
        }
    }
    $script:DateTakenIndex = -1
    return -1
}

<#
.SYNOPSIS
    Extracts the date taken from an image file.
.OUTPUTS
    System.Collections.Hashtable. Contains Date and Source properties.
#>
function Get-FileDate {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)][System.__ComObject]$Shell,
        [Parameter(Mandatory)][System.IO.FileInfo]$Item,
        [Parameter()][string[]]$DateFormats,
        [Parameter()][DateTime]$MinDate = '1970-01-01',
        [Parameter()][DateTime]$MaxDate = (Get-Date)
    )

    try {
        $folder = $Shell.Namespace($Item.DirectoryName)
        $file = $folder.ParseName($Item.Name)
        $dateTakenIndex = Get-DateTakenPropertyIndex $folder

        if ($dateTakenIndex -lt 0) {
            return @{
                Date   = $Item.LastWriteTime
                Source = "LastWriteTime"
            }
        }

        $dateTaken = $folder.GetDetailsOf($file, $dateTakenIndex)
        if ([string]::IsNullOrEmpty($dateTaken) -or $dateTaken -match '^\s*$') {
            return @{
                Date   = $Item.LastWriteTime
                Source = "LastWriteTime"
            }
        }

        $dateTaken = $dateTaken -replace '[^\x20-\x7E]', ''
        try {
            $parsedDate = $null
            foreach ($format in $DateFormats) {
                if ([DateTime]::TryParseExact($dateTaken, $format, [System.Globalization.CultureInfo]::InvariantCulture,
                        [System.Globalization.DateTimeStyles]::None, [ref]$parsedDate)) {
                    break
                }
            }

            if (-not $parsedDate) {
                $parsedDate = Get-Date $dateTaken -ErrorAction Stop
            }

            if ($parsedDate -gt $MaxDate -or $parsedDate -lt $MinDate) {
                Write-Verbose "Invalid date for $($Item.Name): $dateTaken (outside specified range)"
                $script:metrics.InvalidDates++
                return @{
                    Date   = $Item.LastWriteTime
                    Source = "LastWriteTime"
                }
            }
            $script:metrics.DateTakenUsed++
            return @{
                Date   = $parsedDate
                Source = "DateTaken"
            }
        } catch {
            Write-Verbose "Could not parse date taken for $($Item.Name): $dateTaken"
            $script:metrics.LastWriteTimeUsed++
            return @{
                Date   = $Item.LastWriteTime
                Source = "LastWriteTime"
            }
        }
    } catch {
        Write-Verbose "Error getting file date: $_"
        return @{
            Date   = $Item.LastWriteTime
            Source = "LastWriteTime"
        }
    }
}

<#
.SYNOPSIS
    Validates if a file is a valid image.
.OUTPUTS
    System.Boolean. True if file is a valid image, false otherwise.
#>
function Confirm-ImageFile {
    [CmdletBinding()]
    [OutputType([bool])]
    param([Parameter(Mandatory)][string]$Path)

    $stream = $null
    $img = $null
    try {
        Add-Type -AssemblyName System.Drawing
        $stream = [System.IO.File]::OpenRead($Path)
        $img = [System.Drawing.Image]::FromStream($stream, $false, $false)
        return $true
    } catch {
        return $false
    } finally {
        if ($img) { $img.Dispose() }
        if ($stream) { $stream.Dispose() }
    }
}

<#
.SYNOPSIS
    Gets current memory usage of the PowerShell process.
.OUTPUTS
    System.Double. Memory usage in MB.
#>
function Get-MemoryUsage {
    [CmdletBinding()]
    [OutputType([double])]
    param()

    $process = Get-Process -Id $pid
    return [math]::Round($process.WorkingSet64 / 1MB, 2)
}

<#
.SYNOPSIS
    Writes a message to the process log file.
#>
function Write-ProcessLog {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Message,
        [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$LogFile
    )

    if (-not $WhatIfPreference) {
        $logMessage = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss'): $Message"
        Add-Content -Path $LogFile -Value $logMessage -ErrorAction Stop
    }
    Write-Verbose $Message
}

<#
.SYNOPSIS
    Generates a summary of processing metrics.
.OUTPUTS
    System.String. Formatted metrics summary.
#>
function Get-MetricsSummary {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)][hashtable]$Metrics,
        [bool]$IsDryRun,
        [int]$ProcessedFilesCount
    )

    try {
        $runtime = if ($Metrics.ContainsKey('EndTime')) {
            (New-TimeSpan -Start ([DateTime]$Metrics.StartTime) -End ([DateTime]$Metrics.EndTime)).TotalMinutes
        } else {
            (New-TimeSpan -Start ([DateTime]$Metrics.StartTime) -End ([DateTime]::Now)).TotalMinutes
        }
    } catch {
        Write-Warning "Error calculating metrics: $_"
        $runtime = 0
    }

    $avgTime = if ($Metrics.FileCount -gt 0) {
        [math]::Round($Metrics.TotalProcessingTime / $Metrics.FileCount, 2)
    } else {
        0
    }

    $sections = @{
        Operation   = @(
            "Files using DateTaken: $($Metrics.DateTakenUsed)"
            "Files using LastWriteTime: $($Metrics.LastWriteTimeUsed)"
            "Files with invalid dates: $($Metrics.InvalidDates)"
            "Previously processed files skipped: $ProcessedFilesCount"
        )
        Performance = @(
            "Average processing time per file: $([math]::Round($avgTime, 2)) seconds"
            "Peak Memory Usage: $($Metrics.MemoryPeak) MB"
            "Total Runtime: $([math]::Round($runtime, 1)) minutes"
        )
        Errors      = @(
            "Access Denied: $($Metrics.ErrorsByCategory.AccessDenied)"
            "Invalid Data: $($Metrics.ErrorsByCategory.InvalidData)"
            "Invalid Result: $($Metrics.ErrorsByCategory.InvalidResult)"
            "Other Failures: $($Metrics.ErrorsByCategory.OperationFailed)"
        )
    }

    $output = [System.Collections.ArrayList]@()
    if ($IsDryRun) {
        $output.Add("Dry run completed - no files were actually moved") | Out-Null
    }
    foreach ($section in $sections.GetEnumerator()) {
        $output.Add("") | Out-Null
        $output.Add("$($section.Key) Metrics:") | Out-Null
        $output.AddRange($section.Value)
    }

    return $output -join "`n"
}

<#
.SYNOPSIS
    Moves a picture file to a dated folder structure.
.DESCRIPTION
    Moves an image file to a destination folder structure organized by year and month,
    based on the image's date taken or last write time.
#>
function Move-PictureToDateFolder {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [System.IO.FileInfo]$Item,

        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [ValidateScript({
                if (!(Test-Path $_)) {
                    throw "Directory does not exist: $_"
                }
                return $true
            })]
        [string]$DestinationDirectory,

        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [System.__ComObject]$Shell,

        [Parameter()]
        [string[]]$DateFormats,

        [Parameter()]
        [ValidateRange(0, [long]::MaxValue)]
        [long]$MaxFileSize = 500MB,

        [Parameter()]
        [int]$LockRetryDelay = 1,
        [int]$LockRetryCount = 3,

        [Parameter()]
        [System.Threading.CancellationToken]$CancellationToken,

        [Parameter()]
        [DateTime]$MinDate,

        [Parameter()]
        [DateTime]$MaxDate,

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string]$LogFile = $Script:CurrentLogFile
    )

    begin {
        try {
            $startTime = [DateTime]::Now
            $script:metrics.FileCount++

            # Fix: Better error message for size limit
            if ($Item.Length -gt $MaxFileSize) {
                $sizeInMB = [math]::Round($MaxFileSize / 1MB, 2)
                throw [System.IO.IOException]::new(
                    "File exceeds size limit of ${sizeInMB}MB: $($Item.FullName)"
                )
            }
        } catch {
            Write-Error -Exception $_.Exception
            throw
        }
    }

    process {
        try {
            # Check cancellation
            if ($CancellationToken -and $CancellationToken.IsCancellationRequested) {
                throw "Operation cancelled by user"
            }

            # Verify file is accessible and not locked
            if (Get-FileLock -Path $Item.FullName) {
                throw "File is locked by another process: $($Item.FullName)"
            }

            # Validate image file
            if (-not (Confirm-ImageFile -Path $Item.FullName)) {
                throw "Invalid or corrupted image file: $($Item.FullName)"
            }

            # Get file date
            $dateInfo = Get-FileDate -Shell $Shell -Item $Item -DateFormats $DateFormats -MinDate $MinDate -MaxDate $MaxDate
            $fileDate = $dateInfo.Date

            # Create year and month folders
            $yearFolder = Join-Path -Path $DestinationDirectory -ChildPath $fileDate.ToString('yyyy')
            $monthFolder = Join-Path -Path $yearFolder -ChildPath $fileDate.ToString('MM-MMMM')
            foreach ($folder in @($yearFolder, $monthFolder)) {
                if (-not (Test-Path -Path $folder)) {
                    if ($PSCmdlet.ShouldProcess($folder, "Create Directory")) {
                        $null = New-Item -ItemType Directory -Path $folder -Force
                    }
                }
            }

            # Generate unique destination path
            $destinationPath = Get-UniqueFilePath -BasePath $monthFolder -FileName $Item.Name

            # Move file
            if ($PSCmdlet.ShouldProcess($destinationPath, "Move file")) {
                Wait-FileOperation -Action {
                    Move-Item -Path $Item.FullName -Destination $destinationPath -Force
                } -OperationName "Move file" -MaxAttempts $LockRetryCount -DelaySeconds $LockRetryDelay
                Write-ProcessLog -Message "Moved $($Item.FullName) to $destinationPath (Get-Date source: $($dateInfo.Source))" -LogFile $LogFile
                $script:processedCount++
            }
        } catch {
            $errorCategory = switch -Regex ($_.Exception.Message) {
                'access.*denied|locked' {
                    'AccessDenied'
                }
                'Invalid.*file|corrupted' {
                    'InvalidData'
                }
                'Invalid.*date' {
                    'InvalidResult'
                }
                default {
                    'OperationFailed'
                }
            }
            $script:metrics.ErrorsByCategory[$errorCategory]++
            throw
        }
    }

    end {
        try {
            # Fix: Ensure consistent time span calculation
            $endTime = [DateTime]::Now
            $duration = New-TimeSpan -Start $startTime -End $endTime
            $script:metrics.TotalProcessingTime += $duration.TotalSeconds

            # Fix: Add null check for memory usage
            $currentMemory = Get-MemoryUsage
            if ($null -ne $currentMemory -and $currentMemory -gt ($script:metrics.MemoryPeak ?? 0)) {
                $script:metrics.MemoryPeak = $currentMemory
            }
        } catch {
            Write-Warning "Error updating metrics: $_"
        }
    }
}

<#
.SYNOPSIS
    Organizes pictures into folders based on their date taken or last modified date.

.DESCRIPTION
    Moves image files from a source directory to a destination directory, organizing them into
    year/month subfolders based on either EXIF "date taken" or last write time. Supports batch
    processing, resume, dry-run, and validation options.

.PARAMETER SourceDirectory
    The directory containing the images to organize. Must be an existing directory.

.PARAMETER DestinationDirectory
    The root directory where organized folders will be created (year/month subfolders).

.PARAMETER FileExtensions
    Extensions to process. Defaults to common image formats.

.PARAMETER LogFile
    Path to the log file (.log extension). Defaults to sort_pictures.log in the current directory.

.PARAMETER ConfirmAll
    Processes all files without the per-run confirmation prompt.

.PARAMETER StopOnError
    Stops processing on the first error. By default, continues with the next file.

.PARAMETER MinDate
    Earliest valid date; images dated earlier fall back to last write time. Default 1970-01-01.

.PARAMETER MaxDate
    Latest valid date; images dated later fall back to last write time. Default is now.

.PARAMETER DryRun
    Shows what would happen without moving files.

.PARAMETER DateFormats
    Custom date formats to try when parsing EXIF data.

.PARAMETER MaxFileSize
    Maximum allowed file size in bytes. Default 500 MB.

.PARAMETER ResumeFile
    JSON file tracking processed files, for resume capability.

.PARAMETER EnableCancel
    Enables cancellation support during processing.

.PARAMETER BatchSize
    Number of files per batch. Default 100.

.EXAMPLE
    Move-PicturesByDate -Source C:\Photos -Destination D:\Organized -DryRun

.EXAMPLE
    Move-PicturesByDate -Source C:\Photos -Destination D:\Organized -ConfirmAll

.INPUTS
    None. You cannot pipe objects to Move-PicturesByDate.

.OUTPUTS
    System.Int32. Returns 0 for success, 1 if errors occurred.

.NOTES
    Requires PowerShell 7.0 or later. Uses the Shell.Application COM object for EXIF extraction.
    Creates a Destination\YYYY\MM-MonthName folder structure.
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
        [string]$LogFile = 'sort_pictures.log',

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
        $ErrorActionPreference = 'Stop'
        $InformationPreference = 'Continue'

        # Resolve the log path and ensure its directory and file exist.
        $resolvedLogPath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($LogFile)
        $logDirectory = Split-Path -Path $resolvedLogPath -Parent
        if (-not (Test-Path -Path $logDirectory)) {
            $null = New-Item -ItemType Directory -Path $logDirectory -Force
            Write-Verbose "Created log directory: $logDirectory"
        }
        $script:CurrentLogFile = $resolvedLogPath
        if (-not $WhatIfPreference -and -not (Test-Path -Path $resolvedLogPath)) {
            $null = New-Item -ItemType File -Path $resolvedLogPath -Force
            Write-Verbose "Created log file at: $resolvedLogPath"
        }
        Write-ProcessLog -Message 'Script started' -LogFile $resolvedLogPath

        if (-not (Test-Path -Path $DestinationDirectory)) {
            throw "Destination directory not found: $DestinationDirectory"
        }

        # Reset per-run state.
        $script:DateTakenIndex = $null
        $script:totalItems = 0
        $script:errors = @()
        $script:processedCount = $script:skipCount = $script:errorCount = 0
        $script:metrics = @{
            DateTakenUsed       = [int]0
            LastWriteTimeUsed   = [int]0
            InvalidDates        = [int]0
            TotalProcessingTime = [double]0
            FileCount           = [int]0
            StartTime           = [DateTime]::Now
            MemoryPeak          = [double]0
            ErrorsByCategory    = @{
                AccessDenied    = [int]0
                InvalidData     = [int]0
                InvalidResult   = [int]0
                OperationFailed = [int]0
            }
        }

        $shell = try {
            New-Object -ComObject Shell.Application
        } catch {
            throw "Failed to initialize Shell.Application: $_"
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
            LogFile              = $resolvedLogPath
        }
    }

    process {
        try {
            $items = @(Get-ChildItem -Path $SourceDirectory -File -Recurse
                | Where-Object { $FileExtensions -contains $_.Extension.ToLower() })

            $script:totalItems = $items.Count
            Write-ProcessLog -Message "Found $($items.Count) matching files to process" -LogFile $resolvedLogPath

            if (-not $ConfirmAll -and -not $PSCmdlet.ShouldProcess("$($items.Count) files", 'Process all')) {
                Write-Verbose 'Operation cancelled by user'
                $script:metrics['EndTime'] = Get-Date
                return 0
            }

            for ($i = 0; $i -lt $items.Count; $i += $BatchSize) {
                $batch = $items | Select-Object -Skip $i -First $BatchSize
                $batchParams = $processParams.Clone()
                $batchParams['LogFile'] = $resolvedLogPath
                Invoke-ImageBatch -Items $batch -ProcessParams $batchParams -ProcessedFiles $processedFiles -ResumeFile $ResumeFile
                [System.GC]::Collect()
                Start-Sleep -Milliseconds 100
            }

            Write-Information @"
Processing Summary:
Files processed: $($script:processedCount)
Files skipped: $($script:skipCount)
Errors encountered: $($script:errorCount)
"@

            if ($script:errors) {
                Write-Warning 'The following errors occurred:'
                $script:errors | ForEach-Object { Write-Warning $_ }
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

            if (-not $script:metrics.ContainsKey('EndTime')) {
                $script:metrics['EndTime'] = Get-Date
            }
        }
    }

    end {
        $summary = Get-MetricsSummary -Metrics $script:metrics -IsDryRun $DryRun -ProcessedFilesCount $processedFiles.Count
        Write-Information $summary

        Remove-Variable -Name CurrentLogFile, DateTakenIndex -Scope Script -ErrorAction SilentlyContinue
    }
}

Set-Alias -Name Sort-Pictures -Value Move-PicturesByDate
Set-Alias -Name Sort_Pictures_By_Date_Taken -Value Move-PicturesByDate

# Only the public command (and its aliases) is exported; the helpers above stay private.
Export-ModuleMember -Function Move-PicturesByDate -Alias Sort-Pictures, Sort_Pictures_By_Date_Taken
