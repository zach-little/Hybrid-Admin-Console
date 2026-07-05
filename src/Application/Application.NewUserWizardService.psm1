Set-StrictMode -Version Latest

$script:HybridNewUserWizardState = @{
    Initialized = $false
    ActiveDirectory = $null
    ExchangeOnline = $null
    LastError = $null
    DefaultUpnSuffix = 'atlas-tech.com'
    RemoteRoutingDomain = 'atlastechcloud.mail.onmicrosoft.com'
    NotificationRecipient = 'ITSupport@atlas-tech.com'
    NotificationSender = 'NEW-HIRE-INFO@atlas-tech.com'
    Configuration = $null
}

function Invoke-HybridNewUserProviderOperation {
    [CmdletBinding()]
    param(
        [AllowNull()][object]$Provider,
        [Parameter(Mandatory=$true)][string[]]$OperationNames,
        [object[]]$Arguments = @()
    )

    if ($null -eq $Provider) { return $null }
    $providerPropertyNames = @($Provider.PSObject.Properties | ForEach-Object { $_.Name })
    foreach ($operationName in $OperationNames) {
        if ($providerPropertyNames -contains $operationName) {
            $operation = $Provider.$operationName
            if ($operation -is [scriptblock]) { return & $operation @Arguments }
            if ($null -ne $operation -and $operation.PSObject.Methods.Name -contains 'Invoke') { return $operation.Invoke($Arguments) }
        }
    }
    return $null
}

function Initialize-HybridNewUserWizardService {
    [CmdletBinding()]
    param(
        [AllowNull()][object]$ActiveDirectoryProvider,
        [AllowNull()][object]$ExchangeOnlineProvider,
        [string]$DefaultUpnSuffix = 'atlas-tech.com',
        [string]$RemoteRoutingDomain = 'atlastechcloud.mail.onmicrosoft.com',
        [AllowNull()][string]$NotificationRecipient,
        [AllowNull()][string]$NotificationSender,
        [AllowNull()][object]$Configuration = $null
    )

    $script:HybridNewUserWizardState.ActiveDirectory = $ActiveDirectoryProvider
    $script:HybridNewUserWizardState.ExchangeOnline = $ExchangeOnlineProvider
    $script:HybridNewUserWizardState.Configuration = Resolve-HybridNewUserWizardConfiguration -Configuration $Configuration
    $script:HybridNewUserWizardState.DefaultUpnSuffix = if ([string]::IsNullOrWhiteSpace($DefaultUpnSuffix)) { 'atlas-tech.com' } else { $DefaultUpnSuffix }
    $script:HybridNewUserWizardState.RemoteRoutingDomain = if ([string]::IsNullOrWhiteSpace($RemoteRoutingDomain)) { 'atlastechcloud.mail.onmicrosoft.com' } else { $RemoteRoutingDomain }
    $script:HybridNewUserWizardState.NotificationRecipient = if ([string]::IsNullOrWhiteSpace($NotificationRecipient)) { [string]$script:HybridNewUserWizardState.Configuration.NotificationRecipient } else { $NotificationRecipient.Trim() }
    $script:HybridNewUserWizardState.NotificationSender = if ([string]::IsNullOrWhiteSpace($NotificationSender)) { [string]$script:HybridNewUserWizardState.Configuration.NotificationSender } else { $NotificationSender.Trim() }
    $script:HybridNewUserWizardState.LastError = $null
    $script:HybridNewUserWizardState.Initialized = $true

    [pscustomobject]@{
        PSTypeName = 'Hybrid.NewUserWizard.Service'
        Name = 'NewUserWizardService'
        Initialized = $true
        GetManagers = ({ Get-HybridNewUserManagerOptions }).GetNewClosure()
        Validate = ({ param([object]$Request) Test-HybridNewUserRequest -Request $Request }).GetNewClosure()
        Preview = ({ param([object]$Request) Get-HybridNewUserPreviewPlan -Request $Request }).GetNewClosure()
        Execute = ({ param([object]$Request, [securestring]$AccountPassword) Invoke-HybridNewUserCreation -Request $Request -AccountPassword $AccountPassword }).GetNewClosure()
        GetDefaults = ({ [pscustomobject]@{ NotificationRecipient = $script:HybridNewUserWizardState.NotificationRecipient; NotificationSender = $script:HybridNewUserWizardState.NotificationSender; Configuration = $script:HybridNewUserWizardState.Configuration } }).GetNewClosure()
    }
}

