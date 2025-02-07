# Helper functions
function Get-DateTakenPropertyIndex {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [System.__ComObject]$Folder
    )
    # Cache the index to avoid repeated lookups
    if ($script:DateTakenIndex) {
        return $script:DateTakenIndex
    }
    for ($i = 0; $i -lt 300; $i++) {
        if ($folder.GetDetailsOf($null, $i) -eq "Date taken") {
            $script:DateTakenIndex = $i
            return $i
        }
    }
    return -1
}

function Wait-FileOperation {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [scriptblock]$Action,
        
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$OperationName,
        
        [Parameter()]
        [ValidateRange(1, 10)]
        [int]$MaxAttempts = 3,
        
        [Parameter()]
        [ValidateRange(1, 30)]
        [int]$DelaySeconds = 2
    )

    $attempt = 1
    $success = $false
    $lastError = $null

    do {
        try {
            & $Action
            $success = $true
            break
        } catch {
            $lastError = $_
            Write-Verbose "$OperationName - Attempt $attempt of $MaxAttempts failed: $_"
            if ($attempt -lt $MaxAttempts) {
                Write-Verbose "Waiting $DelaySeconds seconds before retry..."
                $job = Start-Job -ScriptBlock { Start-Sleep -Seconds $using:DelaySeconds }
                $job | Wait-Job | Remove-Job
            }
            $attempt++ 
        }
    } while ($attempt -le $MaxAttempts)

    if (-not $success) {
        throw "Failed $OperationName after $MaxAttempts attempts: $lastError"
    }
    return $success
}

function Get-FileDate {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [System.__ComObject]$Shell,
        
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [System.IO.FileInfo]$Item
    )
    $folder = $shell.Namespace($item.DirectoryName)
    $file = $folder.ParseName($item.Name)
    $dateTakenIndex = Get-DateTakenPropertyIndex $folder
    
    if ($dateTakenIndex -lt 0) {
        return @{
            Date   = $item.LastWriteTime
            Source = "LastWriteTime"
        }
    }

    $dateTaken = $folder.GetDetailsOf($file, $dateTakenIndex)
    if ([string]::IsNullOrEmpty($dateTaken) -or $dateTaken -match '^\s*$') {
        return @{
            Date   = $item.LastWriteTime
            Source = "LastWriteTime"
        }
    }

    $dateTaken = $dateTaken -replace '[^\x20-\x7E]', ''
    try {
        return @{
            Date   = Get-Date $dateTaken
            Source = "DateTaken"
        }
    } catch {
        Write-Verbose "Could not parse date taken for $($item.Name): $dateTaken"
        return @{
            Date   = $item.LastWriteTime
            Source = "LastWriteTime"
        }
    }
}

function Write-ProcessLog {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Message,
        
        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string]$LogFile = $Script:CurrentLogFile
    )
    
    if (-not $WhatIfPreference) {
        $logMessage = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss'): $Message"
        Add-Content -Path $LogFile -Value $logMessage
    }
    Write-Verbose $Message
}

function Get-UniqueFilePath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$BasePath,
        
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$FileName
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

function Move-PictureToDateFolder {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [System.IO.FileInfo]$Item,
        
        [Parameter(Mandatory)]
        [ValidateScript({
                if (!(Test-Path $_)) {
                    throw "Directory does not exist: $_"
                }
                return $true
            })]
        [string]$DestinationDirectory,
        
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [System.__ComObject]$Shell
    )

    $dateInfo = Get-FileDate -shell $Shell -item $Item
    $yearPath = Join-Path $DestinationDirectory $dateInfo.Date.Year.ToString()
    $monthPath = Join-Path $yearPath $dateInfo.Date.Month.ToString("00")
    $targetPath = Join-Path $monthPath $Item.Name

    # Create target directories
    $null = New-Item -ItemType Directory -Path $monthPath -Force -ErrorAction Stop

    # Handle name conflicts
    $targetPath = Get-UniqueFilePath -basePath $monthPath -fileName $Item.Name

    if (-not $PSCmdlet.ShouldProcess($Item.Name, "Move to $targetPath")) {
        $script:skipCount++
        return
    }

    Copy-Item -Path $Item.FullName -Destination $targetPath -ErrorAction Stop
    Remove-Item -Path $Item.FullName -ErrorAction Stop
    Write-ProcessLog "Processed $($Item.Name) to $targetPath"
    $script:processedCount++
}

