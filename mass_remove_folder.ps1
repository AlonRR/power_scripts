$folderName = "node_modules"  # Replace with the name of the folder you're searching for
$rootPath = "C:\Users\alonr\OneDrive\Shenkar\Archive\שנה ג סמסטר א\Methods_in_software_engenering"  # Replace with the path where you want to start the search

# Find the folders
Get-ChildItem -Path $rootPath -Recurse -Directory | Where-Object {$_.Name -eq $folderName} | ForEach-Object {
    Remove-Item -Path $_.FullName -Recurse -Force -Verbose
}