function Update-HybridNewUserWizardConfiguration {
    [CmdletBinding()]
    param([AllowNull()][object]$Configuration)

    $resolved = Resolve-HybridNewUserWizardConfiguration -Configuration $Configuration
    $script:HybridNewUserWizardState.Configuration = $resolved
    if (-not [string]::IsNullOrWhiteSpace([string]$resolved.NotificationRecipient)) { $script:HybridNewUserWizardState.NotificationRecipient = [string]$resolved.NotificationRecipient }
    if (-not [string]::IsNullOrWhiteSpace([string]$resolved.NotificationSender)) { $script:HybridNewUserWizardState.NotificationSender = [string]$resolved.NotificationSender }
    return $resolved
}

function Resolve-HybridNewUserWizardConfiguration {
    [CmdletBinding()]
    param([AllowNull()][object]$Configuration)

    $defaults = [ordered]@{
        NotificationRecipient = 'ITSupport@atlas-tech.com'
        NotificationSender = 'NEW-HIRE-INFO@atlas-tech.com'
        HomeOrganizations = @(
            [pscustomobject]@{ Number = 1; Name = 'Draco'; GroupName = 'Draco.Team'; DisplayGroupName = 'Draco Team' },
            [pscustomobject]@{ Number = 2; Name = 'Pavo'; GroupName = 'Pavo.Team'; DisplayGroupName = 'Pavo Team' },
            [pscustomobject]@{ Number = 3; Name = 'Corvus'; GroupName = 'Corvus.Team'; DisplayGroupName = 'Corvus Team' }
        )
        Locations = @(
            [pscustomobject]@{ Number = 1; Name = 'Rivers'; LocationGroup = 'Atlas-Charleston'; City = 'North Charleston'; StreetAddress = '5416-A Rivers Avenue - Suite 105'; State = 'SC'; PostalCode = '29406'; OuKey = 'HQ' },
            [pscustomobject]@{ Number = 2; Name = 'Remount'; LocationGroup = 'Atlas-Charleston'; City = 'North Charleston'; StreetAddress = '1101 Remount Rd, Suite 800'; State = 'SC'; PostalCode = '29406'; OuKey = 'HQ' },
            [pscustomobject]@{ Number = 3; Name = 'Virginia Beach'; LocationGroup = 'Atlas-VABeach'; City = 'Virginia Beach'; StreetAddress = '168 Business Park Drive, Suite 103'; State = 'VA'; PostalCode = '23462'; OuKey = '3' },
            [pscustomobject]@{ Number = 4; Name = 'San Diego'; LocationGroup = 'Atlas-SD'; City = 'San Diego'; StreetAddress = '4250 Pacific Highway, 105'; State = 'CA'; PostalCode = '92110'; OuKey = '4' },
            [pscustomobject]@{ Number = 5; Name = 'Alexandria'; LocationGroup = 'Atlas-DC'; City = 'Alexandria'; StreetAddress = '5911 Kingstowne Village Parkway Suite 310'; State = 'VA'; PostalCode = '22315'; OuKey = '5' },
            [pscustomobject]@{ Number = 6; Name = 'Lexington'; LocationGroup = 'Atlas-MD'; City = 'Lexington'; StreetAddress = 'Not Available'; State = 'MD'; PostalCode = 'Not Available'; OuKey = '6' }
        )
        Departments = @(
            [pscustomobject]@{ Number = 1; Name = 'Dept 00 - Accounting'; DisplayName = '00'; TargetOuByLocation = @{ HQ = 'OU=Users,OU=Accounting,OU=Dept-00,OU=HQ,OU=Atlas-tech,DC=atlas-tech,DC=com' } },
            [pscustomobject]@{ Number = 2; Name = 'Dept 00 - Information Technology'; DisplayName = '00'; TargetOuByLocation = @{ HQ = 'OU=Users,OU=IT,OU=Dept-00,OU=HQ,OU=Atlas-tech,DC=atlas-tech,DC=com' } },
            [pscustomobject]@{ Number = 3; Name = 'Dept 00 - Executive'; DisplayName = '00'; TargetOuByLocation = @{ HQ = 'OU=Users,OU=Exec,OU=Dept-00,OU=HQ,OU=Atlas-tech,DC=atlas-tech,DC=com' } },
            [pscustomobject]@{ Number = 4; Name = 'Dept 00 - Human Resources'; DisplayName = '00'; TargetOuByLocation = @{ HQ = 'OU=Users,OU=HR,OU=Dept-00,OU=HQ,OU=Atlas-tech,DC=atlas-tech,DC=com' } },
            [pscustomobject]@{ Number = 5; Name = 'Dept 01 - Contracts'; DisplayName = '01'; TargetOuByLocation = @{ HQ = 'OU=Users,OU=Contracts,OU=Dept-01,OU=HQ,OU=Atlas-tech,DC=atlas-tech,DC=com' } },
            [pscustomobject]@{ Number = 6; Name = 'Dept 01 - Operations'; DisplayName = '01'; TargetOuByLocation = @{ HQ = 'OU=Users,OU=Operations,OU=Dept-01,OU=HQ,OU=Atlas-tech,DC=atlas-tech,DC=com' } },
            [pscustomobject]@{ Number = 7; Name = 'Dept 02 - DC/PAX/Charleston Division'; DisplayName = '02'; TargetOuByLocation = @{ HQ = 'OU=Users,OU=Dept-02,OU=SC,OU=Atlas-tech,DC=atlas-tech,DC=com'; '5' = 'OU=Users,OU=Dept-02,OU=DC,OU=Atlas-tech,DC=atlas-tech,DC=com'; '6' = 'OU=Users,OU=Dept-02,OU=MD,OU=Atlas-tech,DC=atlas-tech,DC=com' } },
            [pscustomobject]@{ Number = 8; Name = 'Dept 03 - VABeach Division'; DisplayName = '03'; TargetOuByLocation = @{ '3' = 'OU=Users,OU=Dept-03,OU=VA,OU=Atlas-tech,DC=atlas-tech,DC=com' } },
            [pscustomobject]@{ Number = 9; Name = 'Dept 04 - San Diego Division'; DisplayName = '04'; TargetOuByLocation = @{ '4' = 'OU=Users,OU=Dept-04,OU=CA,OU=Atlas-tech,DC=atlas-tech,DC=com' } },
            [pscustomobject]@{ Number = 10; Name = 'Service Account'; DisplayName = 'Service Account'; TargetOu = 'OU=Service Accounts,OU=Atlas-tech,DC=atlas-tech,DC=com'; IsServiceAccount = $true }
        )
        Portfolios = @('', 'Corporate', 'Contracts', 'Operations', 'Information Technology', 'Human Resources')
        Groups = [pscustomobject]@{ CgUsersSc = 'SC_CGUsers'; CgUsersSd = 'SD_CGUsers'; CgUsersVa = 'VABeach_CGUsers'; CacGroup = 'CAC_Holders' }
        DefaultTargetOu = 'CN=Users,DC=atlas-tech,DC=com'
    }

    if ($null -ne $Configuration) {
        foreach ($key in @($defaults.Keys)) {
            if ($Configuration.PSObject.Properties.Name -contains $key -and $null -ne $Configuration.$key) { $defaults[$key] = $Configuration.$key }
        }
    }

    return [pscustomobject]$defaults
}

