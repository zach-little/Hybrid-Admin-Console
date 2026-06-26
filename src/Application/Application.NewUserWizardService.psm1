Set-StrictMode -Version Latest

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

    $officeMap = @{
        1 = @{ AtlasLocation = 'Atlas-Charleston'; City = 'North Charleston'; StreetAddress = '5416-A Rivers Avenue - Suite 105'; State = 'SC'; PostalCode = '29406' }
        2 = @{ AtlasLocation = 'Atlas-Charleston'; City = 'North Charleston'; StreetAddress = '1101 Remount Rd, Suite 800'; State = 'SC'; PostalCode = '29406' }
        3 = @{ AtlasLocation = 'Atlas-VABeach'; City = 'Virginia Beach'; StreetAddress = '168 Business Park Drive, Suite 103'; State = 'VA'; PostalCode = '23462' }
        4 = @{ AtlasLocation = 'Atlas-SD'; City = 'San Diego'; StreetAddress = '4250 Pacific Highway, 105'; State = 'CA'; PostalCode = '92110' }
        5 = @{ AtlasLocation = 'Atlas-DC'; City = 'Alexandria'; StreetAddress = '5911 Kingstowne Village Parkway Suite 310'; State = 'VA'; PostalCode = '22315' }
        6 = @{ AtlasLocation = 'Atlas-MD'; City = 'Lexington'; StreetAddress = 'Not Available'; State = 'MD'; PostalCode = 'Not Available' }
    }

    $homeOrganizationMap = @{
        1 = @{ GroupName = 'Draco.Team'; DisplayName = 'Draco Team' }
        2 = @{ GroupName = 'Pavo.Team'; DisplayName = 'Pavo Team' }
        3 = @{ GroupName = 'Corvus.Team'; DisplayName = 'Corvus Team' }
    }

    $ouMap = @{
        'HQ:1' = 'OU=Users,OU=Accounting,OU=Dept-00,OU=HQ,OU=Atlas-tech,DC=atlas-tech,DC=com'
        'HQ:2' = 'OU=Users,OU=IT,OU=Dept-00,OU=HQ,OU=Atlas-tech,DC=atlas-tech,DC=com'
        'HQ:3' = 'OU=Users,OU=Exec,OU=Dept-00,OU=HQ,OU=Atlas-tech,DC=atlas-tech,DC=com'
        'HQ:4' = 'OU=Users,OU=HR,OU=Dept-00,OU=HQ,OU=Atlas-tech,DC=atlas-tech,DC=com'
        'HQ:5' = 'OU=Users,OU=Contracts,OU=Dept-01,OU=HQ,OU=Atlas-tech,DC=atlas-tech,DC=com'
        'HQ:6' = 'OU=Users,OU=Operations,OU=Dept-01,OU=HQ,OU=Atlas-tech,DC=atlas-tech,DC=com'
        'HQ:7' = 'OU=Users,OU=Dept-02,OU=SC,OU=Atlas-tech,DC=atlas-tech,DC=com'
        '3:8'  = 'OU=Users,OU=Dept-03,OU=VA,OU=Atlas-tech,DC=atlas-tech,DC=com'
        '4:9'  = 'OU=Users,OU=Dept-04,OU=CA,OU=Atlas-tech,DC=atlas-tech,DC=com'
        '5:7'  = 'OU=Users,OU=Dept-02,OU=DC,OU=Atlas-tech,DC=atlas-tech,DC=com'
        '6:7'  = 'OU=Users,OU=Dept-02,OU=MD,OU=Atlas-tech,DC=atlas-tech,DC=com'
    }

    $office = if ($officeMap.ContainsKey($OfficeNumber)) { $officeMap[$OfficeNumber] } else { @{ AtlasLocation = 'Atlas-Charleston'; City = 'Not Entered'; StreetAddress = 'Not Entered'; State = 'NA'; PostalCode = 'Not Available' } }
    $homeOrganization = if ($homeOrganizationMap.ContainsKey($HomeOrganizationNumber)) { $homeOrganizationMap[$HomeOrganizationNumber] } else { @{ GroupName = 'NA'; DisplayName = $null } }

    if ($DepartmentNumber -eq 10) {
        $targetOu = 'OU=Service Accounts,OU=Atlas-tech,DC=atlas-tech,DC=com'
    }
    else {
        $ouKey = if ($OfficeNumber -in @(1,2)) { "HQ:$DepartmentNumber" } else { "${OfficeNumber}:$DepartmentNumber" }
        $targetOu = if ($ouMap.ContainsKey($ouKey)) { $ouMap[$ouKey] } else { 'CN=Users,DC=atlas-tech,DC=com' }
    }

    [pscustomobject]@{
        PSTypeName = 'Hybrid.NewUserWizard.Mappings'
        CgUsersSc = 'SC_CGUsers'
        CgUsersSd = 'SD_CGUsers'
        CgUsersVa = 'VABeach_CGUsers'
        CacGroup = 'CAC_Holders'
        AtlasLocation = $office.AtlasLocation
        HomeOrganizationGroup = $homeOrganization.GroupName
        HomeOrganizationDisplayGroup = $homeOrganization.DisplayName
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
        [bool]$CacRequired
    )

    $officeNumber = Get-HybridNewUserSelectedNumber -Value $Location
    $departmentNumber = Get-HybridNewUserSelectedNumber -Value $Department
    $homeOrganizationNumber = Get-HybridNewUserSelectedNumber -Value $HomeOrganization
    $mappings = Get-HybridNewUserMappings -OfficeNumber $officeNumber -DepartmentNumber $departmentNumber -HomeOrganizationNumber $homeOrganizationNumber
    $sam = ConvertTo-HybridNewUserAccountName -FirstName $FirstName -LastName $LastName -MiddleInitial $MiddleInitial -IncludeMiddleInitial $IncludeMiddleInitial
    $displayName = ((@($FirstName, $LastName) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }) -join ' ').Trim()

    [pscustomobject]@{
        PSTypeName = 'Hybrid.NewUserWizard.Request'
        FirstName = if ($null -eq $FirstName) { '' } else { $FirstName.Trim() }
        LastName = if ($null -eq $LastName) { '' } else { $LastName.Trim() }
        MiddleInitial = if ($null -eq $MiddleInitial) { '' } else { $MiddleInitial.Trim() }
        IncludeMiddleInitial = $IncludeMiddleInitial
        DisplayName = $displayName
        SamAccountName = $sam
        UserPrincipalName = if ([string]::IsNullOrWhiteSpace($sam)) { '' } else { "$sam@atlas-tech.com" }
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
        OfficePhone = if ($null -eq $OfficePhone) { '' } else { $OfficePhone.Trim() }
        MobilePhone = if ($null -eq $MobilePhone) { '' } else { $MobilePhone.Trim() }
        StartDate = $StartDate
        CreateMailbox = $CreateMailbox
        SendNewHireNotice = $SendNewHireNotice
        CacRequired = $CacRequired
        Mappings = $mappings
    }
}

