<#
.SYNOPSIS
    Lists Edge workspaces in a table.
#>

# Define the path to the JSON file
$jsonFilePath = "$($env:UserProfile)\AppData\Local\Microsoft\Edge\User Data\Default\Workspaces\WorkspacesCache"

# Read and parse the JSON file
$jsonContent = Get-Content -Path $jsonFilePath -Raw 
| ConvertFrom-Json

# Check if the JSON content is empty or null
if (-not $jsonContent -or -not $jsonContent.workspaces) {
    Write-Host "No workspaces found or the JSON file is empty."
    exit
}

# create a table 
$workspaceTable = @()
foreach ($workspace in $jsonContent.workspaces) {
    $workspaceTable += [PSCustomObject]@{
        Name = $workspace.name
        ID   = $workspace.id
    }
}

# Display the table
$workspaceTable 
| Format-Table -AutoSize

# export an alias for the script
Export-Alias Show-Edge-Workspaces

# Ignore the rest of the file as it is not needed for the task at hand
# # Import the assembly for Windows Forms
# Add-Type -AssemblyName System.Windows.Forms

# # Create a new form
# $form = New-Object System.Windows.Forms.Form
# $form.Text = 'Select a Workspace'
# $form.StartPosition = 'CenterScreen'
# $form.AutoSize = $true
# $form.FormBorderStyle = 'FixedDialog'
# $form.MinimizeBox = $false
# $form.MaximizeBox = $false
# $form.Height = 120

# # Create a ComboBox for workspace selection
# $comboBox = New-Object System.Windows.Forms.ComboBox
# $comboBox.DropDownStyle = 'DropDownList'
# $comboBox.Width = 250
# $comboBox.Location = New-Object System.Drawing.Point(10, 10)

# Collate workspace names and IDs into the ComboBox


# # Add the ComboBox to the form
# $form.Controls.Add($comboBox)

# # Create an OK button
# $okButton = New-Object System.Windows.Forms.Button
# $okButton.Text = 'Open Workspace'
# $okButton.DialogResult = [System.Windows.Forms.DialogResult]::OK
# $okButton.Location = New-Object System.Drawing.Point(10, 45)
# $okButton.AutoSize = $true

# # Add the OK button to the form
# $form.Controls.Add($okButton)

# # Create a Cancel button
# $cancelButton = New-Object System.Windows.Forms.Button
# $cancelButton.Text = 'Cancel'
# $cancelButton.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
# $cancelButton.Location = New-Object System.Drawing.Point(120, 45)
# $cancelButton.AutoSize = $true

# Add the Cancel button to the form
# $form.Controls.Add($cancelButton)

# Show the form and wait for the user to click OK or Cancel
# $result = $form.ShowDialog()

# # Extract the selected workspace name and ID
# $selectedWorkspaceFullText = $comboBox.SelectedItem
# $selectedWorkspaceName = $selectedWorkspaceFullText -replace ' \[\S+\]', ''
# $selectedWorkspaceID = [regex]::Match($selectedWorkspaceFullText, '\[(\S+)\]').groups[1].value

# # Shell output of selection
# Write-Output "Selected Workspace Name: $selectedWorkspaceName"
# Write-Output "Selected Workspace ID: $selectedWorkspaceID"

# # Launch Microsoft Edge with the selected workspace
# Write-Host "Launching Microsoft Edge for workspace: $selectedWorkspaceName"
# Start-Process -FilePath "msedge.exe" -ArgumentList "--launch-workspace=$selectedWorkspaceID --no-startup-window"
# Write-Host "Workspace has been launched."
