@{
    RootModule        = 'Core.Deployment.psm1'
    ModuleVersion     = '0.8.0.0'
    GUID              = '2777a3ab-3e77-4c8c-9d8f-0f8dc7b8c807'
    Author            = 'Hybrid Admin Platform'
    CompanyName       = 'Hybrid Admin Platform'
    Copyright         = '(c) Hybrid Admin Platform. All rights reserved.'
    Description       = 'Deployment layout and packaging support for Hybrid Admin Platform runtime deployments.'
    PowerShellVersion = '5.1'
    FunctionsToExport = @(
        'Get-HybridDeploymentLayout',
        'Get-HybridDeploymentRuntimeProfile',
        'Initialize-HybridDeployment',
        'Test-HybridDeploymentLayout',
        'New-HybridDeploymentPackage'
    )
    CmdletsToExport   = @()
    VariablesToExport = '*'
    AliasesToExport   = @()
}
