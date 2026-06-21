@{
    RootModule = 'Core.Runtime.psm1'
    ModuleVersion = '0.8.0'
    GUID = '9a9e4d25-9a2f-4df3-9c43-0a2a6f1d7c82'
    Author = 'Hybrid Administration Platform'
    CompanyName = 'Hybrid Administration Platform'
    Copyright = '(c) Hybrid Administration Platform. All rights reserved.'
    Description = 'Runtime bootstrap engine for profile-driven Hybrid Admin Console startup.'
    PowerShellVersion = '5.1'
    FunctionsToExport = @('Initialize-HybridRuntime','Get-HybridRuntime','Reset-HybridRuntime','Get-HybridRuntimeProviderRegistration','Get-HybridRuntimeProviderModeSummary')
    CmdletsToExport = @()
    VariablesToExport = '*'
    AliasesToExport = @()
}
