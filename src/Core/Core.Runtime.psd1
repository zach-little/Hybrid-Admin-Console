@{
    RootModule = 'Core.Runtime.psm1'
    ModuleVersion = '0.8.0'
    GUID = '9a9e4d25-9a2f-4df3-9c43-0a2a6f1d7c82'
    Author = 'Little Innovation Tech'
    CompanyName = 'Little Innovation Tech'
    Copyright = '(c) Little Innovation Tech. All rights reserved.'
    Description = 'Runtime bootstrap engine and startup diagnostics for profile-driven HILOP Console startup.'
    PowerShellVersion = '5.1'
    FunctionsToExport = @('Initialize-HybridRuntime','Get-HybridRuntime','Reset-HybridRuntime','Get-HybridRuntimeProviderRegistration','Get-HybridRuntimeProviderModeSummary','Get-HybridRuntimeDiagnostics','Test-HybridRuntimeDiagnostics')
    CmdletsToExport = @()
    VariablesToExport = '*'
    AliasesToExport = @()
}
