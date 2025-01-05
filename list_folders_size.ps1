$fso = new-object -com Scripting.FileSystemObject
Get-ChildItem -Directory `
| Select-Object @{l = 'Size'; e = { $fso.GetFolder($_.FullName).Size } }, FullName `
| Sort-Object Size -Descending `
| Format-Table @{l = 'Size [MB]'; e = { '{0:N2}    ' -f ($_.Size / 1MB) } }, FullName