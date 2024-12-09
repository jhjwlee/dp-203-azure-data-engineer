Clear-Host
Write-Host "Starting script at $(Get-Date)"

# Prompt for existing resource group name
$resourceGroupName = Read-Host "Enter the existing resource group name"

# Prompt for a unique random suffix
$suffix = Read-Host "Enter a unique random suffix for Azure resources"

# Upload files
write-host "Uploading files..."
$dataLakeAccountName = "datalake$suffix"
$storageAccount = Get-AzStorageAccount -ResourceGroupName $resourceGroupName -Name $dataLakeAccountName
$storageContext = $storageAccount.Context
Get-ChildItem "./data/*.csv" -File | Foreach-Object {
    write-host ""
    $file = $_.Name
    Write-Host $file
    $blobPath = "data/$file"
    Set-AzStorageBlobContent -File $_.FullName -Container "files" -Blob $blobPath -Context $storageContext
}

write-host "Script completed at $(Get-Date)"