function Test-HybridNewUserRequest {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][object]$Request)

    $errors = New-Object System.Collections.Generic.List[string]
    if ([string]::IsNullOrWhiteSpace([string]$Request.FirstName)) { [void]$errors.Add('First name is required.') }
    if ([string]::IsNullOrWhiteSpace([string]$Request.LastName)) { [void]$errors.Add('Last name is required.') }
    if ([string]::IsNullOrWhiteSpace([string]$Request.JobTitle)) { [void]$errors.Add('Job title is required.') }
    if ($null -eq $Request.OfficeNumber) { [void]$errors.Add('Location selection is required.') }
    if ($null -eq $Request.DepartmentNumber) { [void]$errors.Add('Department selection is required.') }
    if ($null -eq $Request.HomeOrganizationNumber) { [void]$errors.Add('Home organization selection is required.') }
    if ([string]::IsNullOrWhiteSpace([string]$Request.SamAccountName)) { [void]$errors.Add('SamAccountName could not be generated.') }
    if (-not [string]::IsNullOrWhiteSpace([string]$Request.OfficePhone) -and ([string]$Request.OfficePhone).Length -notin @(10,12)) { [void]$errors.Add('Office phone should be blank, 10 digits, or a 12-character formatted number.') }

    [pscustomobject]@{
        PSTypeName = 'Hybrid.NewUserWizard.ValidationResult'
        IsValid = ($errors.Count -eq 0)
        Errors = @($errors)
    }
}

function Get-HybridNewUserPreviewPlan {
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

    $actions = New-Object System.Collections.Generic.List[string]
    [void]$actions.Add("Create AD user '$($Request.DisplayName)' as $($Request.SamAccountName) in $($Request.Mappings.TargetOu).")
    [void]$actions.Add("Set identity attributes: UPN=$($Request.UserPrincipalName), title=$($Request.JobTitle), employeeID=$($Request.EmployeeId), badgeID=$($Request.BadgeId).")
    [void]$actions.Add("Set location attributes: office=$($Request.Location), city=$($Request.Mappings.City), state=$($Request.Mappings.State), postalCode=$($Request.Mappings.PostalCode).")
    if (-not [string]::IsNullOrWhiteSpace([string]$Request.ManagerIdentity)) { [void]$actions.Add("Resolve and set manager '$($Request.ManagerIdentity)'.") }
    if ($groups.Count -gt 0) { [void]$actions.Add('Add security groups: ' + (@($groups) -join ', ') + '.') } else { [void]$actions.Add('No security groups planned because this appears to be a service account or no group mapping matched.') }
    if ($Request.CreateMailbox) { [void]$actions.Add("Create remote mailbox with routing address $($Request.SamAccountName)@atlastechcloud.mail.onmicrosoft.com.") } else { [void]$actions.Add('Skip remote mailbox creation.') }
    if ($Request.SendNewHireNotice) { [void]$actions.Add('Prepare new-hire onboarding notification for the execution phase.') } else { [void]$actions.Add('Skip new-hire onboarding notification.') }
    [void]$actions.Add('Execution is intentionally disabled in v0.9C; this is a validation and preview milestone.')

    [pscustomobject]@{
        PSTypeName = 'Hybrid.NewUserWizard.PreviewPlan'
        DisplayName = $Request.DisplayName
        SamAccountName = $Request.SamAccountName
        UserPrincipalName = $Request.UserPrincipalName
        TargetOu = $Request.Mappings.TargetOu
        Groups = @($groups)
        Actions = @($actions)
    }
}

Export-ModuleMember -Function @(
    'Get-HybridNewUserSelectedNumber',
    'Get-HybridNewUserMappings',
    'ConvertTo-HybridNewUserAccountName',
    'New-HybridNewUserRequest',
    'Test-HybridNewUserRequest',
    'Get-HybridNewUserPreviewPlan'
)
