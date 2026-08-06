using HAP.Contracts;
using HAP.Providers.ActiveDirectory;
using HAP.Providers.ExchangeOnline;
using HAP.Providers.Graph;
using Xunit;

namespace HAP.IntegrationTests;

public sealed class NativeProviderFoundationTests
{
    [Fact]
    public async Task GraphFoundation_ProvidesHealthReadsAndExplicitUnsupportedWrites()
    {
        var provider = new MicrosoftGraphProvider();

        var health = await provider.GetHealthAsync(CorrelationId.From("graph-health"));
        var profile = await provider.GetGraphProfileAsync("zlittleadm", CorrelationId.From("graph-profile"));
        var devices = await provider.GetManagedDevicesAsync("amorgan", CorrelationId.From("graph-devices"));
        var write = await provider.AddGroupMembershipAsync(new() { Identity = "amorgan", Group = "group1" }, CorrelationId.From("graph-write"));

        Assert.True(health.Succeeded);
        Assert.Equal("Connected", health.Status);
        Assert.True(profile.Succeeded);
        Assert.Contains("User Administrator", profile.Value!.PimRoles);
        Assert.True(devices.Succeeded);
        Assert.NotEmpty(devices.Value!);
        Assert.False(write.Succeeded);
        Assert.Equal("Unsupported", write.Status);
    }

    [Fact]
    public async Task ActiveDirectoryFoundation_DistinguishesConnectionFailuresFromLookupResults()
    {
        var provider = new ActiveDirectoryProvider();
        var unavailable = new ActiveDirectoryProvider(new ActiveDirectoryProviderOptions { ConnectionAvailable = false });

        var groups = await provider.GetGroupsAsync("amorgan", CorrelationId.From("ad-groups"));
        var missing = await provider.GetUserAsync("missing", CorrelationId.From("ad-missing"));
        var failed = await unavailable.GetHealthAsync(CorrelationId.From("ad-failed"));

        Assert.True(groups.Succeeded);
        Assert.Contains(groups.Value!, group => group.DisplayName == "GG-IT-Administrators");
        Assert.True(missing.Succeeded);
        Assert.Null(missing.Value);
        Assert.False(failed.Succeeded);
        Assert.Contains(failed.Errors, error => error.Code == "AD.ConnectionFailed");
    }

    [Fact]
    public async Task ExchangeOnlineFoundation_AllowsOnlyApprovedLimitedReads()
    {
        var provider = new ExchangeOnlineProvider();

        var health = await provider.GetHealthAsync(CorrelationId.From("exo-health"));
        var mailbox = await provider.GetMailboxAsync("amorgan@example.com", CorrelationId.From("exo-mailbox"));
        var delegation = await provider.GetMailboxDelegationsAsync("amorgan@example.com", CorrelationId.From("exo-delegation"));

        Assert.True(health.Succeeded);
        Assert.Equal("Limited", health.Status);
        Assert.True(mailbox.Succeeded);
        Assert.Equal("amorgan@example.com", mailbox.Value!.PrimarySmtpAddress);
        Assert.False(delegation.Succeeded);
        Assert.Equal("Unsupported", delegation.Status);
        Assert.Contains(delegation.Errors, error => error.Code == "ExchangeOnline.MailboxDelegation.UnsupportedWithoutPowerShell");
    }
}
