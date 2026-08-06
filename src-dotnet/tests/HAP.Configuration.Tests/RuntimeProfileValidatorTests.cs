using HAP.Configuration;
using HAP.Contracts;
using Xunit;

namespace HAP.Configuration.Tests;

public sealed class RuntimeProfileValidatorTests
{
    [Fact]
    public void Validate_AcceptsSimulationProfileWithDirectorySimulator()
    {
        var profile = new RuntimeProfile
        {
            ProfileName = "Simulation",
            Cloud = "Commercial",
            Mode = RuntimeProfileMode.Simulation,
            Providers = new Dictionary<string, RuntimeProviderSettings>(StringComparer.OrdinalIgnoreCase)
            {
                ["DirectorySimulator"] = new()
                {
                    Name = "DirectorySimulator",
                    Enabled = true,
                    Mode = ProviderMode.Simulation,
                    Required = true
                }
            }
        };

        var result = new RuntimeProfileValidator().Validate(profile);

        Assert.True(result.IsValid);
    }

    [Fact]
    public void Validate_RejectsSimulationProfileWithoutDirectorySimulator()
    {
        var profile = new RuntimeProfile
        {
            ProfileName = "Broken Simulation",
            Cloud = "Commercial",
            Mode = RuntimeProfileMode.Simulation,
            Providers = new Dictionary<string, RuntimeProviderSettings>(StringComparer.OrdinalIgnoreCase)
            {
                ["MicrosoftGraph"] = new()
                {
                    Name = "MicrosoftGraph",
                    Enabled = true,
                    Mode = ProviderMode.Simulation
                }
            }
        };

        var result = new RuntimeProfileValidator().Validate(profile);

        Assert.False(result.IsValid);
        Assert.Contains(result.Errors, error => error.Code == "RuntimeProfile.DirectorySimulatorRequired");
    }

    [Fact]
    public void Validate_RejectsEnabledProviderInDisabledMode()
    {
        var profile = new RuntimeProfile
        {
            ProfileName = "Live",
            Cloud = "GCCHigh",
            Mode = RuntimeProfileMode.Live,
            Providers = new Dictionary<string, RuntimeProviderSettings>(StringComparer.OrdinalIgnoreCase)
            {
                ["MicrosoftGraph"] = new()
                {
                    Name = "MicrosoftGraph",
                    Enabled = true,
                    Mode = ProviderMode.Disabled
                }
            }
        };

        var result = new RuntimeProfileValidator().Validate(profile);

        Assert.False(result.IsValid);
        Assert.Contains(result.Errors, error => error.Code == "RuntimeProfile.EnabledProviderCannotBeDisabled");
    }

    [Fact]
    public void Validate_AcceptsApprovedExtensionReference()
    {
        var registration = CreateApprovedMobilePassRegistration();
        var profile = CreateMobilePassProfile();

        var result = new RuntimeProfileValidator().Validate(profile, new[] { registration });

        Assert.True(result.IsValid);
    }

    [Fact]
    public void Validate_RejectsUnapprovedExtensionCapability()
    {
        var registration = CreateApprovedMobilePassRegistration() with
        {
            ApprovedCapabilities = new[] { ProviderCapabilityIds.ProviderHealth }
        };
        var profile = CreateMobilePassProfile();

        var result = new RuntimeProfileValidator().Validate(profile, new[] { registration });

        Assert.False(result.IsValid);
        Assert.Contains(result.Errors, error => error.Code == "RuntimeProfile.ExtensionCapabilityNotApproved");
    }

    private static ExtensionRegistration CreateApprovedMobilePassRegistration()
    {
        return new ExtensionRegistration
        {
            ProviderId = "contoso.mobilepass",
            ProviderInstanceId = "mobilepass-prod",
            DisplayName = "MobilePass",
            Publisher = "Contoso",
            Version = "1.2.0",
            HapApiVersion = "1.0",
            InstallationPath = @"C:\ProgramData\HAP\Providers\Contoso.MobilePass",
            EntryModule = "Contoso.MobilePass.psd1",
            Enabled = true,
            Approved = true,
            ApprovedCapabilities = new[]
            {
                ProviderCapabilityIds.ProviderHealth,
                ProviderCapabilityIds.UserLookup,
                ProviderCapabilityIds.CredentialEnrollment
            },
            FileHashes = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase)
            {
                ["hap-provider.json"] = "sha256:abc"
            }
        };
    }

    private static RuntimeProfile CreateMobilePassProfile()
    {
        return new RuntimeProfile
        {
            ProfileName = "Live",
            Cloud = "GCCHigh",
            Mode = RuntimeProfileMode.Live,
            Providers = new Dictionary<string, RuntimeProviderSettings>(StringComparer.OrdinalIgnoreCase)
            {
                ["MobilePass"] = new()
                {
                    Name = "MobilePass",
                    Enabled = true,
                    Mode = ProviderMode.Live,
                    ImplementationKind = ProviderImplementationKind.PowerShellExtension,
                    ExtensionInstanceId = "mobilepass-prod",
                    RequestedCapabilities = new[]
                    {
                        ProviderCapabilityIds.ProviderHealth,
                        ProviderCapabilityIds.CredentialEnrollment
                    }
                }
            }
        };
    }
}