function Get-HybridNewUserSelectedNumber {
    [CmdletBinding()]
    param([AllowNull()][string]$Value)

    if ([string]::IsNullOrWhiteSpace($Value)) { return $null }
    $match = [regex]::Match($Value.Trim(), '^(?<Number>\d+)')
    if (-not $match.Success) { return $null }
    return [int]$match.Groups['Number'].Value
}

function Get-HybridNewUserMappings {
    [CmdletBinding()]
    param(
        [Nullable[int]]$OfficeNumber,
        [Nullable[int]]$DepartmentNumber,
        [Nullable[int]]$HomeOrganizationNumber
    )

    $configuration = if ($null -ne $script:HybridNewUserWizardState.Configuration) { $script:HybridNewUserWizardState.Configuration } else { Resolve-HybridNewUserWizardConfiguration -Configuration $null }
    $office = @($configuration.Locations | Where-Object { [int]$_.Number -eq [int]$OfficeNumber } | Select-Object -First 1)[0]
    $department = @($configuration.Departments | Where-Object { [int]$_.Number -eq [int]$DepartmentNumber } | Select-Object -First 1)[0]
    $homeOrganization = @($configuration.HomeOrganizations | Where-Object { [int]$_.Number -eq [int]$HomeOrganizationNumber } | Select-Object -First 1)[0]
    $groups = $configuration.Groups

    if ($null -eq $office) { $office = [pscustomobject]@{ LocationGroup = ''; City = 'Not Entered'; StreetAddress = 'Not Entered'; State = 'NA'; PostalCode = 'Not Available'; OuKey = '' } }
    if ($null -eq $department) { $department = [pscustomobject]@{ TargetOu = ''; TargetOuByLocation = $null; IsServiceAccount = $false } }
    if ($null -eq $homeOrganization) { $homeOrganization = [pscustomobject]@{ GroupName = 'NA'; DisplayGroupName = $null } }
    if ($null -eq $groups) { $groups = [pscustomobject]@{} }

    $targetOu = ''
    if ($department.PSObject.Properties.Name -contains 'TargetOu' -and -not [string]::IsNullOrWhiteSpace([string]$department.TargetOu)) {
        $targetOu = [string]$department.TargetOu
    }
    elseif ($department.PSObject.Properties.Name -contains 'TargetOuByLocation' -and $null -ne $department.TargetOuByLocation) {
        $locationKey = if ($office.PSObject.Properties.Name -contains 'OuKey' -and -not [string]::IsNullOrWhiteSpace([string]$office.OuKey)) { [string]$office.OuKey } else { [string]$OfficeNumber }
        $ouMap = $department.TargetOuByLocation
        if ($ouMap -is [System.Collections.IDictionary] -and $ouMap.Contains($locationKey)) { $targetOu = [string]$ouMap[$locationKey] }
        elseif ($ouMap.PSObject.Properties.Name -contains $locationKey) { $targetOu = [string]$ouMap.$locationKey }
    }
    if ([string]::IsNullOrWhiteSpace($targetOu)) { $targetOu = [string]$configuration.DefaultTargetOu }

    [pscustomobject]@{
        PSTypeName = 'Hybrid.NewUserWizard.Mappings'
        CgUsersSc = if ($groups.PSObject.Properties.Name -contains 'CgUsersSc') { [string]$groups.CgUsersSc } else { '' }
        CgUsersSd = if ($groups.PSObject.Properties.Name -contains 'CgUsersSd') { [string]$groups.CgUsersSd } else { '' }
        CgUsersVa = if ($groups.PSObject.Properties.Name -contains 'CgUsersVa') { [string]$groups.CgUsersVa } else { '' }
        CacGroup = if ($groups.PSObject.Properties.Name -contains 'CacGroup') { [string]$groups.CacGroup } else { '' }
        AtlasLocation = if ($office.PSObject.Properties.Name -contains 'LocationGroup') { [string]$office.LocationGroup } else { '' }
        HomeOrganizationGroup = $homeOrganization.GroupName
        HomeOrganizationDisplayGroup = if ($homeOrganization.PSObject.Properties.Name -contains 'DisplayGroupName') { $homeOrganization.DisplayGroupName } elseif ($homeOrganization.PSObject.Properties.Name -contains 'DisplayName') { $homeOrganization.DisplayName } else { $null }
        TargetOu = $targetOu
        City = $office.City
        StreetAddress = $office.StreetAddress
        State = $office.State
        PostalCode = $office.PostalCode
    }
}

