<#
.SYNOPSIS
    Builds the "Power BI Service -> VNet Data Gateway -> Azure SQL Private Endpoint" lab
    infrastructure, README Phases 1 to 7.3, and prints a summary of everything done.

.DESCRIPTION
    Creates (idempotently: existing resources are reused, not recreated):
      Phase 1  Resource group, vnet-sql (snet-pe, snet-jumpbox), vnet-gateway, NAT gateway for jumpbox
      Phase 2  Azure SQL logical server + SalesDB (Basic)
      Phase 5  Tables, sample data, views (incl. vw_ConnectionProof) and pbi_reader user
               -> run BEFORE lock-down, through a temporary firewall rule for YOUR public IP only
      Phase 3  Private endpoint pe-sql, private DNS zone, link to vnet-sql,
               then public network access DISABLED and the temporary firewall rule removed
      Phase 4  vm-jumpbox (no public IP), auto-shutdown, Azure Bastion, DNS check from inside the VNet
      Phase 6  Bidirectional VNet peering + DNS zone link to vnet-gateway
      Phase 7  Microsoft.PowerPlatform provider registration, NSG (7.3), delegated snet-pbigateway

    Phase 8 onwards (Fabric capacity, workspace, VNet Data Gateway, connection, report) is done in
    the Azure Portal / https://app.powerbi.com as described in README.md.

.NOTES
    Requires: PowerShell 7.x (recommended) or Windows PowerShell 5.1
              Az modules: Az.Accounts, Az.Resources, Az.Network, Az.PrivateDns, Az.Sql, Az.Compute
              SqlServer module (v22+) for Invoke-Sqlcmd
    Missing modules are installed for the current user.

.EXAMPLE
    ./Deploy-PbiPrivateLab.ps1

.EXAMPLE
    ./Deploy-PbiPrivateLab.ps1 -SqlServerName sql-pbi-private-lab-raj01 -BastionSku Basic -InstallJumpboxTools
#>