function Sort_Pictures_By_Date_Taken {
    <#
    .SYNOPSIS
        Sorts pictures into folders by date taken.
    .DESCRIPTION
        Organizes pictures from a source directory into a year/month folder structure based on their DateTaken metadata.
        If DateTaken metadata is not available, falls back to LastWriteTime.
        Creates a folder structure like: DestinationDirectory/YYYY/MM/
    .PARAMETER SourceDirectory
        The directory containing the pictures to sort.
    .PARAMETER DestinationDirectory
        The directory where the sorted folder structure will be created.
    .PARAMETER FileExtensions 
        The file extensions to consider for sorting. Default is .jpg, .jpeg, .png, .gif, .bmp, .tiff.
    .PARAMETER LogFile
        The path to the log file to write processing information. Default is sort_pictures.log in the script directory.
    .PARAMETER ConfirmAll
        Skip individual confirmations and proceed with all files.
    .PARAMETER StopOnError
        Stops processing when an error occurs. By default, the script will continue processing other files.
    .PARAMETER WhatIf
        Shows what would happen if the cmdlet runs.
        The cmdlet is not run.
    .PARAMETER Confirm
        Prompts you for confirmation before running the cmdlet.
    .PARAMETER Verbose
        Shows detailed processing information during execution.
    .EXAMPLE
        Sort_Pictures_By_Date_Taken -SourceDirectory "C:\Pictures" -DestinationDirectory "C:\SortedPictures"
        
        Sorts pictures from C:\Pictures into a year/month folder structure in C:\SortedPictures.
    .EXAMPLE
        Sort_Pictures_By_Date_Taken -SourceDirectory ".\Photos" -DestinationDirectory ".\Sorted" -ConfirmAll -Verbose
        
        Sorts pictures with verbose output and no confirmations.
    .EXAMPLE
        Sort_Pictures_By_Date_Taken -SourceDirectory ".\Photos" -DestinationDirectory ".\Sorted" -WhatIf
        
        Shows what changes would be made without actually moving files.
    .NOTES
        The script attempts to use image metadata (DateTaken) first, then falls back to file LastWriteTime if metadata is not available.
    #>
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
        [ValidateNotNullOrEmpty()]
        [string[]]$FileExtensions = @('.jpg', '.jpeg', '.png', '.gif', '.bmp', '.tiff'),

        [Parameter()]
        [ValidateScript({
                if ($_ -notmatch '\.log$') {
                    throw "Log file must have .log extension"
                }
                return $true
            })]
        [string]$LogFile = "$PSScriptRoot\sort_pictures.log",

        [Parameter(ParameterSetName = 'NoConfirm')]
        [switch]$ConfirmAll,

        [Parameter()]
        [switch]$StopOnError
    )

    begin {
        # Clear any existing script-scope variables
        Remove-Variable -Name DateTakenIndex -Scope Script -ErrorAction SilentlyContinue
        $Script:CurrentLogFile = $LogFile
        # Initialize
        $ErrorActionPreference = 'Stop'
        $InformationPreference = 'Continue'
        $errors = @()
        $processedCount = $skipCount = $errorCount = 0

        # Initialize log file if needed
        if (-not $WhatIfPreference -and -not (Test-Path -Path $LogFile)) {
            $null = New-Item -ItemType File -Path $LogFile -Force
            Write-Verbose "Created log file at: $LogFile"
            Write-ProcessLog "Script started"
        }

        # Get shell COM object
        $shell = try {
            New-Object -ComObject Shell.Application
        } catch {
            Write-Error "Failed to initialize Shell.Application: $_"
            return
        }
    }

    process {
        try {
            # Get matching files
            $items = @(Get-ChildItem -Path $SourceDirectory -File -Recurse | 
                Where-Object { $FileExtensions -contains $_.Extension.ToLower() })

            if ($items.Count -eq 0) {
                Write-Information "No matching files found."
                return
            }

            Write-ProcessLog "Found $($items.Count) matching files to process"

            # Confirm batch processing
            if (-not $ConfirmAll -and -not $PSCmdlet.ShouldProcess("$($items.Count) files", "Process all")) {
                Write-Verbose "Operation cancelled by user"
                return
            }

            # Process each file
            foreach ($item in $items) {
                try {
                    Write-Progress -Activity "Sorting Pictures" -Status "Processing $($item.Name)" `
                        -PercentComplete (($processedCount + $skipCount + $errorCount) * 100 / $items.Count)

                    Move-PictureToDateFolder -Item $item -DestinationDirectory $DestinationDirectory -Shell $shell
                } catch {
                    $errorMsg = "Error processing $($item.FullName): $_"
                    $errors += $errorMsg
                    $errorCount++
                    Write-Error $errorMsg
                    if ($StopOnError) {
                        break 
                    }
                }
            }

            # Final summary
            Write-Information @"
Processing Summary:
Files processed: $processedCount
Files skipped: $skipCount
Errors encountered: $errorCount
"@

            if ($errors) {
                Write-Warning "The following errors occurred:"
                $errors | ForEach-Object { Write-Warning $_ }
                return 1
            }
            return 0
        } finally {
            if ($shell) {
                [System.Runtime.Interopservices.Marshal]::ReleaseComObject($shell)
                [System.GC]::Collect()
                [System.GC]::WaitForPendingFinalizers()
            }
            Write-Progress -Activity "Sorting Pictures" -Completed
        }
    }

    end {
        # Cleanup script-scope variables
        Remove-Variable -Name CurrentLogFile, DateTakenIndex -Scope Script -ErrorAction SilentlyContinue
    }
}

# Only export the main function
Export-ModuleMember -Function Sort_Pictures_By_Date_Taken