function ConvertTo-HybridNewUserAccountName {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][string]$FirstName,
        [Parameter(Mandatory=$true)][string]$LastName,
        [AllowNull()][string]$MiddleInitial,
        [bool]$IncludeMiddleInitial
    )

    $first = ($FirstName.Trim() -replace '[^A-Za-z0-9]','')
    $last = ($LastName.Trim() -replace '[^A-Za-z0-9]','')
    $middle = if ([string]::IsNullOrWhiteSpace($MiddleInitial)) { '' } else { ($MiddleInitial.Trim().Substring(0,1) -replace '[^A-Za-z0-9]','') }
    if ([string]::IsNullOrWhiteSpace($first) -or [string]::IsNullOrWhiteSpace($last)) { return '' }
    $name = if ($IncludeMiddleInitial -and -not [string]::IsNullOrWhiteSpace($middle)) { $first.Substring(0,1) + $middle + $last } else { $first.Substring(0,1) + $last }
    return $name.ToLowerInvariant()
}

function ConvertTo-HybridNewUserPhoneValue {
    [CmdletBinding()]
    param([AllowNull()][string]$OfficePhone)

    if ([string]::IsNullOrWhiteSpace($OfficePhone)) { return 'NA' }
    $value = $OfficePhone.Trim()
    if ($value.Length -lt 12 -or $value.Length -gt 12) { return 'NA' }
    return $value
}

function ConvertTo-HybridNewUserDisplayDepartment {
    param([AllowNull()][string]$Department)
    if ([string]::IsNullOrWhiteSpace($Department)) { return '' }
    $value = $Department -replace '^\d+\.\s*', ''
    return ($value -replace '^Dept\s*(\d+)\s*-.*$', '$1')
}

function ConvertTo-HybridNewUserDisplayOffice {
    param([AllowNull()][string]$Location)
    if ([string]::IsNullOrWhiteSpace($Location)) { return '' }
    return ($Location -replace '^\d+\.\s*', '')
}

