using HILOP.Application.Extensions;
using HILOP.Extensions.Abstractions;
using Xunit;

namespace HILOP.IntegrationTests;

public sealed class NoPowerShellNormalModeTests
{
    [Fact]
    public void CreatePlan_NoEnabledPowerShellExtensions_DoesNotLaunchPowerShell()
    {
        var policy = new PowerShellExtensionLaunchPolicy();

        var plan = policy.CreatePlan(Array.Empty<ExtensionLaunchCandidate>());

        Assert.False(plan.ShouldLaunchPowerShell);
        Assert.Empty(plan.ProviderIdsRequiringHost);
    }

    [Fact]
    public void CreatePlan_DisabledPowerShellExtension_DoesNotLaunchPowerShell()
    {
        var policy = new PowerShellExtensionLaunchPolicy();

        var plan = policy.CreatePlan(new[]
        {
            new ExtensionLaunchCandidate
            {
                ProviderId = "contoso.identity",
                Implementation = HapProviderImplementationKind.PowerShell,
                Enabled = false
            }
        });

        Assert.False(plan.ShouldLaunchPowerShell);
        Assert.Empty(plan.ProviderIdsRequiringHost);
    }

    [Fact]
    public void CreatePlan_EnabledPowerShellExtension_IsExplicitLaunchBoundary()
    {
        var policy = new PowerShellExtensionLaunchPolicy();

        var plan = policy.CreatePlan(new[]
        {
            new ExtensionLaunchCandidate
            {
                ProviderId = "contoso.identity",
                Implementation = HapProviderImplementationKind.PowerShell,
                Enabled = true
            }
        });

        Assert.True(plan.ShouldLaunchPowerShell);
        Assert.Equal(new[] { "contoso.identity" }, plan.ProviderIdsRequiringHost);
    }
}
