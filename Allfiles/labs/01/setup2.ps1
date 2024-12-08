# 기존 리소스 그룹 설정
$existingResourceGroupName = Read-Host "Enter the existing Azure resource group name"

# 리소스 등록 확인 및 배포
Write-Host "Registering resource providers..."
$provider_list = "Microsoft.Synapse", "Microsoft.Sql", "Microsoft.Storage", "Microsoft.Compute"

foreach ($provider in $provider_list) {
    $currentStatus = (Get-AzResourceProvider -ProviderNamespace $provider).RegistrationState
    if ($currentStatus -eq "Registered") {
        Write-Host "$provider is successfully registered."
    } else {
        Write-Host "$provider registration failed. Please check your Azure account."
        Exit
    }
}

# 리소스 생성 시 기존 리소스 그룹 사용
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

# SQL 데이터베이스 생성
write-host "Creating the $sqlDatabaseName database..."
sqlcmd -S "$synapseWorkspace.sql.azuresynapse.net" -U $sqlUser -P $sqlPassword -d $sqlDatabaseName -I -i setup.sql

# 스토리지 역할 할당
Write-Host "Granting permissions on the $dataLakeAccountName storage account..."
$subscriptionId = (Get-AzContext).Subscription.Id
$userName = ((az ad signed-in-user show) | ConvertFrom-JSON).UserPrincipalName
$id = (Get-AzADServicePrincipal -DisplayName $synapseWorkspace).id

New-AzRoleAssignment -Objectid $id -RoleDefinitionName "Storage Blob Data Owner" -Scope "/subscriptions/$subscriptionId/resourceGroups/$existingResourceGroupName/providers/Microsoft.Storage/storageAccounts/$dataLakeAccountName" -ErrorAction SilentlyContinue
New-AzRoleAssignment -SignInName $userName -RoleDefinitionName "Storage Blob Data Owner" -Scope "/subscriptions/$subscriptionId/resourceGroups/$existingResourceGroupName/providers/Microsoft.Storage/storageAccounts/$dataLakeAccountName" -ErrorAction SilentlyContinue

Write-Host "Script completed at $(Get-Date)"