function New-HybridNewUserRequest {
    [CmdletBinding()]
    param(
        [AllowNull()][string]$FirstName,
        [AllowNull()][string]$LastName,
        [AllowNull()][string]$MiddleInitial,
        [bool]$IncludeMiddleInitial,
        [AllowNull()][string]$HomeOrganization,
        [AllowNull()][string]$Location,
        [AllowNull()][string]$Department,
        [AllowNull()][string]$JobTitle,
        [AllowNull()][string]$ManagerIdentity,
        [AllowNull()][string]$EmployeeId,
        [AllowNull()][string]$BadgeId,
        [AllowNull()][string]$OfficePhone,
        [AllowNull()][string]$MobilePhone,
        [AllowNull()][datetime]$StartDate,
        [bool]$CreateMailbox,
        [bool]$SendNewHireNotice,
        [bool]$CacRequired,
        [AllowNull()][string]$Portfolio,
        [AllowNull()][string]$NotificationRecipient,
        [AllowNull()][string]$NotificationSender,
        [bool]$NothingRequested,
        [bool]$TemporaryOfficeSpace,
        [bool]$PermanentOfficeSpace,
        [bool]$Desktop,
        [bool]$Laptop,
        [bool]$DockingStation,
        [bool]$MouseKeyboard,
        [bool]$Monitor,
        [bool]$DualMonitor,
        [bool]$DeskPhone,
        [bool]$CellPhone,
        [bool]$Speakers,
        [bool]$JamisClaimSetup
    )

    $officeNumber = Get-HybridNewUserSelectedNumber -Value $Location
    $departmentNumber = Get-HybridNewUserSelectedNumber -Value $Department
    $homeOrganizationNumber = Get-HybridNewUserSelectedNumber -Value $HomeOrganization
    $mappings = Get-HybridNewUserMappings -OfficeNumber $officeNumber -DepartmentNumber $departmentNumber -HomeOrganizationNumber $homeOrganizationNumber
    $sam = ConvertTo-HybridNewUserAccountName -FirstName $FirstName -LastName $LastName -MiddleInitial $MiddleInitial -IncludeMiddleInitial $IncludeMiddleInitial
    $displayName = ((@($FirstName, $LastName) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }) -join ' ').Trim()
    $upnSuffix = $script:HybridNewUserWizardState.DefaultUpnSuffix

    [pscustomobject]@{
        PSTypeName = 'Hybrid.NewUserWizard.Request'
        FirstName = if ($null -eq $FirstName) { '' } else { $FirstName.Trim() }
        LastName = if ($null -eq $LastName) { '' } else { $LastName.Trim() }
        MiddleInitial = if ($null -eq $MiddleInitial) { '' } else { $MiddleInitial.Trim() }
        IncludeMiddleInitial = $IncludeMiddleInitial
        DisplayName = $displayName
        SamAccountName = $sam
        UserPrincipalName = if ([string]::IsNullOrWhiteSpace($sam)) { '' } else { "$sam@$upnSuffix" }
        HomeOrganization = $HomeOrganization
        HomeOrganizationNumber = $homeOrganizationNumber
        Location = $Location
        OfficeNumber = $officeNumber
        Department = $Department
        DepartmentNumber = $departmentNumber
        JobTitle = if ($null -eq $JobTitle) { '' } else { $JobTitle.Trim() }
        ManagerIdentity = if ($null -eq $ManagerIdentity) { '' } else { $ManagerIdentity.Trim() }
        EmployeeId = if ($null -eq $EmployeeId) { '' } else { $EmployeeId.Trim() }
        BadgeId = if ($null -eq $BadgeId) { '' } else { $BadgeId.Trim() }
        OfficePhone = ConvertTo-HybridNewUserPhoneValue -OfficePhone $OfficePhone
        MobilePhone = if ($null -eq $MobilePhone) { '' } else { $MobilePhone.Trim() }
        StartDate = $StartDate
        CreateMailbox = $CreateMailbox
        SendNewHireNotice = $SendNewHireNotice
        CacRequired = $CacRequired
        Portfolio = if ($null -eq $Portfolio) { '' } else { $Portfolio.Trim() }
        NotificationRecipient = if ([string]::IsNullOrWhiteSpace($NotificationRecipient)) { $script:HybridNewUserWizardState.NotificationRecipient } else { $NotificationRecipient.Trim() }
        NotificationSender = if ([string]::IsNullOrWhiteSpace($NotificationSender)) { $script:HybridNewUserWizardState.NotificationSender } else { $NotificationSender.Trim() }
        EquipmentRequests = [pscustomobject]@{
            NothingRequested = $NothingRequested
            TemporaryOfficeSpace = $TemporaryOfficeSpace
            PermanentOfficeSpace = $PermanentOfficeSpace
            Desktop = $Desktop
            Laptop = $Laptop
            DockingStation = $DockingStation
            MouseKeyboard = $MouseKeyboard
            Monitor = $Monitor
            DualMonitor = $DualMonitor
            DeskPhone = $DeskPhone
            CellPhone = $CellPhone
            Speakers = $Speakers
        }
        JamisClaimSetup = $JamisClaimSetup
        Mappings = $mappings
    }
}

