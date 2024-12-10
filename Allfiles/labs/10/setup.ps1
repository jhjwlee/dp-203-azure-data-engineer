Clear-Host
Write-Host "Starting script at $(Get-Date)"

# Azure Synapse 모듈 설치
Set-PSRepository -Name PSGallery -InstallationPolicy Trusted
Install-Module -Name Az.Synapse -Force

# 사용자 입력 받기
$resourceGroupName = Read-Host "Enter the existing resource group name"
$suffix = Read-Host "Enter a unique suffix for Azure resources"

# Azure 구독 선택
$subs = Get-AzSubscription | Select-Object
if ($subs.Count -gt 1) {
    Write-Host "You have multiple Azure subscriptions - please select one:"
    for ($i = 0; $i -lt $subs.Count; $i++) {
        Write-Host "[$i]: $($subs[$i].Name) (ID: $($subs[$i].Id))"
    }
    $selectedIndex = Read-Host "Enter the number of the subscription you want to use"
    $selectedSub = $subs[$selectedIndex].Id
    Select-AzSubscription -SubscriptionId $selectedSub
}

# 비밀번호 입력 및 검증
$sqlUser = "SQLUser"
$sqlPassword = ""
$complexPassword = 0

while ($complexPassword -ne 1) {
    $SqlPassword = Read-Host "Enter a password for the $sqlUser login (complexity requirements: 8+ characters, at least one upper/lowercase letter, digit, special character)"
    if (($SqlPassword -cmatch '[a-z]') -and ($SqlPassword -cmatch '[A-Z]') -and ($SqlPassword -match '\d') -and ($SqlPassword.Length -ge 8) -and ($SqlPassword -match '[!@#\$%\^&\*]')) {
        $complexPassword = 1
        Write-Host "Password accepted."
    } else {
        Write-Host "The password does not meet the complexity requirements. Try again."
    }
}

# 자원 이름 설정
$synapseWorkspace = "synapse$suffix"
$dataLakeAccountName = "datalake$suffix"
$sqlDatabaseName = "sql$suffix"

# 리소스 그룹 유효성 검증
$resourceGroup = Get-AzResourceGroup -Name $resourceGroupName -ErrorAction SilentlyContinue
if (-not $resourceGroup) {
    Write-Host "Resource group $resourceGroupName not found. Please create it first." -ForegroundColor Red
    Exit
}

# Synapse 작업 영역 생성
Write-Host "Creating $synapseWorkspace Synapse Analytics workspace in $resourceGroupName..."
New-AzResourceGroupDeployment -ResourceGroupName $resourceGroupName `
    -TemplateFile "setup.json" `
    -Mode Complete `
    -uniqueSuffix $suffix `
    -workspaceName $synapseWorkspace `
    -dataLakeAccountName $dataLakeAccountName `
    -sqlDatabaseName $sqlDatabaseName `
    -sqlUser $sqlUser `
    -sqlPassword $sqlPassword `
    -Force

# 데이터 레이크 권한 부여
Write-Host "Granting permissions on the $dataLakeAccountName storage account..."
$subscriptionId = (Get-AzContext).Subscription.Id
$userName = ((az ad signed-in-user show) | ConvertFrom-JSON).UserPrincipalName
$id = (Get-AzADServicePrincipal -DisplayName $synapseWorkspace).Id

New-AzRoleAssignment -ObjectId $id -RoleDefinitionName "Storage Blob Data Owner" -Scope "/subscriptions/$subscriptionId/resourceGroups/$resourceGroupName/providers/Microsoft.Storage/storageAccounts/$dataLakeAccountName" -ErrorAction SilentlyContinue
New-AzRoleAssignment -SignInName $userName -RoleDefinitionName "Storage Blob Data Owner" -Scope "/subscriptions/$subscriptionId/resourceGroups/$resourceGroupName/providers/Microsoft.Storage/storageAccounts/$dataLakeAccountName" -ErrorAction SilentlyContinue

# SQL 풀 생성
Write-Host "Creating the $sqlDatabaseName dedicated SQL pool..."
New-AzSynapseSqlPool -WorkspaceName $synapseWorkspace -Name $sqlDatabaseName -PerformanceLevel "DW100c" -ResourceGroupName $resourceGroupName

# 데이터 업로드
Write-Host "Uploading files to storage..."
$storageAccount = Get-AzStorageAccount -ResourceGroupName $resourceGroupName -Name $dataLakeAccountName
$storageContext = $storageAccount.Context
Get-ChildItem "./data/*.csv" -File | ForEach-Object {
    $file = $_.Name
    $blobPath = "data/$file"
    Set-AzStorageBlobContent -File $_.FullName -Container "files" -Blob $blobPath -Context $storageContext
}

# SQL 풀 일시 중지
Write-Host "Pausing the $sqlDatabaseName SQL Pool..."
Suspend-AzSynapseSqlPool -WorkspaceName $synapseWorkspace -Name $sqlDatabaseName -AsJob

Write-Host "Script completed at $(Get-Date)"
