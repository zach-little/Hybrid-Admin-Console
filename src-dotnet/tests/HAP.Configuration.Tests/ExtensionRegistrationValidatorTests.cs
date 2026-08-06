using HAP.Configuration;
using HAP.Contracts;
using Xunit;

namespace HAP.Configuration.Tests;

public sealed class ExtensionRegistrationValidatorTests
{
    [Fact]
    public void Validate_RequiresApprovalForEnabledExtension()
    {
        var registration = ValidRegistration() with
        {
            Enabled = true,
            Approved = false
        };

        var result = new ExtensionRegistrationValidator().Validate(registration);

        Assert.False(result.IsValid);
        Assert.Contains(result.Errors, error => error.Code == "Extension.ApprovalRequired");
    }

    [Fact]
    public void Validate_RequiresFileHashForPowerShellExtension()
    {
        var registration = ValidRegistration() with
        {
            FileHashes = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase)
        };

        var result = new ExtensionRegistrationValidator().Validate(registration);

        Assert.False(result.IsValid);
        Assert.Contains(result.Errors, error => error.Code == "Extension.FileHashRequired");
    }

    [Fact]
    public void Validate_AcceptsApprovedPowerShellExtension()
    {
        var result = new ExtensionRegistrationValidator().Validate(ValidRegistration());

        Assert.True(result.IsValid);
    }

    private static ExtensionRegistration ValidRegistration()
    {
        return new ExtensionRegistration
        {
            ProviderId = "contoso.mobilepass",
            ProviderInstanceId = "mobilepass-prod",
            DisplayName = "MobilePass",
            Publisher = "Contoso",
            Version = "1.2.0",
            HapApiVersion = "1.0",
            ImplementationKind = ProviderImplementationKind.PowerShellExtension,
            InstallationPath = @"C:\ProgramData\HAP\Providers\Contoso.MobilePass",
            EntryModule = "Contoso.MobilePass.psd1",
            Enabled = true,
            Approved = true,
            ApprovedCapabilities = new[]
            {
                ProviderCapabilityIds.ProviderHealth,
                ProviderCapabilityIds.UserLookup
            },
            FileHashes = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase)
            {
                ["hap-provider.json"] = "sha256:abc"
            }
        };
    }
}
