#Requires -Version 7.0
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }
<#
    Pester tests for the PictureSorting module (Move-PicturesByDate and its private helpers).

    Covers: LastWriteTime sorting, EXIF date-taken sorting, dry-run, extension filtering,
    filename-collision handling, resume/skip, MinDate/MaxDate range fallback, oversized-file
    rejection, invalid-image rejection, batch sizing, and the private helpers Get-UniqueFilePath,
    Confirm-ImageFile and Get-FileDate.

    Run:  Invoke-Pester -Path .\Tests\PictureSorting.Tests.ps1
#>

BeforeAll {
    $script:ModuleManifest = Join-Path (Split-Path $PSScriptRoot -Parent) 'Modules\PictureSorting\PictureSorting.psd1'
    Import-Module $script:ModuleManifest -Force

    Add-Type -AssemblyName System.Drawing

    # Creates a real JPEG. With -DateTaken, embeds an EXIF DateTimeOriginal so Windows/Shell
    # reports a "Date taken". PropertyItem has no public constructor, so use the non-public one.
    function New-TestImage {
        [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Test helper, not a public cmdlet.')]
        param(
            [Parameter(Mandatory)][string]$Path,
            [datetime]$DateTaken,
            [datetime]$LastWrite
        )
        $bmp = [System.Drawing.Bitmap]::new(16, 16)
        try {
            if ($PSBoundParameters.ContainsKey('DateTaken')) {
                $ctor = [System.Drawing.Imaging.PropertyItem].GetConstructor(
                    [System.Reflection.BindingFlags]'NonPublic,Instance', $null, @(), $null)
                $exif = $DateTaken.ToString('yyyy:MM:dd HH:mm:ss') + "`0"
                $bytes = [System.Text.Encoding]::ASCII.GetBytes($exif)
                foreach ($id in 0x9003, 0x0132) {
                    $pi = $ctor.Invoke(@())
                    $pi.Id = $id; $pi.Type = 2; $pi.Value = $bytes; $pi.Len = $bytes.Length
                    $bmp.SetPropertyItem($pi)
                }
            }
            $bmp.Save($Path, [System.Drawing.Imaging.ImageFormat]::Jpeg)
        }
        finally {
            $bmp.Dispose()
        }
        if ($PSBoundParameters.ContainsKey('LastWrite')) {
            (Get-Item -LiteralPath $Path).LastWriteTime = $LastWrite
        }
    }

    # Writes a minimal but signature-valid .mp4 (24-byte box with an 'ftyp' at offset 4).
    function New-TestVideo {
        [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Test helper, not a public cmdlet.')]
        param(
            [Parameter(Mandatory)][string]$Path,
            [datetime]$LastWrite
        )
        $bytes = [byte[]]@(0, 0, 0, 0x18) + [System.Text.Encoding]::ASCII.GetBytes('ftypisom') + [byte[]]::new(12)
        [System.IO.File]::WriteAllBytes($Path, $bytes)
        if ($PSBoundParameters.ContainsKey('LastWrite')) {
            (Get-Item -LiteralPath $Path).LastWriteTime = $LastWrite
        }
    }

    # Runs Move-PicturesByDate non-interactively, swallowing the Information/warning/error streams
    # (some tests deliberately feed it bad files and assert on the counted errors afterwards).
    function Invoke-Sort {
        param([hashtable]$Params)
        Move-PicturesByDate @Params -ConfirmAll -Confirm:$false 6>$null 3>$null 2>$null | Out-Null
    }
}

AfterAll {
    Remove-Module PictureSorting -Force -ErrorAction SilentlyContinue
}

Describe 'Move-PicturesByDate (integration)' {
    BeforeEach {
        $script:src = Join-Path $TestDrive 'source'
        $script:dest = Join-Path $TestDrive 'organized'
        $script:log = Join-Path $TestDrive 'run.log'
        New-Item -ItemType Directory -Path $script:src, $script:dest -Force | Out-Null
    }
    AfterEach {
        Remove-Item -LiteralPath $script:src, $script:dest -Recurse -Force -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath $script:log -Force -ErrorAction SilentlyContinue
    }

    It 'sorts a no-EXIF image into a YYYY/MM folder by LastWriteTime' {
        New-TestImage -Path (Join-Path $src 'a.jpg') -LastWrite ([datetime]'2021-03-14 09:00')
        Invoke-Sort @{ SourceDirectory = $src; DestinationDirectory = $dest; LogFile = $log }

        Join-Path $dest '2021\03\a.jpg' | Should -Exist
        @(Get-ChildItem $src -File).Count | Should -Be 0
    }

    It 'sorts an EXIF image by its date taken, not its LastWriteTime' {
        # EXIF says 2015-06; file timestamp says 2022-01. It must land under 2015/06.
        New-TestImage -Path (Join-Path $src 'e.jpg') -DateTaken ([datetime]'2015-06-15 10:30') -LastWrite ([datetime]'2022-01-01')
        Invoke-Sort @{ SourceDirectory = $src; DestinationDirectory = $dest; LogFile = $log }

        Join-Path $dest '2015\06\e.jpg' | Should -Exist
        Join-Path $dest '2022\01\e.jpg' | Should -Not -Exist
        InModuleScope PictureSorting { $script:metrics.DateTakenUsed } | Should -Be 1
    }

    It 'moves nothing in dry-run mode' {
        New-TestImage -Path (Join-Path $src 'a.jpg') -LastWrite ([datetime]'2021-03-14')
        Move-PicturesByDate -SourceDirectory $src -DestinationDirectory $dest -LogFile $log -DryRun -ConfirmAll 6>$null 3>$null | Out-Null

        @(Get-ChildItem $src -File).Count | Should -Be 1
        @(Get-ChildItem $dest -Recurse -File).Count | Should -Be 0
    }

    It 'processes only the configured file extensions' {
        New-TestImage -Path (Join-Path $src 'keep.jpg') -LastWrite ([datetime]'2020-05-01')
        Set-Content -LiteralPath (Join-Path $src 'ignore.txt') -Value 'not an image'
        Invoke-Sort @{ SourceDirectory = $src; DestinationDirectory = $dest; LogFile = $log }

        Join-Path $dest '2020\05\keep.jpg' | Should -Exist
        Join-Path $src 'ignore.txt' | Should -Exist   # untouched
    }

    It 'renames on a filename collision instead of overwriting' {
        New-Item -ItemType Directory -Path (Join-Path $src 'one'), (Join-Path $src 'two') -Force | Out-Null
        New-TestImage -Path (Join-Path $src 'one\pic.jpg') -LastWrite ([datetime]'2019-07-04')
        New-TestImage -Path (Join-Path $src 'two\pic.jpg') -LastWrite ([datetime]'2019-07-20')
        Invoke-Sort @{ SourceDirectory = $src; DestinationDirectory = $dest; LogFile = $log }

        $monthDir = Join-Path $dest '2019\07'
        @(Get-ChildItem $monthDir -File).Count | Should -Be 2
        Join-Path $monthDir 'pic.jpg'   | Should -Exist
        Join-Path $monthDir 'pic_1.jpg' | Should -Exist
    }

    It 'skips files already recorded in the resume file' {
        $img = Join-Path $src 'r.jpg'
        New-TestImage -Path $img -LastWrite ([datetime]'2021-01-01')
        $resume = Join-Path $TestDrive 'resume.json'
        @{ $img = (Get-Date).ToString('o') } | ConvertTo-Json | Set-Content -LiteralPath $resume

        Invoke-Sort @{ SourceDirectory = $src; DestinationDirectory = $dest; LogFile = $log; ResumeFile = $resume }

        Join-Path $src 'r.jpg' | Should -Exist            # not moved - it was skipped
        @(Get-ChildItem $dest -Recurse -File).Count | Should -Be 0
    }

    It 'falls back to LastWriteTime when the EXIF date is outside MinDate/MaxDate' {
        # EXIF 2015 but MinDate 2020 -> out of range -> use LastWriteTime (2021-08).
        New-TestImage -Path (Join-Path $src 'o.jpg') -DateTaken ([datetime]'2015-06-15') -LastWrite ([datetime]'2021-08-09')
        Invoke-Sort @{ SourceDirectory = $src; DestinationDirectory = $dest; LogFile = $log; MinDate = [datetime]'2020-01-01' }

        Join-Path $dest '2021\08\o.jpg' | Should -Exist
        InModuleScope PictureSorting { $script:metrics.InvalidDates } | Should -Be 1
    }

    It 'rejects a non-image file that has an image extension' {
        Set-Content -LiteralPath (Join-Path $src 'fake.jpg') -Value 'this is text, not a JPEG'
        Invoke-Sort @{ SourceDirectory = $src; DestinationDirectory = $dest; LogFile = $log }

        Join-Path $src 'fake.jpg' | Should -Exist         # not moved
        @(Get-ChildItem $dest -Recurse -File).Count | Should -Be 0
        InModuleScope PictureSorting { $script:errorCount } | Should -BeGreaterThan 0
    }

    It 'rejects a file that exceeds MaxFileSize' {
        New-TestImage -Path (Join-Path $src 'big.jpg') -LastWrite ([datetime]'2021-01-01')
        Invoke-Sort @{ SourceDirectory = $src; DestinationDirectory = $dest; LogFile = $log; MaxFileSize = 10 }

        Join-Path $src 'big.jpg' | Should -Exist          # over the 10-byte limit, not moved
        @(Get-ChildItem $dest -Recurse -File).Count | Should -Be 0
    }

    It 'processes every file even when BatchSize is 1' {
        1..3 | ForEach-Object {
            New-TestImage -Path (Join-Path $src "b$_.jpg") -LastWrite ([datetime]"2020-0$_-15")
        }
        Invoke-Sort @{ SourceDirectory = $src; DestinationDirectory = $dest; LogFile = $log; BatchSize = 1 }

        @(Get-ChildItem $dest -Recurse -File).Count | Should -Be 3
        @(Get-ChildItem $src -File).Count | Should -Be 0
    }

    It 'throws when the destination directory does not exist' {
        New-TestImage -Path (Join-Path $src 'a.jpg') -LastWrite ([datetime]'2021-01-01')
        { Move-PicturesByDate -SourceDirectory $src -DestinationDirectory (Join-Path $TestDrive 'nope') -LogFile $log -ConfirmAll 6>$null }
        | Should -Throw
    }

    It 'skips files already under the destination when the destination is nested in the source' {
        $nestedDest = Join-Path $src 'organized'
        New-Item -ItemType Directory -Path (Join-Path $nestedDest '2020\05') -Force | Out-Null
        New-TestImage -Path (Join-Path $nestedDest '2020\05\already.jpg') -LastWrite ([datetime]'2020-05-01')
        New-TestImage -Path (Join-Path $src 'loose.jpg') -LastWrite ([datetime]'2021-03-14')

        Invoke-Sort @{ SourceDirectory = $src; DestinationDirectory = $nestedDest; LogFile = $log }

        Join-Path $nestedDest '2021\03\loose.jpg' | Should -Exist          # loose file sorted
        Join-Path $nestedDest '2020\05\already.jpg' | Should -Exist        # already-sorted file untouched (not renamed)
        @(Get-ChildItem (Join-Path $nestedDest '2020\05') -File).Count | Should -Be 1
    }

    It 'handles and de-collides filenames containing square brackets' {
        New-Item -ItemType Directory -Path (Join-Path $src 'one'), (Join-Path $src 'two') -Force | Out-Null
        New-TestImage -Path (Join-Path $src 'one\photo[1].jpg') -LastWrite ([datetime]'2022-06-15')
        New-TestImage -Path (Join-Path $src 'two\photo[1].jpg') -LastWrite ([datetime]'2022-06-20')

        Invoke-Sort @{ SourceDirectory = $src; DestinationDirectory = $dest; LogFile = $log }

        $monthDir = Join-Path $dest '2022\06'
        Test-Path -LiteralPath (Join-Path $monthDir 'photo[1].jpg')   | Should -BeTrue
        Test-Path -LiteralPath (Join-Path $monthDir 'photo[1]_1.jpg') | Should -BeTrue
    }

    It 'pauses and resumes OneDrive around the move when -PauseOneDriveSync is set' {
        # Mock the module's own pause/resume so the real OneDrive is never touched.
        Mock -ModuleName PictureSorting Suspend-OneDriveSync { 'C:\fake\OneDrive.exe' }
        Mock -ModuleName PictureSorting Resume-OneDriveSync { }
        New-TestImage -Path (Join-Path $src 'a.jpg') -LastWrite ([datetime]'2021-03-14')

        Invoke-Sort @{ SourceDirectory = $src; DestinationDirectory = $dest; LogFile = $log; PauseOneDriveSync = $true }

        Should -Invoke -ModuleName PictureSorting Suspend-OneDriveSync -Times 1
        Should -Invoke -ModuleName PictureSorting Resume-OneDriveSync -Times 1
        Join-Path $dest '2021\03\a.jpg' | Should -Exist   # the move still happened
    }

    It 'does not pause OneDrive for a dry run even if -PauseOneDriveSync is set' {
        Mock -ModuleName PictureSorting Suspend-OneDriveSync { 'C:\fake\OneDrive.exe' }
        New-TestImage -Path (Join-Path $src 'a.jpg') -LastWrite ([datetime]'2021-03-14')

        Move-PicturesByDate -SourceDirectory $src -DestinationDirectory $dest -LogFile $log -DryRun -ConfirmAll -PauseOneDriveSync 6>$null 3>$null | Out-Null

        Should -Invoke -ModuleName PictureSorting Suspend-OneDriveSync -Times 0
    }

    It 'sorts a video by LastWriteTime into a YYYY/MM folder' {
        New-TestVideo -Path (Join-Path $src 'clip.mp4') -LastWrite ([datetime]'2023-05-20')
        Invoke-Sort @{ SourceDirectory = $src; DestinationDirectory = $dest; LogFile = $log }
        Join-Path $dest '2023\05\clip.mp4' | Should -Exist
    }

    It 'sorts images and videos together in one run' {
        New-TestImage -Path (Join-Path $src 'p.jpg') -LastWrite ([datetime]'2022-04-10')
        New-TestVideo -Path (Join-Path $src 'v.mp4') -LastWrite ([datetime]'2022-04-15')
        Invoke-Sort @{ SourceDirectory = $src; DestinationDirectory = $dest; LogFile = $log }
        Join-Path $dest '2022\04\p.jpg' | Should -Exist
        Join-Path $dest '2022\04\v.mp4' | Should -Exist
    }

    It 'rejects a .mp4 that is not a real video' {
        Set-Content -LiteralPath (Join-Path $src 'fake.mp4') -Value 'this is not a video at all'
        Invoke-Sort @{ SourceDirectory = $src; DestinationDirectory = $dest; LogFile = $log }
        Join-Path $src 'fake.mp4' | Should -Exist                       # not moved
        @(Get-ChildItem $dest -Recurse -File).Count | Should -Be 0
    }
}

Describe 'Private helpers' {
    It 'Get-UniqueFilePath returns the base path when there is no collision' {
        InModuleScope PictureSorting -Parameters @{ Dir = $TestDrive } {
            param($Dir)
            Get-UniqueFilePath -BasePath $Dir -FileName 'new.jpg' | Should -Be (Join-Path $Dir 'new.jpg')
        }
    }

    It 'Get-UniqueFilePath appends an incrementing counter on collisions' {
        $dir = Join-Path $TestDrive 'uniq'
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $dir 'x.jpg') -Value '1'
        InModuleScope PictureSorting -Parameters @{ Dir = $dir } {
            param($Dir)
            Get-UniqueFilePath -BasePath $Dir -FileName 'x.jpg' | Should -Be (Join-Path $Dir 'x_1.jpg')
        }
    }

    It 'Confirm-VideoFile accepts a valid signature and rejects a text file or empty file' {
        $good = Join-Path $TestDrive 'good.mp4'
        New-TestVideo -Path $good
        $bad = Join-Path $TestDrive 'bad.mp4'
        Set-Content -LiteralPath $bad -Value 'not a video at all, just text'
        $empty = Join-Path $TestDrive 'empty.mp4'
        [System.IO.File]::WriteAllBytes($empty, [byte[]]::new(0))
        InModuleScope PictureSorting -Parameters @{ G = $good; B = $bad; E = $empty } {
            param($G, $B, $E)
            Confirm-VideoFile -Path $G | Should -BeTrue
            Confirm-VideoFile -Path $B | Should -BeFalse
            Confirm-VideoFile -Path $E | Should -BeFalse
        }
    }

    It 'Confirm-ImageFile is true for a real image and false for text' {
        $img = Join-Path $TestDrive 'real.jpg'
        New-TestImage -Path $img -LastWrite ([datetime]'2020-01-01')
        $txt = Join-Path $TestDrive 'real.txt'
        Set-Content -LiteralPath $txt -Value 'nope'
        InModuleScope PictureSorting -Parameters @{ Img = $img; Txt = $txt } {
            param($Img, $Txt)
            Confirm-ImageFile -Path $Img | Should -BeTrue
            Confirm-ImageFile -Path $Txt | Should -BeFalse
        }
    }

    It 'Get-FileDate reports the DateTaken source for an EXIF image' {
        $img = Join-Path $TestDrive 'dt.jpg'
        New-TestImage -Path $img -DateTaken ([datetime]'2016-09-09 12:00') -LastWrite ([datetime]'2023-01-01')
        InModuleScope PictureSorting -Parameters @{ Img = $img } {
            param($Img)
            $script:DateTakenIndex = $null   # clear any cached index from prior tests
            $shell = New-Object -ComObject Shell.Application
            try {
                $info = Get-FileDate -Shell $shell -Item (Get-Item -LiteralPath $Img)
                $info.Source | Should -Be 'DateTaken'
                $info.Date.Year | Should -Be 2016
            }
            finally {
                [void][System.Runtime.Interopservices.Marshal]::ReleaseComObject($shell)
            }
        }
    }

    It 'Get-FileLock reports a missing file as not locked' {
        InModuleScope PictureSorting -Parameters @{ P = (Join-Path $TestDrive 'gone.jpg') } {
            param($P)
            Get-FileLock -Path $P | Should -BeFalse
        }
    }

    It 'Suspend-OneDriveSync returns null and stops nothing when OneDrive is not running' {
        InModuleScope PictureSorting {
            Mock Get-Process { $null }
            Mock Stop-Process { }
            Suspend-OneDriveSync | Should -BeNullOrEmpty
            Should -Invoke Stop-Process -Times 0
        }
    }

    It 'Suspend-OneDriveSync stops OneDrive and returns its path when running' {
        InModuleScope PictureSorting {
            # Id is needed so the "| Stop-Process" pipeline binds (Stop-Process -Id by property name).
            Mock Get-Process { [pscustomobject]@{ Path = 'C:\fake\OneDrive.exe'; Id = 4242 } }
            Mock Stop-Process { }
            Mock Start-Sleep { }
            Suspend-OneDriveSync | Should -Be 'C:\fake\OneDrive.exe'
            Should -Invoke Stop-Process -Times 1
        }
    }

    It 'Resume-OneDriveSync does nothing when given no path' {
        InModuleScope PictureSorting {
            Mock Start-Process { }
            Resume-OneDriveSync -Path ''
            Should -Invoke Start-Process -Times 0
        }
    }

    It 'Resume-OneDriveSync restarts OneDrive from the given path' {
        InModuleScope PictureSorting {
            Mock Get-Process { $null }
            Mock Test-Path { $true }
            Mock Start-Process { }
            Resume-OneDriveSync -Path 'C:\fake\OneDrive.exe'
            Should -Invoke Start-Process -Times 1
        }
    }

    It 'Get-FileDate falls back to LastWriteTime for a no-EXIF image' {
        $img = Join-Path $TestDrive 'nodt.jpg'
        New-TestImage -Path $img -LastWrite ([datetime]'2018-04-01')
        InModuleScope PictureSorting -Parameters @{ Img = $img } {
            param($Img)
            $shell = New-Object -ComObject Shell.Application
            try {
                $info = Get-FileDate -Shell $shell -Item (Get-Item -LiteralPath $Img)
                $info.Source | Should -Be 'LastWriteTime'
            }
            finally {
                [void][System.Runtime.Interopservices.Marshal]::ReleaseComObject($shell)
            }
        }
    }
}