function Test-HybridNewUserRequest {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][object]$Request)

    $errors = New-Object System.Collections.Generic.List[string]
    $warnings = New-Object System.Collections.Generic.List[string]
    if ([string]::IsNullOrWhiteSpace([string]$Request.FirstName)) { [void]$errors.Add('First name is required.') }
    if ([string]::IsNullOrWhiteSpace([string]$Request.LastName)) { [void]$errors.Add('Last name is required.') }
    if ([string]::IsNullOrWhiteSpace([string]$Request.JobTitle)) { [void]$errors.Add('Job title is required.') }
    if ([string]::IsNullOrWhiteSpace([string]$Request.ManagerIdentity)) { [void]$errors.Add('Manager is required.') }
    if ($null -eq $Request.OfficeNumber) { [void]$errors.Add('Location selection is required.') }
    if ($null -eq $Request.DepartmentNumber) { [void]$errors.Add('Department selection is required.') }
    if ([string]::IsNullOrWhiteSpace([string]$Request.EmployeeId)) { [void]$errors.Add('Employee ID # is required.') }
    if ([string]::IsNullOrWhiteSpace([string]$Request.BadgeId)) { [void]$errors.Add('Encoded Badge Number # is required.') }
    if ([string]::IsNullOrWhiteSpace([string]$Request.SamAccountName)) { [void]$errors.Add('SamAccountName could not be generated.') }
    if ($Request.CreateMailbox -and $null -eq $script:HybridNewUserWizardState.ExchangeOnline) { [void]$warnings.Add('Exchange provider is unavailable; mailbox creation will fail safely if executed.') }
    if ($Request.JamisClaimSetup) { [void]$warnings.Add('JAMIS claim setup is a discrete post-create step and does not run during preview.') }

    [pscustomobject]@{
        PSTypeName = 'Hybrid.NewUserWizard.ValidationResult'
        IsValid = ($errors.Count -eq 0)
        Errors = @($errors)
        Warnings = @($warnings)
    }
}

function Get-HybridNewUserGroupPlan {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][object]$Request)

    $groups = New-Object System.Collections.Generic.List[string]
    if ($Request.DepartmentNumber -ne 10) {
        foreach ($group in @($Request.Mappings.CgUsersSc,$Request.Mappings.CgUsersSd,$Request.Mappings.CgUsersVa,$Request.Mappings.AtlasLocation,$Request.Mappings.HomeOrganizationDisplayGroup,$Request.Mappings.HomeOrganizationGroup)) {
            if (-not [string]::IsNullOrWhiteSpace([string]$group) -and [string]$group -ne 'NA') { [void]$groups.Add([string]$group) }
        }
        if ($Request.CacRequired) { [void]$groups.Add($Request.Mappings.CacGroup) }
        [void]$groups.Add('TEEntry')
    }
    return @($groups | Select-Object -Unique)
}

function Get-HybridNewUserAdCreateParameters {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][object]$Request,
        [AllowNull()][securestring]$AccountPassword = $null,
        [AllowNull()][string]$ManagerDistinguishedName = $null
    )

    if ($null -eq $AccountPassword) { $AccountPassword = ConvertTo-SecureString 'TempPasswordNotSet1!' -AsPlainText -Force }
    $params = @{
        Enabled = $true
        Name = $Request.DisplayName
        GivenName = $Request.FirstName
        Surname = $Request.LastName
        Initial = $Request.MiddleInitial
        DisplayName = $Request.DisplayName
        SamAccountName = $Request.SamAccountName
        UserPrincipalName = $Request.UserPrincipalName
        AccountPassword = $AccountPassword
        Path = $Request.Mappings.TargetOu
        Company = 'Atlas Technologies, Inc.'
        Manager = $ManagerDistinguishedName
        Description = $Request.JobTitle
        Office = (ConvertTo-HybridNewUserDisplayOffice -Location $Request.Location)
        OfficePhone = $Request.OfficePhone
        MobilePhone = $Request.MobilePhone
        Department = (ConvertTo-HybridNewUserDisplayDepartment -Department $Request.Department)
        EmployeeID = $Request.EmployeeId
        City = $Request.Mappings.City
        StreetAddress = $Request.Mappings.StreetAddress
        State = $Request.Mappings.State
        PostalCode = $Request.Mappings.PostalCode
        OtherAttributes = @{
            title = $Request.JobTitle
            badgeID = $Request.BadgeId
            ipPhone = $Request.OfficePhone
        }
    }

    foreach ($key in @($params.Keys)) {
        if ($null -eq $params[$key] -or ([string]$params[$key] -eq '')) { $params.Remove($key) }
    }
    return $params
}

