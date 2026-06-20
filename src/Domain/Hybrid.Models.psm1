#region Module Information
# Name: Hybrid.Models
# Purpose: Common domain models used across services, providers, UI, and workflows.
# Dependencies: None
# Exports: New-HybridResult, New-HybridUser, New-HybridGroup, New-HybridMailbox, New-HybridDevice, New-HybridLicense
#endregion

Set-StrictMode -Version Latest

#region Private
function New-HybridModelObject {
    param([string]$TypeName,[hashtable]$Properties)
    $ordered = [ordered]@{ PSTypeName = $TypeName }
    foreach ($key in $Properties.Keys) { $ordered[$key] = $Properties[$key] }
    return [pscustomobject]$ordered
}
#endregion

#region Public
function New-HybridResult {
    <#.SYNOPSIS Creates a standard operation result.#>
    [CmdletBinding()] param([bool]$Success,[string]$Message='',[object]$Data=$null,[object]$ErrorRecord=$null)
    New-HybridModelObject -TypeName 'Hybrid.Result' -Properties @{ Success=$Success; Message=$Message; Data=$Data; Error=$ErrorRecord; TimestampUtc=[datetime]::UtcNow }
}
function New-HybridUser {
    <#.SYNOPSIS Creates a HybridUser model.#>
    [CmdletBinding()] param([string]$DisplayName,[string]$SamAccountName,[string]$UserPrincipalName,[string]$Mail,[string]$Department,[string]$Title,[object]$Raw=$null)
    New-HybridModelObject -TypeName 'Hybrid.User' -Properties @{ DisplayName=$DisplayName; SamAccountName=$SamAccountName; UserPrincipalName=$UserPrincipalName; Mail=$Mail; Department=$Department; Title=$Title; Sources=@(); Groups=@(); Mailbox=$null; Devices=@(); Licenses=@(); Raw=$Raw }
}
function New-HybridGroup {
    <#.SYNOPSIS Creates a HybridGroup model.#>
    [CmdletBinding()] param([string]$Name,[string]$Id,[string]$Source='Unknown',[object]$Raw=$null)
    New-HybridModelObject -TypeName 'Hybrid.Group' -Properties @{ Name=$Name; Id=$Id; Source=$Source; Raw=$Raw }
}
function New-HybridMailbox {
    <#.SYNOPSIS Creates a HybridMailbox model.#>
    [CmdletBinding()] param([string]$PrimarySmtpAddress,[string]$RecipientType,[bool]$Exists=$false,[object]$Raw=$null)
    New-HybridModelObject -TypeName 'Hybrid.Mailbox' -Properties @{ PrimarySmtpAddress=$PrimarySmtpAddress; RecipientType=$RecipientType; Exists=$Exists; Raw=$Raw }
}
function New-HybridDevice {
    <#.SYNOPSIS Creates a HybridDevice model.#>
    [CmdletBinding()] param([string]$Name,[string]$Id,[string]$Platform,[string]$ComplianceState,[object]$Raw=$null)
    New-HybridModelObject -TypeName 'Hybrid.Device' -Properties @{ Name=$Name; Id=$Id; Platform=$Platform; ComplianceState=$ComplianceState; Raw=$Raw }
}
function New-HybridLicense {
    <#.SYNOPSIS Creates a HybridLicense model.#>
    [CmdletBinding()] param([string]$SkuPartNumber,[string]$DisplayName,[string]$AssignmentSource='Unknown',[object]$Raw=$null)
    New-HybridModelObject -TypeName 'Hybrid.License' -Properties @{ SkuPartNumber=$SkuPartNumber; DisplayName=$DisplayName; AssignmentSource=$AssignmentSource; Raw=$Raw }
}
#endregion

#region Initialization
Export-ModuleMember -Function New-HybridResult, New-HybridUser, New-HybridGroup, New-HybridMailbox, New-HybridDevice, New-HybridLicense
#endregion
