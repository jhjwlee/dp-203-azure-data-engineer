Clear-Host
Write-Host "Starting script at $(Get-Date)"
Set-PSRepository -Name PSGallery -InstallationPolicy Trusted
Install-Module -Name Az.Synapse -Force

# Azure 구독 선택
$subs = Get-AzSubscription | Select-Object
if ($subs.GetType().IsArray -and $subs.length -gt 1) {
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
}

# 리소스 그룹 이름 입력 받기
$existingResourceGroupName = Read-Host "Enter the existing Azure resource group name"

# SQL 사용자 및 암호 설정
$sqlUser = "SQLUser"
$sqlPassword = ""
while ($sqlPassword -eq "") {
    $sqlPassword = Read-Host "Enter a password for the $sqlUser login (Minimum 8 characters with uppercase, lowercase, digit, and special character)"
    if ($sqlPassword -match "^(?=.*[a-z])(?=.*[A-Z])(?=.*\d)(?=.*[!@#$%^&*]).{8,}$") {
        Write-Host "Password accepted."
    } else {
        Write-Host "Password does not meet complexity requirements. Try again."
        $sqlPassword = ""
    }
}

# 리소스 공급자 등록
Write-Host "Registering resource providers..."
$provider_list = "Microsoft.Synapse", "Microsoft.Sql", "Microsoft.Storage", "Microsoft.Compute"
foreach ($provider in $provider_list) {
    $currentStatus = (Get-AzResourceProvider -ProviderNamespace $provider).RegistrationState
    if ($currentStatus -eq "Registered") {
        Write-Host "$provider is successfully registered."
    } else {
        Write-Host "Failed to register $provider. Please check your Azure account."
        Exit
    }
}

# 고유 접미사 생성
[string]$suffix = -join ((48..57) + (97..122) | Get-Random -Count 7 | % {[char]$_})
Write-Host "Your randomly-generated suffix for Azure resources is $suffix"

# 주요 변수 초기화
$synapseWorkspace = "synapse$suffix"
$dataLakeAccountName = "datalake$suffix"
$sparkPool = "spark$suffix"
$sqlDatabaseName = "sql$suffix"

# 초기화 상태 로깅
Write-Host "Initialized variables:"
Write-Host "Synapse Workspace: $synapseWorkspace"
Write-Host "Data Lake Account: $dataLakeAccountName"
Write-Host "Spark Pool: $sparkPool"
Write-Host "SQL Database: $sqlDatabaseName"

# 리소스 배포
Write-Host "Creating $synapseWorkspace Synapse Analytics workspace in $existingResourceGroupName resource group..."
New-AzResourceGroupDeployment -ResourceGroupName $existingResourceGroupName `
  -TemplateFile "setup.json" `
  -Mode Complete `
  -workspaceName $synapseWorkspace `
  -dataLakeAccountName $dataLakeAccountName `
  -sparkPoolName $sparkPool `
  -sqlDatabaseName $sqlDatabaseName `
  -sqlUser $sqlUser `
  -sqlPassword $sqlPassword `
  -uniqueSuffix $suffix `
  -Force

# 스토리지 역할 할당
Write-Host "Granting permissions on the $dataLakeAccountName storage account..."
$subscriptionId = (Get-AzContext).Subscription.Id
$userName = ((az ad signed-in-user show) | ConvertFrom-JSON).UserPrincipalName
$id = (Get-AzADServicePrincipal -DisplayName $synapseWorkspace).id

New-AzRoleAssignment -ObjectId $id -RoleDefinitionName "Storage Blob Data Owner" -Scope "/subscriptions/$subscriptionId/resourceGroups/$existingResourceGroupName/providers/Microsoft.Storage/storageAccounts/$dataLakeAccountName" -ErrorAction SilentlyContinue
New-AzRoleAssignment -SignInName $userName -RoleDefinitionName "Storage Blob Data Owner" -Scope "/subscriptions/$subscriptionId/resourceGroups/$existingResourceGroupName/providers/Microsoft.Storage/storageAccounts/$dataLakeAccountName" -ErrorAction SilentlyContinue

# SQL 데이터베이스 생성
Write-Host "Creating the $sqlDatabaseName database..."
sqlcmd -S "$synapseWorkspace.sql.azuresynapse.net" -U $sqlUser -P $sqlPassword -d $sqlDatabaseName -I -i setup.sql

# 데이터 로드
Write-Host "Loading data..."
Get-ChildItem "./data/*.txt" -File | ForEach-Object {
    $file = $_.FullName
    $table = $_.Name.Replace(".txt", "")
    $formatFile = $file.Replace(".txt", ".fmt")

    if (Test-Path $formatFile) {
        Write-Host "Loading $file into $table using format file $formatFile..."
        bcp dbo.$table in $file -S "$synapseWorkspace.sql.azuresynapse.net" -U $sqlUser -P $sqlPassword -d $sqlDatabaseName -f $formatFile -q -k -E -b 5000
    } else {
        Write-Host "Loading $file into $table without a format file..."
        bcp dbo.$table in $file -S "$synapseWorkspace.sql.azuresynapse.net" -U $sqlUser -P $sqlPassword -d $sqlDatabaseName -n -q -k -E -b 5000
    }
}

# SQL 풀 일시 중지
Write-Host "Pausing the $sqlDatabaseName SQL Pool..."
Suspend-AzSynapseSqlPool -WorkspaceName $synapseWorkspace -Name $sqlDatabaseName -AsJob

# 데이터 업로드
Write-Host "Uploading files..."
$storageAccount = Get-AzStorageAccount -ResourceGroupName $existingResourceGroupName -Name $dataLakeAccountName
$storageContext = $storageAccount.Context
Get-ChildItem "./files/*.csv" -File | ForEach-Object {
    $file = $_.Name
    $blobPath = "sales_data/$file"
    Set-AzStorageBlobContent -File $_.FullName -Container "files" -Blob $blobPath -Context $storageContext
}

Write-Host "Script completed at $(Get-Date)"