function Get-HybridNewUserPreviewPlan {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][object]$Request)

    $groups = @(Get-HybridNewUserGroupPlan -Request $Request)
    $remoteRouting = "$($Request.SamAccountName)@$($script:HybridNewUserWizardState.RemoteRoutingDomain)"
    $actions = New-Object System.Collections.Generic.List[string]
    [void]$actions.Add("Create AD user '$($Request.DisplayName)' as $($Request.SamAccountName) in $($Request.Mappings.TargetOu).")
    [void]$actions.Add("Set UPN=$($Request.UserPrincipalName), title=$($Request.JobTitle), employeeID=$($Request.EmployeeId), badgeID=$($Request.BadgeId).")
    [void]$actions.Add("Set location: office=$(ConvertTo-HybridNewUserDisplayOffice -Location $Request.Location), city=$($Request.Mappings.City), state=$($Request.Mappings.State), postalCode=$($Request.Mappings.PostalCode).")
    if (-not [string]::IsNullOrWhiteSpace([string]$Request.ManagerIdentity)) { [void]$actions.Add("Resolve and set manager '$($Request.ManagerIdentity)'.") }
    if ($groups.Count -gt 0) { [void]$actions.Add('Add groups: ' + (@($groups) -join ', ') + '.') } else { [void]$actions.Add('No group assignments planned for service account/no mapping.') }
    if ($Request.CreateMailbox) { [void]$actions.Add("Enable remote mailbox with routing address $remoteRouting.") } else { [void]$actions.Add('Skip remote mailbox creation.') }
    if ($Request.SendNewHireNotice) { [void]$actions.Add("Prepare new-hire notification from $($Request.NotificationSender) to $($Request.NotificationRecipient).") }
    if ($Request.JamisClaimSetup) { [void]$actions.Add('Queue JAMIS claim setup as an optional post-create operator step.') }

    [pscustomobject]@{
        PSTypeName = 'Hybrid.NewUserWizard.PreviewPlan'
        DisplayName = $Request.DisplayName
        SamAccountName = $Request.SamAccountName
        UserPrincipalName = $Request.UserPrincipalName
        TargetOu = $Request.Mappings.TargetOu
        Groups = @($groups)
        RemoteRoutingAddress = $remoteRouting
        Actions = @($actions)
        AdCreateParameters = Get-HybridNewUserAdCreateParameters -Request $Request
    }
}

function Get-HybridNewUserManagerOptions {
    [CmdletBinding()]
    param()

    $managers = @(Invoke-HybridNewUserProviderOperation -Provider $script:HybridNewUserWizardState.ActiveDirectory -OperationNames @('GetUsersWithDirectReports','GetManagersWithDirectReports','GetManagers') -Arguments @())
    if ($managers.Count -eq 0) {
        return @([pscustomobject]@{ Name = 'No Managers Available'; SamAccountName = ''; Identity = ''; Enabled = $false })
    }
    return @($managers | ForEach-Object {
        [pscustomobject]@{
            Name = if ($_.PSObject.Properties.Name -contains 'Name') { [string]$_.Name } else { [string]$_.DisplayName }
            SamAccountName = if ($_.PSObject.Properties.Name -contains 'SamAccountName') { [string]$_.SamAccountName } else { [string]$_.Identity }
            Identity = if ($_.PSObject.Properties.Name -contains 'Identity') { [string]$_.Identity } else { [string]$_.SamAccountName }
            DistinguishedName = if ($_.PSObject.Properties.Name -contains 'DistinguishedName') { [string]$_.DistinguishedName } else { '' }
            Enabled = $true
        }
    })
}

