Clear-Host
Write-Host "Starting script at $(Get-Date)"

# Azure 구독 선택
$subs = Get-AzSubscription | Select-Object
if ($subs -eq $null -or $subs.Count -eq 0) {
    Write-Error "No Azure subscriptions found. Please check your Azure account and try again."
    Exit
}

if ($subs.Count -gt 1) {
    Write-Host "You have multiple Azure subscriptions - please select the one you want to use:"
    for ($i = 0; $i -lt $subs.length; $i++) {
        Write-Host "[$($i)]: $($subs[$i].Name) (ID = $($subs[$i].Id))"
    }
    $selectedIndex = -1
    while ($selectedIndex -eq -1) {
        $enteredValue = Read-Host "Enter a subscription number"
        if ($enteredValue -match "^\d+$" -and [int]$enteredValue -lt $subs.Length) {
            $selectedIndex = [int]$enteredValue
        } else {
            Write-Host "Invalid selection. Please try again."
        }
    }
    $selectedSub = $subs[$selectedIndex].Id
    Select-AzSubscription -SubscriptionId $selectedSub
} else {
    Write-Host "Only one subscription found. Using subscription $($subs[0].Name)"
    Select-AzSubscription -SubscriptionId $subs[0].Id
}

# 리소스 그룹 및 접미사 입력 받기
$resourceGroupName = Read-Host "Enter the existing Azure resource group name"
$suffix = Read-Host "Enter the unique suffix for your Azure resources"

# 랜덤 지역 설정
Write-Host "Selecting a random Azure region..."
$preferredRegions = "australiaeast", "centralus", "southcentralus", "eastus2", "northeurope", "southeastasia", "uksouth", "westeurope", "westus", "westus2"

# Azure 지역 목록 필터링
$locations = Get-AzLocation | Where-Object { $_.Location -in $preferredRegions }
if ($locations.Count -eq 0) {
    Write-Error "No available Azure regions found. Please check your subscription and try again."
    Exit
}

# 무작위 지역 선택
$randomIndex = Get-Random -Minimum 0 -Maximum $locations.Count
$Region = $locations[$randomIndex].Location
Write-Host "Selected random region: $Region"

# 스토리지 계정 이름 및 컨텍스트 설정
$dataLakeAccountName = "datalake$suffix"

# 스토리지 계정 확인
try {
    $storageAccount = Get-AzStorageAccount -ResourceGroupName $resourceGroupName -Name $dataLakeAccountName -ErrorAction Stop
    $storageContext = $storageAccount.Context
    Write-Host "Storage account found: $dataLakeAccountName in $resourceGroupName"
} catch {
    Write-Error "Storage account $dataLakeAccountName not found in resource group $resourceGroupName. Please check the values and try again."
    Exit
}

# 파일 업로드
Write-Host "Uploading files to Azure Storage..."

# CSV 파일 업로드
Get-ChildItem "./data/*.csv" -File | ForEach-Object {
    $file = $_.Name
    $blobPath = "sales/csv/$file"
    Write-Host "Uploading $file to $blobPath ..."
    Set-AzStorageBlobContent -File $_.FullName -Container "files" -Blob $blobPath -Context $storageContext
}

# Parquet 파일 업로드
Get-ChildItem "./data/*.parquet" -File | ForEach-Object {
    $file = $_.Name
    $folder = $_.Name.Replace(".snappy.parquet", "")
    $newFileName = "orders$($folder).snappy.parquet"
    $blobPath = "sales/parquet/year=$folder/$newFileName"
    Write-Host "Uploading $file to $blobPath ..."
    Set-AzStorageBlobContent -File $_.FullName -Container "files" -Blob $blobPath -Context $storageContext
}

# JSON 파일 업로드
Get-ChildItem "./data/*.json" -File | ForEach-Object {
    $file = $_.Name
    $blobPath = "sales/json/$file"
    Write-Host "Uploading $file to $blobPath ..."
    Set-AzStorageBlobContent -File $_.FullName -Container "files" -Blob $blobPath -Context $storageContext
}

Write-Host "Script completed at $(Get-Date)"