[CmdletBinding()]
param(
    [string]$SubscriptionId,
    [string]$Location            = 'centralindia',
    [string]$ResourceGroupName   = 'rg-pbi-private-lab',

    # Networking
    [string]$SqlVnetName         = 'vnet-sql',
    [string]$SqlVnetPrefix       = '10.10.0.0/16',
    [string]$PeSubnetName        = 'snet-pe',
    [string]$PeSubnetPrefix      = '10.10.1.0/24',
    [string]$JumpSubnetName      = 'snet-jumpbox',
    [string]$JumpSubnetPrefix    = '10.10.2.0/24',
    [string]$BastionSubnetPrefix = '10.10.3.0/26',
    [string]$GwVnetName          = 'vnet-gateway',
    [string]$GwVnetPrefix        = '10.20.0.0/16',
    [string]$GwSubnetName        = 'snet-pbigateway',
    [string]$GwSubnetPrefix      = '10.20.2.0/27',

    # SQL
    [string]$SqlServerName       = 'sql-pbi-private-lab',
    [string]$DatabaseName        = 'SalesDB',
    [string]$SqlAdminLogin       = 'sqladminlab',
    [SecureString]$SqlAdminPassword,
    [SecureString]$PbiReaderPassword,
    [switch]$SetEntraAdminToMe,

    # Private endpoint / DNS
    [string]$PrivateEndpointName = 'pe-sql',
    [string]$PrivateDnsZoneName  = 'privatelink.database.windows.net',

    # Jumpbox
    [string]$VmName              = 'vm-jumpbox',
    [string]$VmSize              = 'Standard_B2ms',
    [string]$VmAdminUser         = 'labadmin',
    [SecureString]$VmAdminPassword,
    [string]$AutoShutdownTime    = '2200',             # HHmm, India Standard Time
    [ValidateSet('Developer','Basic','None')]
    [string]$BastionSku          = 'Developer',
    [switch]$SkipNatGateway,                          # NAT gives the jumpbox outbound internet to download tools
    [switch]$InstallJumpboxTools,                     # best-effort silent install of SSMS + Power BI Desktop

    # Gateway subnet
    [switch]$SkipGatewayNsg
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

# ----------------------------------------------------------------------------------------------
# Helpers
# ----------------------------------------------------------------------------------------------
$script:Summary   = [System.Collections.Generic.List[object]]::new()
$script:StartTime = Get-Date
$script:Info      = [ordered]@{}

function Write-Phase([string]$Text) {
    Write-Host ''
    Write-Host ('=' * 90) -ForegroundColor DarkCyan
    Write-Host "  $Text" -ForegroundColor Cyan
    Write-Host ('=' * 90) -ForegroundColor DarkCyan
}

function Write-Step([string]$Text) { Write-Host "  -> $Text" -ForegroundColor Gray }

function Add-Result {
    param([string]$Phase, [string]$Item, [ValidateSet('Created','Existing','Updated','Done','Skipped','Warning','Failed')][string]$Status, [string]$Detail = '')
    $script:Summary.Add([pscustomobject]@{ Phase = $Phase; Item = $Item; Status = $Status; Detail = $Detail })
    $color = switch ($Status) { 'Created' {'Green'} 'Updated' {'Green'} 'Done' {'Green'} 'Existing' {'Yellow'} 'Skipped' {'DarkGray'} 'Warning' {'DarkYellow'} 'Failed' {'Red'} }
    Write-Host ("     [{0,-8}] {1}  {2}" -f $Status, $Item, $Detail) -ForegroundColor $color
}

function ConvertTo-PlainText([SecureString]$Secure) {
    [System.Net.NetworkCredential]::new('', $Secure).Password
}

function Ensure-Module([string]$Name, [version]$MinimumVersion = '0.0') {
    $m = Get-Module -ListAvailable -Name $Name | Sort-Object Version -Descending | Select-Object -First 1
    if (-not $m -or $m.Version -lt $MinimumVersion) {
        Write-Step "Installing module $Name (current user)..."
        Install-Module -Name $Name -MinimumVersion $MinimumVersion -Scope CurrentUser -Force -AllowClobber -Repository PSGallery
    }
    Import-Module $Name -MinimumVersion $MinimumVersion -ErrorAction Stop | Out-Null
}

function Invoke-SqlBatch {
    param([string]$Query, [string]$Database, [int]$Retries = 6)
    $fqdn = "$SqlServerName.database.windows.net"
    for ($i = 1; $i -le $Retries; $i++) {
        try {
            return Invoke-Sqlcmd -ServerInstance $fqdn -Database $Database `
                -Username $SqlAdminLogin -Password $script:SqlAdminPlain `
                -Query $Query -Encrypt Mandatory -ConnectionTimeout 30 -QueryTimeout 120 -ErrorAction Stop
        } catch {
            if ($i -eq $Retries) { throw }
            Write-Step "SQL not reachable yet (attempt $i/$Retries): $($_.Exception.Message.Split([Environment]::NewLine)[0]). Retrying in 15s..."
            Start-Sleep -Seconds 15
        }
    }
}

# ----------------------------------------------------------------------------------------------
# Main
# ----------------------------------------------------------------------------------------------
try {
    Write-Phase 'Phase 0 - Pre-flight: modules, sign-in, inputs'

    foreach ($mod in 'Az.Accounts','Az.Resources','Az.Network','Az.PrivateDns','Az.Sql','Az.Compute') { Ensure-Module $mod }
    Ensure-Module 'SqlServer' '22.0.0'
    Add-Result 'Phase 0' 'PowerShell modules' 'Done' 'Az.* + SqlServer loaded'

    if (-not (Get-AzContext)) { Connect-AzAccount | Out-Null }
    if ($SubscriptionId) { Set-AzContext -Subscription $SubscriptionId | Out-Null }
    $ctx = Get-AzContext
    $subId = $ctx.Subscription.Id
    Add-Result 'Phase 0' 'Azure sign-in' 'Done' "$($ctx.Account.Id) / $($ctx.Subscription.Name) ($subId)"

    if (-not $SqlAdminPassword)  { $SqlAdminPassword  = Read-Host -AsSecureString "SQL admin password for '$SqlAdminLogin'" }
    if (-not $PbiReaderPassword) { $PbiReaderPassword = Read-Host -AsSecureString "Password for SQL user 'pbi_reader'" }
    if (-not $VmAdminPassword)   { $VmAdminPassword   = Read-Host -AsSecureString "Jumpbox local admin password for '$VmAdminUser'" }
    $script:SqlAdminPlain = ConvertTo-PlainText $SqlAdminPassword
    $pbiReaderPlain       = (ConvertTo-PlainText $PbiReaderPassword).Replace("'", "''")

    $myIp = (Invoke-RestMethod -Uri 'https://api.ipify.org' -TimeoutSec 20).ToString().Trim()
    Add-Result 'Phase 0' 'Your public IP' 'Done' "$myIp (used only for a temporary SQL firewall rule)"

    # ------------------------------------------------------------------------------------------
    Write-Phase 'Phase 1 - Resource group and virtual networks'
    # ------------------------------------------------------------------------------------------
    $rg = Get-AzResourceGroup -Name $ResourceGroupName -ErrorAction SilentlyContinue
    if ($rg) { Add-Result 'Phase 1' "Resource group $ResourceGroupName" 'Existing' $rg.Location }
    else {
        $rg = New-AzResourceGroup -Name $ResourceGroupName -Location $Location
        Add-Result 'Phase 1' "Resource group $ResourceGroupName" 'Created' $Location
    }

    # NAT gateway (outbound internet for the jumpbox: new VNets have no default outbound access)
    $nat = $null
    if (-not $SkipNatGateway) {
        $nat = Get-AzNatGateway -ResourceGroupName $ResourceGroupName -Name 'nat-jumpbox' -ErrorAction SilentlyContinue
        if ($nat) { Add-Result 'Phase 1' 'NAT gateway nat-jumpbox' 'Existing' }
        else {
            Write-Step 'Creating NAT gateway for jumpbox outbound internet...'
            $natPip = Get-AzPublicIpAddress -ResourceGroupName $ResourceGroupName -Name 'pip-nat-jumpbox' -ErrorAction SilentlyContinue
            if (-not $natPip) {
                $natPip = New-AzPublicIpAddress -ResourceGroupName $ResourceGroupName -Name 'pip-nat-jumpbox' -Location $Location -Sku Standard -AllocationMethod Static
            }
            $nat = New-AzNatGateway -ResourceGroupName $ResourceGroupName -Name 'nat-jumpbox' -Location $Location -Sku Standard -PublicIpAddress $natPip -IdleTimeoutInMinutes 4
            Add-Result 'Phase 1' 'NAT gateway nat-jumpbox' 'Created' "Public IP $($natPip.IpAddress)"
        }
    } else { Add-Result 'Phase 1' 'NAT gateway' 'Skipped' 'Jumpbox will have no outbound internet' }

    # vnet-sql
    $vnetSql = Get-AzVirtualNetwork -ResourceGroupName $ResourceGroupName -Name $SqlVnetName -ErrorAction SilentlyContinue
    if ($vnetSql) { Add-Result 'Phase 1' "VNet $SqlVnetName" 'Existing' ($vnetSql.AddressSpace.AddressPrefixes -join ',') }
    else {
        $peSub   = New-AzVirtualNetworkSubnetConfig -Name $PeSubnetName -AddressPrefix $PeSubnetPrefix
        $jumpArgs = @{ Name = $JumpSubnetName; AddressPrefix = $JumpSubnetPrefix }
        if ($nat) { $jumpArgs.NatGateway = $nat }
        $jumpSub = New-AzVirtualNetworkSubnetConfig @jumpArgs
        $subnets = @($peSub, $jumpSub)
        if ($BastionSku -eq 'Basic') { $subnets += New-AzVirtualNetworkSubnetConfig -Name 'AzureBastionSubnet' -AddressPrefix $BastionSubnetPrefix }
        $vnetSql = New-AzVirtualNetwork -ResourceGroupName $ResourceGroupName -Name $SqlVnetName -Location $Location -AddressPrefix $SqlVnetPrefix -Subnet $subnets
        Add-Result 'Phase 1' "VNet $SqlVnetName" 'Created' "$SqlVnetPrefix ; $PeSubnetName $PeSubnetPrefix ; $JumpSubnetName $JumpSubnetPrefix"
    }
    # make sure required subnets exist on an existing VNet
    $changed = $false
    if (-not ($vnetSql.Subnets | Where-Object Name -eq $PeSubnetName)) {
        Add-AzVirtualNetworkSubnetConfig -VirtualNetwork $vnetSql -Name $PeSubnetName -AddressPrefix $PeSubnetPrefix | Out-Null; $changed = $true }
    if (-not ($vnetSql.Subnets | Where-Object Name -eq $JumpSubnetName)) {
        $a = @{ VirtualNetwork = $vnetSql; Name = $JumpSubnetName; AddressPrefix = $JumpSubnetPrefix }; if ($nat) { $a.NatGateway = $nat }
        Add-AzVirtualNetworkSubnetConfig @a | Out-Null; $changed = $true }
    if ($BastionSku -eq 'Basic' -and -not ($vnetSql.Subnets | Where-Object Name -eq 'AzureBastionSubnet')) {
        Add-AzVirtualNetworkSubnetConfig -VirtualNetwork $vnetSql -Name 'AzureBastionSubnet' -AddressPrefix $BastionSubnetPrefix | Out-Null; $changed = $true }
    if ($changed) { $vnetSql = $vnetSql | Set-AzVirtualNetwork; Add-Result 'Phase 1' "VNet $SqlVnetName subnets" 'Updated' 'Missing subnets added' }

    # vnet-gateway (no subnets yet; delegated subnet comes in Phase 7)
    $vnetGw = Get-AzVirtualNetwork -ResourceGroupName $ResourceGroupName -Name $GwVnetName -ErrorAction SilentlyContinue
    if ($vnetGw) { Add-Result 'Phase 1' "VNet $GwVnetName" 'Existing' ($vnetGw.AddressSpace.AddressPrefixes -join ',') }
    else {
        $vnetGw = New-AzVirtualNetwork -ResourceGroupName $ResourceGroupName -Name $GwVnetName -Location $Location -AddressPrefix $GwVnetPrefix
        Add-Result 'Phase 1' "VNet $GwVnetName" 'Created' "$GwVnetPrefix (gateway subnet added in Phase 7)"
    }

    # ------------------------------------------------------------------------------------------
    Write-Phase 'Phase 2 - Azure SQL logical server and database'
    # ------------------------------------------------------------------------------------------
    $sql = Get-AzSqlServer -ResourceGroupName $ResourceGroupName -ServerName $SqlServerName -ErrorAction SilentlyContinue
    if ($sql) { Add-Result 'Phase 2' "SQL server $SqlServerName" 'Existing' $sql.FullyQualifiedDomainName }
    else {
        # global name check
        $taken = $false
        try { Resolve-DnsName "$SqlServerName.database.windows.net" -ErrorAction Stop | Out-Null; $taken = $true } catch {}
        if ($taken) { throw "SQL server name '$SqlServerName' is already used globally. Re-run with -SqlServerName <unique-name> (and use that name in README steps)." }

        Write-Step 'Creating SQL logical server (2-5 minutes)...'
        $cred = [pscredential]::new($SqlAdminLogin, $SqlAdminPassword)
        $sql = New-AzSqlServer -ResourceGroupName $ResourceGroupName -ServerName $SqlServerName -Location $Location `
                               -SqlAdministratorCredentials $cred -MinimalTlsVersion '1.2' -PublicNetworkAccess 'Enabled'
        Add-Result 'Phase 2' "SQL server $SqlServerName" 'Created' "$($sql.FullyQualifiedDomainName), admin $SqlAdminLogin"
    }

    if ($SetEntraAdminToMe) {
        try {
            $me = Get-AzADUser -SignedIn
            Set-AzSqlServerActiveDirectoryAdministrator -ResourceGroupName $ResourceGroupName -ServerName $SqlServerName -DisplayName $me.UserPrincipalName -ObjectId $me.Id | Out-Null
            Add-Result 'Phase 2' 'Microsoft Entra admin' 'Done' $me.UserPrincipalName
        } catch { Add-Result 'Phase 2' 'Microsoft Entra admin' 'Warning' $_.Exception.Message }
    }

    $db = Get-AzSqlDatabase -ResourceGroupName $ResourceGroupName -ServerName $SqlServerName -DatabaseName $DatabaseName -ErrorAction SilentlyContinue
    if ($db) { Add-Result 'Phase 2' "Database $DatabaseName" 'Existing' "$($db.Edition) / $($db.CurrentServiceObjectiveName)" }
    else {
        Write-Step "Creating database $DatabaseName (Basic)..."
        $db = New-AzSqlDatabase -ResourceGroupName $ResourceGroupName -ServerName $SqlServerName -DatabaseName $DatabaseName `
                                -Edition 'Basic' -RequestedServiceObjectiveName 'Basic' -BackupStorageRedundancy 'Local'
        Add-Result 'Phase 2' "Database $DatabaseName" 'Created' 'Basic (5 DTU), LRS backups'
    }

    # ------------------------------------------------------------------------------------------
    Write-Phase 'Phase 5 - Load schema and data (temporary firewall rule for your IP only)'
    # ------------------------------------------------------------------------------------------
    $tempRule = 'temp-deploy-script'
    $sqlNow = Get-AzSqlServer -ResourceGroupName $ResourceGroupName -ServerName $SqlServerName
    if ($sqlNow.PublicNetworkAccess -ne 'Enabled') {
        Write-Step 'Temporarily enabling public network access for data load...'
        Set-AzSqlServer -ResourceGroupName $ResourceGroupName -ServerName $SqlServerName -PublicNetworkAccess 'Enabled' | Out-Null
    }
    if (-not (Get-AzSqlServerFirewallRule -ResourceGroupName $ResourceGroupName -ServerName $SqlServerName -FirewallRuleName $tempRule -ErrorAction SilentlyContinue)) {
        New-AzSqlServerFirewallRule -ResourceGroupName $ResourceGroupName -ServerName $SqlServerName -FirewallRuleName $tempRule -StartIpAddress $myIp -EndIpAddress $myIp | Out-Null
    }
    Add-Result 'Phase 5' 'Temporary firewall rule' 'Created' "$tempRule = $myIp (removed in Phase 3)"
    Write-Step 'Waiting 20s for firewall rule propagation...'
    Start-Sleep -Seconds 20

    $batches = [ordered]@{
        'Table dbo.SalesOrders' = @"
IF OBJECT_ID('dbo.SalesOrders','U') IS NULL
CREATE TABLE dbo.SalesOrders
(
    OrderID      INT IDENTITY(1001,1) PRIMARY KEY,
    OrderDate    DATE           NOT NULL,
    CustomerName NVARCHAR(100)  NOT NULL,
    Region       NVARCHAR(50)   NOT NULL,
    Product      NVARCHAR(50)   NOT NULL,
    Quantity     INT            NOT NULL,
    UnitPrice    DECIMAL(12,2)  NOT NULL,
    SalesAmount  AS (Quantity * UnitPrice) PERSISTED,
    CreatedAt    DATETIME2      DEFAULT SYSUTCDATETIME()
);
"@
        'Sample data (12 rows)' = @"
IF NOT EXISTS (SELECT 1 FROM dbo.SalesOrders)
INSERT INTO dbo.SalesOrders (OrderDate, CustomerName, Region, Product, Quantity, UnitPrice)
VALUES
 ('2026-10-01','Rahul', 'Pune',     'Laptop',   2, 65000),
 ('2026-10-02','Priya', 'Mumbai',   'Monitor',  3, 12000),
 ('2026-10-03','Amit',  'Delhi',    'Keyboard', 5,  1500),
 ('2026-10-04','Neha',  'Bangalore','Laptop',   1, 65000),
 ('2026-10-05','Karan', 'Pune',     'Mouse',   10,   800),
 ('2026-10-06','Sneha', 'Mumbai',   'Laptop',   2, 65000),
 ('2026-10-07','Arjun', 'Delhi',    'Monitor',  4, 12000),
 ('2026-10-08','Pooja', 'Bangalore','Keyboard', 8,  1500),
 ('2026-10-09','Rohan', 'Pune',     'Monitor',  2, 12000),
 ('2026-10-10','Meera', 'Mumbai',   'Mouse',    6,   800),
 ('2026-10-11','Dev',   'Delhi',    'Laptop',   1, 65000),
 ('2026-10-12','Ananya','Bangalore','Mouse',   12,   800);
"@
        'View dbo.vw_SalesByRegion' = @"
CREATE OR ALTER VIEW dbo.vw_SalesByRegion
AS
SELECT Region,
       COUNT(*)         AS TotalOrders,
       SUM(Quantity)    AS TotalQuantity,
       SUM(SalesAmount) AS TotalSales
FROM dbo.SalesOrders
GROUP BY Region;
"@
        'View dbo.vw_ConnectionProof' = @"
CREATE OR ALTER VIEW dbo.vw_ConnectionProof
AS
SELECT
    CAST(CONNECTIONPROPERTY('client_net_address') AS NVARCHAR(50)) AS ClientIP,
    CAST(CONNECTIONPROPERTY('net_transport')      AS NVARCHAR(50)) AS NetTransport,
    CAST(CONNECTIONPROPERTY('protocol_type')      AS NVARCHAR(50)) AS ProtocolType,
    HOST_NAME()      AS ClientHostName,
    APP_NAME()       AS ClientAppName,
    SUSER_SNAME()    AS LoginName,
    SYSUTCDATETIME() AS QueriedAtUtc;
"@
        'User pbi_reader + SELECT grants' = @"
IF NOT EXISTS (SELECT 1 FROM sys.database_principals WHERE name = 'pbi_reader')
    CREATE USER pbi_reader WITH PASSWORD = '$pbiReaderPlain';
ELSE
    ALTER USER pbi_reader WITH PASSWORD = '$pbiReaderPlain';
GRANT SELECT ON dbo.SalesOrders        TO pbi_reader;
GRANT SELECT ON dbo.vw_SalesByRegion   TO pbi_reader;
GRANT SELECT ON dbo.vw_ConnectionProof TO pbi_reader;
"@
    }
    foreach ($k in $batches.Keys) {
        Write-Step "Running: $k"
        Invoke-SqlBatch -Query $batches[$k] -Database $DatabaseName | Out-Null
        Add-Result 'Phase 5' $k 'Done'
    }

    $check = Invoke-SqlBatch -Database $DatabaseName -Query 'SELECT COUNT(*) AS TotalOrders, SUM(SalesAmount) AS TotalSales, COUNT(DISTINCT Region) AS Regions FROM dbo.SalesOrders;'
    $script:Info['Data check'] = "Orders=$($check.TotalOrders)  TotalSales=$('{0:N0}' -f $check.TotalSales)  Regions=$($check.Regions)  (expected 12 / 539,900 / 4)"
    $status = if ($check.TotalOrders -eq 12 -and [decimal]$check.TotalSales -eq 539900) { 'Done' } else { 'Warning' }
    Add-Result 'Phase 5' 'Data verification' $status $script:Info['Data check']

    # ------------------------------------------------------------------------------------------
    Write-Phase 'Phase 3 - Private endpoint, private DNS, lock down public access'
    # ------------------------------------------------------------------------------------------
    $vnetSql  = Get-AzVirtualNetwork -ResourceGroupName $ResourceGroupName -Name $SqlVnetName
    $peSubnet = $vnetSql.Subnets | Where-Object Name -eq $PeSubnetName

    $pe = Get-AzPrivateEndpoint -ResourceGroupName $ResourceGroupName -Name $PrivateEndpointName -ErrorAction SilentlyContinue
    if ($pe) { Add-Result 'Phase 3' "Private endpoint $PrivateEndpointName" 'Existing' }
    else {
        Write-Step 'Creating private endpoint (1-3 minutes)...'
        $plsc = New-AzPrivateLinkServiceConnection -Name "$PrivateEndpointName-conn" -PrivateLinkServiceId $sql.ResourceId -GroupId 'sqlServer'
        $pe = New-AzPrivateEndpoint -ResourceGroupName $ResourceGroupName -Name $PrivateEndpointName -Location $Location `
                                    -Subnet $peSubnet -PrivateLinkServiceConnection $plsc -CustomNetworkInterfaceName "$PrivateEndpointName-nic"
        Add-Result 'Phase 3' "Private endpoint $PrivateEndpointName" 'Created' "$SqlVnetName/$PeSubnetName, sub-resource sqlServer"
    }
    $peNic = Get-AzNetworkInterface -ResourceId $pe.NetworkInterfaces[0].Id
    $peIp  = $peNic.IpConfigurations[0].PrivateIpAddress
    $script:Info['Private endpoint IP (<PE_IP>)'] = $peIp
    $peState = $pe.PrivateLinkServiceConnections[0].PrivateLinkServiceConnectionState.Status
    Add-Result 'Phase 3' 'Private endpoint IP / state' 'Done' "$peIp / $peState"

    $zone = Get-AzPrivateDnsZone -ResourceGroupName $ResourceGroupName -Name $PrivateDnsZoneName -ErrorAction SilentlyContinue
    if ($zone) { Add-Result 'Phase 3' "Private DNS zone $PrivateDnsZoneName" 'Existing' }
    else {
        $zone = New-AzPrivateDnsZone -ResourceGroupName $ResourceGroupName -Name $PrivateDnsZoneName
        Add-Result 'Phase 3' "Private DNS zone $PrivateDnsZoneName" 'Created'
    }

    $linkSql = Get-AzPrivateDnsVirtualNetworkLink -ResourceGroupName $ResourceGroupName -ZoneName $PrivateDnsZoneName -Name 'link-vnet-sql' -ErrorAction SilentlyContinue
    if ($linkSql) { Add-Result 'Phase 3' 'DNS link link-vnet-sql' 'Existing' }
    else {
        New-AzPrivateDnsVirtualNetworkLink -ResourceGroupName $ResourceGroupName -ZoneName $PrivateDnsZoneName -Name 'link-vnet-sql' -VirtualNetworkId $vnetSql.Id | Out-Null
        Add-Result 'Phase 3' 'DNS link link-vnet-sql' 'Created' "-> $SqlVnetName (auto-registration off)"
    }

    $zg = Get-AzPrivateDnsZoneGroup -ResourceGroupName $ResourceGroupName -PrivateEndpointName $PrivateEndpointName -ErrorAction SilentlyContinue
    if ($zg) { Add-Result 'Phase 3' 'PE DNS zone group (A record)' 'Existing' }
    else {
        $zcfg = New-AzPrivateDnsZoneConfig -Name 'privatelink-database-windows-net' -PrivateDnsZoneId $zone.ResourceId
        New-AzPrivateDnsZoneGroup -ResourceGroupName $ResourceGroupName -PrivateEndpointName $PrivateEndpointName -Name 'default' -PrivateDnsZoneConfig $zcfg | Out-Null
        Add-Result 'Phase 3' 'PE DNS zone group (A record)' 'Created' "$SqlServerName -> $peIp"
    }

    # lock down
    Remove-AzSqlServerFirewallRule -ResourceGroupName $ResourceGroupName -ServerName $SqlServerName -FirewallRuleName $tempRule -Force -ErrorAction SilentlyContinue | Out-Null
    Add-Result 'Phase 3' 'Temporary firewall rule' 'Done' "$tempRule removed"
    Set-AzSqlServer -ResourceGroupName $ResourceGroupName -ServerName $SqlServerName -PublicNetworkAccess 'Disabled' | Out-Null
    $pna = (Get-AzSqlServer -ResourceGroupName $ResourceGroupName -ServerName $SqlServerName).PublicNetworkAccess
    $script:Info['SQL public network access'] = $pna
    Add-Result 'Phase 3' 'SQL public network access' ($(if ($pna -eq 'Disabled') {'Updated'} else {'Warning'})) $pna

    # ------------------------------------------------------------------------------------------
    Write-Phase 'Phase 4 - Jumpbox VM inside vnet-sql + Bastion'
    # ------------------------------------------------------------------------------------------
    $vm = Get-AzVM -ResourceGroupName $ResourceGroupName -Name $VmName -ErrorAction SilentlyContinue
    if ($vm) { Add-Result 'Phase 4' "VM $VmName" 'Existing' $vm.HardwareProfile.VmSize }
    else {
        Write-Step 'Creating jumpbox VM (3-6 minutes)...'
        $jumpSubnet = $vnetSql.Subnets | Where-Object Name -eq $JumpSubnetName
        $nic = Get-AzNetworkInterface -ResourceGroupName $ResourceGroupName -Name "$VmName-nic" -ErrorAction SilentlyContinue
        if (-not $nic) { $nic = New-AzNetworkInterface -ResourceGroupName $ResourceGroupName -Name "$VmName-nic" -Location $Location -SubnetId $jumpSubnet.Id }

        $vmCred = [pscredential]::new($VmAdminUser, $VmAdminPassword)
        $cfg = New-AzVMConfig -VMName $VmName -VMSize $VmSize -SecurityType 'TrustedLaunch'
        $cfg = Set-AzVMUefi -VM $cfg -EnableVtpm $true -EnableSecureBoot $true
        $cfg = Set-AzVMOperatingSystem -VM $cfg -Windows -ComputerName 'jumpbox' -Credential $vmCred -ProvisionVMAgent -EnableAutoUpdate
        $cfg = Set-AzVMSourceImage -VM $cfg -PublisherName 'MicrosoftWindowsServer' -Offer 'WindowsServer' -Skus '2022-datacenter-azure-edition' -Version 'latest'
        $cfg = Set-AzVMOSDisk -VM $cfg -Name "$VmName-osdisk" -CreateOption FromImage -StorageAccountType 'StandardSSD_LRS'
        $cfg = Add-AzVMNetworkInterface -VM $cfg -Id $nic.Id
        $cfg = Set-AzVMBootDiagnostic -VM $cfg -Enable
        New-AzVM -ResourceGroupName $ResourceGroupName -Location $Location -VM $cfg | Out-Null
        $vm = Get-AzVM -ResourceGroupName $ResourceGroupName -Name $VmName
        Add-Result 'Phase 4' "VM $VmName" 'Created' "$VmSize, Windows Server 2022, no public IP"
    }
    $vmNic = Get-AzNetworkInterface -ResourceId $vm.NetworkProfile.NetworkInterfaces[0].Id
    $script:Info['Jumpbox private IP'] = $vmNic.IpConfigurations[0].PrivateIpAddress

    # auto-shutdown
    try {
        $schedId = "/subscriptions/$subId/resourceGroups/$ResourceGroupName/providers/microsoft.devtestlab/schedules/shutdown-computevm-$VmName"
        $props = @{
            status = 'Enabled'; taskType = 'ComputeVmShutdownTask'
            dailyRecurrence = @{ time = $AutoShutdownTime }; timeZoneId = 'India Standard Time'
            notificationSettings = @{ status = 'Disabled' }; targetResourceId = $vm.Id
        }
        New-AzResource -ResourceId $schedId -Location $Location -Properties $props -Force | Out-Null
        Add-Result 'Phase 4' 'Auto-shutdown' 'Done' "$AutoShutdownTime India Standard Time"
    } catch { Add-Result 'Phase 4' 'Auto-shutdown' 'Warning' $_.Exception.Message }

    # Bastion
    $bastionName = "bas-$SqlVnetName"
    switch ($BastionSku) {
        'None' { Add-Result 'Phase 4' 'Azure Bastion' 'Skipped' 'BastionSku=None' }
        'Developer' {
            $existing = Get-AzBastion -ResourceGroupName $ResourceGroupName -Name $bastionName -ErrorAction SilentlyContinue
            if ($existing) { Add-Result 'Phase 4' "Bastion $bastionName" 'Existing' $existing.Sku.Name }
            else {
                $body = @{ location = $Location; sku = @{ name = 'Developer' }; properties = @{ virtualNetwork = @{ id = $vnetSql.Id } } } | ConvertTo-Json -Depth 5
                $resp = Invoke-AzRestMethod -Method PUT -Payload $body `
                        -Path "/subscriptions/$subId/resourceGroups/$ResourceGroupName/providers/Microsoft.Network/bastionHosts/${bastionName}?api-version=2023-09-01"
                if ($resp.StatusCode -in 200,201) { Add-Result 'Phase 4' "Bastion $bastionName" 'Created' 'Developer SKU (free, provisioning in background)' }
                else { Add-Result 'Phase 4' "Bastion $bastionName" 'Warning' "Developer SKU not accepted ($($resp.StatusCode)). Re-run with -BastionSku Basic. $($resp.Content)" }
            }
        }
        'Basic' {
            $existing = Get-AzBastion -ResourceGroupName $ResourceGroupName -Name $bastionName -ErrorAction SilentlyContinue
            if ($existing) { Add-Result 'Phase 4' "Bastion $bastionName" 'Existing' $existing.Sku.Name }
            else {
                Write-Step 'Creating Bastion Basic (5-10 minutes)...'
                $bpip = Get-AzPublicIpAddress -ResourceGroupName $ResourceGroupName -Name "pip-$bastionName" -ErrorAction SilentlyContinue
                if (-not $bpip) { $bpip = New-AzPublicIpAddress -ResourceGroupName $ResourceGroupName -Name "pip-$bastionName" -Location $Location -Sku Standard -AllocationMethod Static }
                New-AzBastion -ResourceGroupName $ResourceGroupName -Name $bastionName -PublicIpAddress $bpip -VirtualNetwork $vnetSql -Sku 'Basic' | Out-Null
                Add-Result 'Phase 4' "Bastion $bastionName" 'Created' 'Basic SKU'
            }
        }
    }

    # DNS check from inside the VNet (README 4.4)
    try {
        Write-Step 'Resolving SQL FQDN from inside the jumpbox (Run Command, ~1-2 min)...'
        $fqdn = "$SqlServerName.database.windows.net"
        $rc = Invoke-AzVMRunCommand -ResourceGroupName $ResourceGroupName -VMName $VmName -CommandId 'RunPowerShellScript' `
              -ScriptString "(Resolve-DnsName '$fqdn' | Where-Object { `$_.IPAddress } | Select-Object -First 1).IPAddress"
        $insideIp = ($rc.Value[0].Message).Trim()
        $script:Info['DNS from jumpbox'] = "$fqdn -> $insideIp"
        Add-Result 'Phase 4' 'DNS check from jumpbox' ($(if ($insideIp -eq $peIp) {'Done'} else {'Warning'})) "$insideIp (expected $peIp)"
    } catch { Add-Result 'Phase 4' 'DNS check from jumpbox' 'Warning' $_.Exception.Message }
    try {
        $outsideIp = (Resolve-DnsName "$SqlServerName.database.windows.net" -ErrorAction Stop | Where-Object { $_.PSObject.Properties['IPAddress'] -and $_.IPAddress } | Select-Object -First 1).IPAddress
        $script:Info['DNS from this machine'] = "$SqlServerName.database.windows.net -> $outsideIp (public)"
        Add-Result 'Phase 4' 'DNS check from this machine' 'Done' "$outsideIp (public, expected)"
    } catch { Add-Result 'Phase 4' 'DNS check from this machine' 'Skipped' 'Resolve-DnsName not available on this OS' }

    if ($InstallJumpboxTools) {
        if ($SkipNatGateway) { Add-Result 'Phase 4' 'Jumpbox tools' 'Skipped' 'No outbound internet (NAT skipped)' }
        else {
            $installScript = @'
$ErrorActionPreference = 'Continue'
New-Item -ItemType Directory -Path C:\LabTools -Force | Out-Null
[Net.ServicePointManager]::SecurityProtocol = 'Tls12'
Invoke-WebRequest -Uri 'https://aka.ms/ssmsfullsetup' -OutFile C:\LabTools\SSMS-Setup.exe -UseBasicParsing
Start-Process C:\LabTools\SSMS-Setup.exe -ArgumentList '/install','/quiet','/norestart' -Wait
Invoke-WebRequest -Uri 'https://download.microsoft.com/download/8/8/0/880BCA75-79DD-466A-927D-1ABF1F5454B0/PBIDesktopSetup_x64.exe' -OutFile C:\LabTools\PBIDesktopSetup_x64.exe -UseBasicParsing
Start-Process C:\LabTools\PBIDesktopSetup_x64.exe -ArgumentList '-quiet','-norestart','ACCEPT_EULA=1' -Wait
'install finished'
'@
            Invoke-AzVMRunCommand -ResourceGroupName $ResourceGroupName -VMName $VmName -CommandId 'RunPowerShellScript' -ScriptString $installScript -AsJob | Out-Null
            Add-Result 'Phase 4' 'Jumpbox tools' 'Done' 'SSMS + Power BI Desktop install started in background (15-25 min)'
        }
    } else { Add-Result 'Phase 4' 'Jumpbox tools' 'Skipped' 'Install SSMS + Power BI Desktop manually (or use -InstallJumpboxTools)' }

    # ------------------------------------------------------------------------------------------
    Write-Phase 'Phase 6 - VNet peering and DNS link for vnet-gateway'
    # ------------------------------------------------------------------------------------------
    $vnetSql = Get-AzVirtualNetwork -ResourceGroupName $ResourceGroupName -Name $SqlVnetName
    $vnetGw  = Get-AzVirtualNetwork -ResourceGroupName $ResourceGroupName -Name $GwVnetName

    if (Get-AzVirtualNetworkPeering -ResourceGroupName $ResourceGroupName -VirtualNetworkName $SqlVnetName -Name 'sql-to-gateway' -ErrorAction SilentlyContinue) {
        Add-Result 'Phase 6' 'Peering sql-to-gateway' 'Existing'
    } else {
        Add-AzVirtualNetworkPeering -Name 'sql-to-gateway' -VirtualNetwork $vnetSql -RemoteVirtualNetworkId $vnetGw.Id | Out-Null
        Add-Result 'Phase 6' 'Peering sql-to-gateway' 'Created' "$SqlVnetName -> $GwVnetName"
    }
    if (Get-AzVirtualNetworkPeering -ResourceGroupName $ResourceGroupName -VirtualNetworkName $GwVnetName -Name 'gateway-to-sql' -ErrorAction SilentlyContinue) {
        Add-Result 'Phase 6' 'Peering gateway-to-sql' 'Existing'
    } else {
        Add-AzVirtualNetworkPeering -Name 'gateway-to-sql' -VirtualNetwork $vnetGw -RemoteVirtualNetworkId $vnetSql.Id | Out-Null
        Add-Result 'Phase 6' 'Peering gateway-to-sql' 'Created' "$GwVnetName -> $SqlVnetName"
    }
    Start-Sleep -Seconds 10
    $p1 = Get-AzVirtualNetworkPeering -ResourceGroupName $ResourceGroupName -VirtualNetworkName $SqlVnetName -Name 'sql-to-gateway'
    $p2 = Get-AzVirtualNetworkPeering -ResourceGroupName $ResourceGroupName -VirtualNetworkName $GwVnetName  -Name 'gateway-to-sql'
    $script:Info['Peering state'] = "sql-to-gateway=$($p1.PeeringState)  gateway-to-sql=$($p2.PeeringState)"
    Add-Result 'Phase 6' 'Peering state' ($(if ($p1.PeeringState -eq 'Connected' -and $p2.PeeringState -eq 'Connected') {'Done'} else {'Warning'})) $script:Info['Peering state']

    $linkGw = Get-AzPrivateDnsVirtualNetworkLink -ResourceGroupName $ResourceGroupName -ZoneName $PrivateDnsZoneName -Name 'link-vnet-gateway' -ErrorAction SilentlyContinue
    if ($linkGw) { Add-Result 'Phase 6' 'DNS link link-vnet-gateway' 'Existing' }
    else {
        New-AzPrivateDnsVirtualNetworkLink -ResourceGroupName $ResourceGroupName -ZoneName $PrivateDnsZoneName -Name 'link-vnet-gateway' -VirtualNetworkId $vnetGw.Id | Out-Null
        Add-Result 'Phase 6' 'DNS link link-vnet-gateway' 'Created' "-> $GwVnetName (auto-registration off)"
    }

    # ------------------------------------------------------------------------------------------
    Write-Phase 'Phase 7 - Resource provider, NSG and delegated gateway subnet'
    # ------------------------------------------------------------------------------------------
    $prov = Get-AzResourceProvider -ProviderNamespace 'Microsoft.PowerPlatform'
    if ($prov[0].RegistrationState -eq 'Registered') { Add-Result 'Phase 7' 'Provider Microsoft.PowerPlatform' 'Existing' 'Registered' }
    else {
        Register-AzResourceProvider -ProviderNamespace 'Microsoft.PowerPlatform' | Out-Null
        Write-Step 'Waiting for Microsoft.PowerPlatform registration...'
        for ($i = 0; $i -lt 30; $i++) {
            Start-Sleep -Seconds 10
            if ((Get-AzResourceProvider -ProviderNamespace 'Microsoft.PowerPlatform')[0].RegistrationState -eq 'Registered') { break }
        }
        $state = (Get-AzResourceProvider -ProviderNamespace 'Microsoft.PowerPlatform')[0].RegistrationState
        Add-Result 'Phase 7' 'Provider Microsoft.PowerPlatform' ($(if ($state -eq 'Registered') {'Done'} else {'Warning'})) $state
    }

    # 7.3 NSG
    $nsg = $null
    if (-not $SkipGatewayNsg) {
        $nsg = Get-AzNetworkSecurityGroup -ResourceGroupName $ResourceGroupName -Name 'nsg-pbigateway' -ErrorAction SilentlyContinue
        if ($nsg) { Add-Result 'Phase 7' 'NSG nsg-pbigateway' 'Existing' }
        else {
            $rules = @(
                New-AzNetworkSecurityRuleConfig -Name 'Allow-Out-SQL-PE-1433'  -Direction Outbound -Priority 100 -Access Allow -Protocol Tcp -SourceAddressPrefix $GwSubnetPrefix -SourcePortRange '*' -DestinationAddressPrefix "$peIp/32" -DestinationPortRange 1433
                New-AzNetworkSecurityRuleConfig -Name 'Allow-Out-EntraID-443'  -Direction Outbound -Priority 110 -Access Allow -Protocol Tcp -SourceAddressPrefix $GwSubnetPrefix -SourcePortRange '*' -DestinationAddressPrefix 'AzureActiveDirectory' -DestinationPortRange 443
                New-AzNetworkSecurityRuleConfig -Name 'Allow-Out-CRL-80-443'   -Direction Outbound -Priority 120 -Access Allow -Protocol Tcp -SourceAddressPrefix $GwSubnetPrefix -SourcePortRange '*' -DestinationAddressPrefix 'Internet' -DestinationPortRange @('80','443')
                New-AzNetworkSecurityRuleConfig -Name 'Allow-Out-IntraSubnet'  -Direction Outbound -Priority 130 -Access Allow -Protocol '*' -SourceAddressPrefix $GwSubnetPrefix -SourcePortRange '*' -DestinationAddressPrefix $GwSubnetPrefix -DestinationPortRange '*'
                New-AzNetworkSecurityRuleConfig -Name 'Allow-In-IntraSubnet'   -Direction Inbound  -Priority 100 -Access Allow -Protocol '*' -SourceAddressPrefix $GwSubnetPrefix -SourcePortRange '*' -DestinationAddressPrefix $GwSubnetPrefix -DestinationPortRange '*'
            )
            $nsg = New-AzNetworkSecurityGroup -ResourceGroupName $ResourceGroupName -Name 'nsg-pbigateway' -Location $Location -SecurityRules $rules
            Add-Result 'Phase 7' 'NSG nsg-pbigateway' 'Created' "1433->$peIp, 443->AzureActiveDirectory, 80/443->Internet (CRL), intra-subnet"
        }
    } else { Add-Result 'Phase 7' 'NSG for gateway subnet' 'Skipped' '-SkipGatewayNsg' }

    # delegated subnet
    $vnetGw = Get-AzVirtualNetwork -ResourceGroupName $ResourceGroupName -Name $GwVnetName
    $gwSub  = $vnetGw.Subnets | Where-Object Name -eq $GwSubnetName
    if ($gwSub) {
        $hasDelegation = $gwSub.Delegations | Where-Object ServiceName -eq 'Microsoft.PowerPlatform/vnetaccesslinks'
        if ($hasDelegation) { Add-Result 'Phase 7' "Subnet $GwSubnetName" 'Existing' "$($gwSub.AddressPrefix -join ',') delegated" }
        else {
            $gwSub = Add-AzDelegation -Name 'pbi-vnetaccesslinks' -ServiceName 'Microsoft.PowerPlatform/vnetaccesslinks' -Subnet $gwSub
            $vnetGw | Set-AzVirtualNetwork | Out-Null
            Add-Result 'Phase 7' "Subnet $GwSubnetName" 'Updated' 'Delegation added'
        }
    } else {
        $deleg = New-AzDelegation -Name 'pbi-vnetaccesslinks' -ServiceName 'Microsoft.PowerPlatform/vnetaccesslinks'
        $sa = @{ VirtualNetwork = $vnetGw; Name = $GwSubnetName; AddressPrefix = $GwSubnetPrefix; Delegation = $deleg }
        if ($nsg) { $sa.NetworkSecurityGroup = $nsg }
        Add-AzVirtualNetworkSubnetConfig @sa | Out-Null
        $vnetGw | Set-AzVirtualNetwork | Out-Null
        Add-Result 'Phase 7' "Subnet $GwSubnetName" 'Created' "$GwSubnetPrefix, delegated to Microsoft.PowerPlatform/vnetaccesslinks$(if ($nsg) {', NSG attached'})"
    }
}
catch {
    Add-Result 'ERROR' 'Script stopped' 'Failed' $_.Exception.Message
    Write-Host ''
    Write-Host "  Script stopped: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "  At: $($_.InvocationInfo.PositionMessage)" -ForegroundColor DarkRed
    Write-Host '  Fix the issue and re-run: existing resources are reused, not recreated.' -ForegroundColor Yellow
}
finally {
    # ------------------------------------------------------------------------------------------
    # On-screen summary
    # ------------------------------------------------------------------------------------------
    $elapsed = (Get-Date) - $script:StartTime
    Write-Host ''
    Write-Host ('#' * 90) -ForegroundColor Green
    Write-Host '  DEPLOYMENT SUMMARY - README Phases 1 to 7.3' -ForegroundColor Green
    Write-Host ('#' * 90) -ForegroundColor Green
    $script:Summary | Format-Table -AutoSize -Wrap Phase, Status, Item, Detail | Out-String -Width 220 | Write-Host

    $counts = $script:Summary | Group-Object Status | ForEach-Object { "$($_.Name)=$($_.Count)" }
    Write-Host ("  Totals: {0}    Elapsed: {1:mm\:ss}" -f ($counts -join '  '), $elapsed) -ForegroundColor White

    if ($script:Info.Count -gt 0) {
        Write-Host ''
        Write-Host '  KEY VALUES (copy these into your lab notes)' -ForegroundColor Cyan
        Write-Host ("    {0,-32} {1}" -f 'SQL server FQDN', "$SqlServerName.database.windows.net")
        Write-Host ("    {0,-32} {1}" -f 'Database / read-only user', "$DatabaseName / pbi_reader")
        foreach ($k in $script:Info.Keys) { Write-Host ("    {0,-32} {1}" -f $k, $script:Info[$k]) }
        Write-Host ("    {0,-32} {1}" -f 'Gateway subnet (expected ClientIP)', "$GwVnetName/$GwSubnetName  $GwSubnetPrefix")
    }

    Write-Host ''
    Write-Host '  NEXT (manual, see README.md):' -ForegroundColor Cyan
    Write-Host '    Phase 4  Connect to vm-jumpbox via Bastion; install SSMS + Power BI Desktop if not done.'
    Write-Host '    Phase 8  Create Fabric F2 capacity + workspace PBI-Private-Lab (license mode: Fabric capacity).'
    Write-Host '    Phase 9  app.powerbi.com > Settings > Manage connections and gateways > Virtual network data gateways > New'
    Write-Host "             VNet $GwVnetName / subnet $GwSubnetName / name pbi-vnet-gateway"
    Write-Host '    Phase 10+ Create connection conn-sql-salesdb, build report on jumpbox, publish, bind, prove.'
    Write-Host ''

    $outFile = Join-Path (Get-Location) ("lab-deploy-summary-{0:yyyyMMdd-HHmmss}.txt" -f (Get-Date))
    try {
        ($script:Summary | Format-Table -AutoSize -Wrap Phase, Status, Item, Detail | Out-String -Width 220) +
        "`r`n" + (($script:Info.GetEnumerator() | ForEach-Object { "{0,-32} {1}" -f $_.Key, $_.Value }) -join "`r`n") |
            Set-Content -Path $outFile -Encoding UTF8
        Write-Host "  Summary also saved to: $outFile" -ForegroundColor DarkGray
    } catch {}

    $script:SqlAdminPlain = $null
}