function Invoke-HybridNewUserCreation {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][object]$Request,
        [AllowNull()][securestring]$AccountPassword = $null
    )

    $validation = Test-HybridNewUserRequest -Request $Request
    if (-not $validation.IsValid) { throw ('New user request is invalid: ' + (@($validation.Errors) -join '; ')) }

    $steps = New-Object System.Collections.Generic.List[object]
    $managerDn = ''
    if (-not [string]::IsNullOrWhiteSpace([string]$Request.ManagerIdentity)) {
        $managerDn = [string](Invoke-HybridNewUserProviderOperation -Provider $script:HybridNewUserWizardState.ActiveDirectory -OperationNames @('ResolveUserDistinguishedName','ResolveManagerDistinguishedName') -Arguments @($Request.ManagerIdentity))
        if ([string]::IsNullOrWhiteSpace($managerDn)) { throw "Could not resolve manager '$($Request.ManagerIdentity)' to a distinguishedName." }
    }

    $createParams = Get-HybridNewUserAdCreateParameters -Request $Request -AccountPassword $AccountPassword -ManagerDistinguishedName $managerDn
    $createResult = Invoke-HybridNewUserProviderOperation -Provider $script:HybridNewUserWizardState.ActiveDirectory -OperationNames @('CreateUser','NewUser','CreateADUser') -Arguments @($createParams)
    if ($null -eq $createResult) { throw 'Active Directory provider does not expose CreateUser/NewUser.' }
    $steps.Add([pscustomobject]@{ Step='Create AD User'; Status='Completed'; Message="Created $($Request.SamAccountName)."; Result=$createResult }) | Out-Null

    foreach ($group in @(Get-HybridNewUserGroupPlan -Request $Request)) {
        try {
            $groupResult = Invoke-HybridNewUserProviderOperation -Provider $script:HybridNewUserWizardState.ActiveDirectory -OperationNames @('AddUserToGroup','AddUserGroupMembership') -Arguments @($Request.SamAccountName, $group)
            $steps.Add([pscustomobject]@{ Step="Add group $group"; Status='Completed'; Message="Added to $group."; Result=$groupResult }) | Out-Null
        }
        catch {
            $steps.Add([pscustomobject]@{ Step="Add group $group"; Status='Failed'; Message=$_.Exception.Message; Result=$null }) | Out-Null
        }
    }

    if ($Request.CreateMailbox) {
        $remoteRouting = "$($Request.SamAccountName)@$($script:HybridNewUserWizardState.RemoteRoutingDomain)"
        $exchangeGuid = [guid]::NewGuid()
        try {
            Invoke-HybridNewUserProviderOperation -Provider $script:HybridNewUserWizardState.ActiveDirectory -OperationNames @('SetUserAttributes','SetDirectoryAttributes') -Arguments @($Request.SamAccountName, @{
                msExchRemoteRecipientType = 4
                targetAddress = $remoteRouting
                msExchMailboxGuid = $exchangeGuid.ToByteArray()
            }) | Out-Null
            $mailboxResult = Invoke-HybridNewUserProviderOperation -Provider $script:HybridNewUserWizardState.ExchangeOnline -OperationNames @('EnableRemoteMailbox','EnableUserRemoteMailbox') -Arguments @($Request.SamAccountName, $remoteRouting, $Request.SamAccountName, $exchangeGuid)
            if ($null -eq $mailboxResult) { throw 'Exchange provider does not expose EnableRemoteMailbox.' }
            $steps.Add([pscustomobject]@{ Step='Enable Remote Mailbox'; Status='Completed'; Message="Remote routing $remoteRouting."; Result=$mailboxResult }) | Out-Null
        }
        catch {
            $steps.Add([pscustomobject]@{ Step='Enable Remote Mailbox'; Status='Failed'; Message=$_.Exception.Message; Result=$null }) | Out-Null
        }
    }

    if ($Request.SendNewHireNotice) {
        $steps.Add([pscustomobject]@{ Step='New Hire Notification'; Status='Planned'; Message="Notification prepared for $($Request.NotificationRecipient)."; Result=$null }) | Out-Null
    }
    if ($Request.JamisClaimSetup) {
        $steps.Add([pscustomobject]@{ Step='JAMIS Claim Setup'; Status='Planned'; Message='Run as a discrete post-create operator step.'; Result=$null }) | Out-Null
    }

    $stepArray = @($steps.ToArray())
    $failedSteps = @($stepArray | Where-Object { $_.Status -eq 'Failed' })

    [pscustomobject]@{
        PSTypeName = 'Hybrid.NewUserWizard.ExecutionResult'
        SamAccountName = $Request.SamAccountName
        Success = ($failedSteps.Count -eq 0)
        Steps = @($stepArray)
    }
}

Export-ModuleMember -Function @(
    'Initialize-HybridNewUserWizardService',
    'Update-HybridNewUserWizardConfiguration',
    'Get-HybridNewUserSelectedNumber',
    'Get-HybridNewUserMappings',
    'ConvertTo-HybridNewUserAccountName',
    'ConvertTo-HybridNewUserPhoneValue',
    'New-HybridNewUserRequest',
    'Test-HybridNewUserRequest',
    'Get-HybridNewUserPreviewPlan',
    'Get-HybridNewUserManagerOptions',
    'Invoke-HybridNewUserCreation',
    'Get-HybridNewUserAdCreateParameters',
    'Get-HybridNewUserGroupPlan'
)
