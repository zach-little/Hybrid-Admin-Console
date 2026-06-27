# Unblock all repository files
Get-ChildItem -Path . -Recurse -File | Unblock-File

# Unload any loaded HAP modules
@(
'Application.NewUserWizardService',
'Application.GraphProfileService',
'Application.UserAdministrationService',
'Application.HybridUserService',
'Core.Runtime',
'Core.Authentication.Manager',
'Core.Provider.MicrosoftGraph',
'Core.Provider.ExchangeOnline',
'Infrastructure.ActiveDirectory',
'Infrastructure.DirectorySimulator',
'Core.ProviderBase',
'ActiveDirectory',
'Hybrid.Models'
) | ForEach-Object {
    Remove-Module $_ -Force -ErrorAction SilentlyContinue
}

# Execute every test script
Get-ChildItem .\tests -Filter *.ps1 |
    Sort-Object Name |
    ForEach-Object {

        Write-Host ""
        Write-Host "===================================================" -ForegroundColor DarkGray
        Write-Host "Running $($_.Name)" -ForegroundColor Cyan
        Write-Host "===================================================" -ForegroundColor DarkGray

        & powershell.exe `
            -NoProfile `
            -ExecutionPolicy Bypass `
            -File $_.FullName

        if ($LASTEXITCODE -ne 0) {
            Write-Host "FAILED: $($_.Name)" -ForegroundColor Red
        }
        else {
            Write-Host "PASSED: $($_.Name)" -ForegroundColor Green
        }
    }

Write-Host ""
Write-Host "All test scripts completed." -ForegroundColor Yellow