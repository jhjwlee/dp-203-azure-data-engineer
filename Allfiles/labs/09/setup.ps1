Clear-Host
Write-Host "Starting script at $(Get-Date)"

Set-PSRepository -Name PSGallery -InstallationPolicy Trusted
Install-Module -Name Az.Synapse -Force

# Handle cases where the user has multiple subscriptions
$subs = Get-AzSubscription | Select-Object
if($subs.GetType().IsArray -and $subs.length -gt 1){
        Write-Host "You have multiple Azure subscriptions - please select the one you want to use:"
        for($i = 0; $i -lt $subs.length; $i++)
        {
                Write-Host "[$($i)]: $($subs[$i].Name) (ID = $($subs[$i].Id))"
        }
        $selectedIndex = -1
        $selectedValidIndex = 0
        while ($selectedValidIndex -ne 1)
        {
                $enteredValue = Read-Host("Enter 0 to $($subs.Length - 1)")
                if (-not ([string]::IsNullOrEmpty($enteredValue)))
                {
                    if ([int]$enteredValue -in (0..$($subs.Length - 1)))
                    {
                        $selectedIndex = [int]$enteredValue
                        $selectedValidIndex = 1
                    }
                    else
                    {
                        Write-Output "Please enter a valid subscription number."
                    }
                }
                else
                {
                    Write-Output "Please enter a valid subscription number."
                }
        }
        $selectedSub = $subs[$selectedIndex].Id
        Select-AzSubscription -SubscriptionId $selectedSub
        az account set --subscription $selectedSub
}

# Prompt user for a resource group
$resourceGroupName = Read-Host "Enter the existing resource group name"

# Validate resource group existence
try {
    $resourceGroup = Get-AzResourceGroup -Name $resourceGroupName -ErrorAction Stop
    Write-Host "Resource group '$resourceGroupName' found."
} catch {
    Write-Host "Resource group '$resourceGroupName' does not exist. Please create it first and try again."
    exit
}

# Prompt user for a password for the SQL Database
$sqlUser = "SQLUser"
write-host ""
$sqlPassword = ""
$complexPassword = 0

while ($complexPassword -ne 1)
{
    $SqlPassword = Read-Host "Enter a password to use for the $sqlUser login.
    `The password must meet complexity requirements:
    ` - Minimum 8 characters. 
    ` - At least one upper case English letter [A-Z]
    ` - At least one lower case English letter [a-z]
    ` - At least one digit [0-9]
    ` - At least one special character (!,@,#,%,^,&,$)
    ` "

    if(($SqlPassword -cmatch '[a-z]') -and ($SqlPassword -cmatch '[A-Z]') -and ($SqlPassword -match '\d') -and ($SqlPassword.length -ge 8) -and ($SqlPassword -match '!|@|#|%|\^|&|\$'))
    {
        $complexPassword = 1
        Write-Output "Password $SqlPassword accepted. Make sure you remember this!"
    }
    else
    {
        Write-Output "$SqlPassword does not meet the complexity requirements."
    }
}

# Generate unique random suffix
[string]$suffix =  -join ((48..57) + (97..122) | Get-Random -Count 7 | % {[char]$_})
Write-Host "Your randomly-generated suffix for Azure resources is $suffix"

# Create Synapse workspace
$synapseWorkspace = "synapse$suffix"
$dataLakeAccountName = "datalake$suffix"
sqlDatabaseName = "sql$suffix"

Write-Host "Creating $synapseWorkspace Synapse Analytics workspace in $resourceGroupName resource group..."
Write-Host "(This may take some time!)"
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
