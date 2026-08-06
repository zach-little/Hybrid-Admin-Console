using HAP.Contracts;
using HAP.Providers.Abstractions;
using HAP.Providers.Simulator;
using Xunit;

namespace HAP.Providers.Simulator.Tests;

public sealed class DirectorySimulatorProviderTests
{
    [Fact]
    public async Task GetHealthAsync_ReturnsConnectedNativeSimulatorHealth()
    {
        var provider = new DirectorySimulatorProvider();

        var result = await provider.GetHealthAsync(CorrelationId.From("sim-health"));

        Assert.True(result.Succeeded, string.Join("; ", result.Errors.Select(error => error.Message)));
        Assert.NotNull(result.Value);
        Assert.Equal("DirectorySimulator", result.Value.ProviderId);
        Assert.Equal("Simulation", result.Value.Mode);
        Assert.True(result.Value.Available);
        Assert.True(result.Value.Connected);
        Assert.Equal("Connected", result.Status);
    }

    [Fact]
    public async Task SearchUsersAsync_ReturnsSeededUserBySamAccountName()
    {
        var provider = new DirectorySimulatorProvider();

        var result = await provider.SearchUsersAsync("amorgan", CorrelationId.From("sim-user"));

        Assert.True(result.Succeeded, string.Join("; ", result.Errors.Select(error => error.Message)));
        var user = Assert.Single(result.Value!);
        Assert.Equal("Alex Morgan", user.DisplayName);
        Assert.Equal("amorgan", user.SamAccountName);
        Assert.Equal("amorgan@atlas-tech.com", user.UserPrincipalName);
        Assert.Equal("SIM-AMORGAN", user.EmployeeId);
        Assert.Equal("treed", user.ManagerSamAccountName);
        Assert.Empty(result.Warnings);
    }

    [Fact]
    public async Task SearchUsersAsync_ReturnsSeededUserByUpn()
    {
        var provider = new DirectorySimulatorProvider();

        var result = await provider.SearchUsersAsync("jlee@atlas-tech.com", CorrelationId.From("sim-upn"));

        Assert.True(result.Succeeded);
        var user = Assert.Single(result.Value!);
        Assert.Equal("Jordan Lee", user.DisplayName);
        Assert.Equal("jlee", user.SamAccountName);
    }

    [Fact]
    public async Task SearchUsersAsync_GeneratesFallbackUserWithWarning()
    {
        var provider = new DirectorySimulatorProvider();

        var result = await provider.SearchUsersAsync("sample.user", CorrelationId.From("sim-generated"));

        Assert.True(result.Succeeded);
        var user = Assert.Single(result.Value!);
        Assert.Equal("Sample User", user.DisplayName);
        Assert.Equal("suser", user.SamAccountName);
        Assert.Contains(result.Warnings, warning => warning.Code == "Simulator.UserGenerated");
    }

    [Fact]
    public async Task SearchUsersAsync_RejectsEmptyQuery()
    {
        var provider = new DirectorySimulatorProvider();

        var result = await provider.SearchUsersAsync("", CorrelationId.From("sim-invalid"));

        Assert.False(result.Succeeded);
        Assert.Contains(result.Errors, error => error.Code == "Simulator.UserLookup.QueryRequired");
    }

    [Fact]
    public async Task SearchUsersAsync_ReportsUnavailableProvider()
    {
        var provider = new DirectorySimulatorProvider(new DirectorySimulatorOptions { ProviderAvailable = false });

        var result = await provider.SearchUsersAsync("amorgan", CorrelationId.From("sim-unavailable"));

        Assert.False(result.Succeeded);
        Assert.Contains(result.Errors, error => error.Code == "Simulator.ProviderUnavailable");
    }

    [Fact]
    public async Task SearchUsersAsync_ReportsInvalidConfiguration()
    {
        var provider = new DirectorySimulatorProvider(new DirectorySimulatorOptions { ConfigurationValid = false });

        var result = await provider.SearchUsersAsync("amorgan", CorrelationId.From("sim-config"));

        Assert.False(result.Succeeded);
        Assert.Contains(result.Errors, error => error.Code == "Simulator.ConfigurationInvalid");
    }

    [Fact]
    public async Task SearchUsersAsync_ReportsCancellation()
    {
        var provider = new DirectorySimulatorProvider();
        using var cancellation = new CancellationTokenSource();
        await cancellation.CancelAsync();

        var result = await provider.SearchUsersAsync("amorgan", CorrelationId.From("sim-cancel"), cancellation.Token);

        Assert.False(result.Succeeded);
        Assert.Contains(result.Errors, error => error.Code == "Simulator.OperationCancelled");
    }

    [Fact]
    public async Task SearchUsersAsync_ReportsTimeout()
    {
        var provider = new DirectorySimulatorProvider(new DirectorySimulatorOptions
        {
            TimeoutMilliseconds = 1,
            SimulatedDelayMilliseconds = 500
        });

        var result = await provider.SearchUsersAsync("amorgan", CorrelationId.From("sim-timeout"));

        Assert.False(result.Succeeded);
        Assert.Equal("TimedOut", result.Status);
        Assert.Contains(result.Errors, error => error.Code == "Simulator.OperationTimeout");
    }

    [Fact]
    public async Task SearchUsersAsync_ReturnsMultipleMatchesInDeterministicOrderWithWarning()
    {
        var provider = new DirectorySimulatorProvider(
            null,
            new[]
            {
                CreateUser("zlee", "Zoe Lee"),
                CreateUser("alee", "Avery Lee")
            });

        var result = await provider.SearchUsersAsync("lee", CorrelationId.From("sim-multiple"));

        Assert.True(result.Succeeded);
        Assert.Equal(new[] { "alee", "zlee" }, result.Value!.Select(user => user.SamAccountName));
        Assert.Contains(result.Warnings, warning => warning.Code == "Simulator.UserLookup.MultipleMatches");
    }

    [Fact]
    public async Task SearchUsersAsync_ReturnsPartialFixtureWithWarning()
    {
        var provider = new DirectorySimulatorProvider(new DirectorySimulatorOptions { IncludePartialFixture = true });

        var result = await provider.SearchUsersAsync("partial.user", CorrelationId.From("sim-partial"));

        Assert.True(result.Succeeded);
        var user = Assert.Single(result.Value!);
        Assert.Equal("partialuser", user.SamAccountName);
        Assert.Contains(result.Warnings, warning => warning.Code == "Simulator.UserLookup.PartialUserData");
    }

    [Fact]
    public async Task ReadCapabilities_ReturnDeterministicRelatedData()
    {
        var provider = new DirectorySimulatorProvider();

        var groups = await provider.GetGroupsAsync("amorgan", CorrelationId.From("sim-groups"));
        var manager = await provider.GetManagerAsync("amorgan", CorrelationId.From("sim-manager"));
        var reports = await provider.GetDirectReportsAsync("treed", CorrelationId.From("sim-reports"));
        var devices = await provider.GetManagedDevicesAsync("amorgan", CorrelationId.From("sim-devices"));
        var graph = await provider.GetGraphProfileAsync("amorgan", CorrelationId.From("sim-graph"));
        var auth = await provider.GetAuthenticationPostureAsync("amorgan", CorrelationId.From("sim-auth"));
        var mailbox = await provider.GetMailboxAsync("amorgan", CorrelationId.From("sim-mailbox"));
        var distributionGroups = await provider.GetDistributionGroupsAsync("amorgan", CorrelationId.From("sim-dgs"));

        Assert.True(groups.Succeeded);
        Assert.Contains(groups.Value!, group => group.DisplayName == "GG-IT-Administrators");
        Assert.Equal("treed", manager.Value!.SamAccountName);
        Assert.Equal(new[] { "amorgan", "jlee" }, reports.Value!.Select(user => user.SamAccountName));
        Assert.Equal(new[] { "SIM-AMORGAN-LT01", "SIM-AMORGAN-PAW01" }, devices.Value!.Select(device => device.Name));
        Assert.Equal("Microsoft 365 E3", Assert.Single(graph.Value!.Licenses, license => license.SkuPartNumber == "ENTERPRISEPACK").FriendlyName);
        Assert.Contains("microsoftAuthenticatorPush", auth.Value!.AuthenticationMethods);
        Assert.Equal("amorgan@atlas-tech.com", mailbox.Value!.PrimarySmtpAddress);
        Assert.Contains(distributionGroups.Value!, group => group.DisplayName == "DL-InformationTechnology-Announcements");
    }

    [Fact]
    public async Task DirectoryAttributes_IncludeBadgeEmployeeAndExchangeSchemaAttributes()
    {
        var provider = new DirectorySimulatorProvider();

        var result = await provider.GetDirectoryAttributesAsync("amorgan", CorrelationId.From("sim-attrs"));

        Assert.True(result.Succeeded);
        Assert.Equal("DirectorySimulator.LatestAdExchangeBaseline", result.Value!.SchemaSource);
        Assert.Contains(result.Value.Attributes, attribute => attribute.Name == "BadgeID" && attribute.Values.Contains("SIM-AMORGAN"));
        Assert.Contains(result.Value.Attributes, attribute => attribute.Name == "EmployeeNumber" && attribute.Values.Contains("SIM-AMORGAN"));
        Assert.Contains(result.Value.Attributes, attribute => attribute.Name == "employeeNumber" && attribute.Values.Contains("SIM-AMORGAN"));
        Assert.Contains(result.Value.Attributes, attribute => attribute.Name == "proxyAddresses" && !attribute.IsSingleValued);
        Assert.Contains(result.Value.Attributes, attribute => attribute.Name == "msExchHideFromAddressLists");
    }

    [Fact]
    public async Task WriteCapabilities_UpdateAndResetDeterministicState()
    {
        var provider = new DirectorySimulatorProvider();

        var create = await provider.CreateUserAsync(
            new UserCreateRequest
            {
                GivenName = "Casey",
                Surname = "Stone",
                SamAccountName = "cstone",
                Department = "Finance",
                Title = "Analyst",
                ManagerSamAccountName = "treed",
                Office = "Charlotte"
            },
            CorrelationId.From("sim-create"));
        var addGroup = await provider.AddGroupMembershipAsync(
            new MembershipChangeRequest { Identity = "cstone", Group = "GG-Finance" },
            CorrelationId.From("sim-add-group"));
        var update = await provider.UpdateUserAttributesAsync(
            new UserUpdateRequest
            {
                Identity = "cstone",
                Attributes = new Dictionary<string, string> { ["Title"] = "Senior Analyst", ["EmployeeId"] = "SIM-CSTONE-2" }
            },
            CorrelationId.From("sim-update"));
        var forwarding = await provider.SetMailboxForwardingAsync(
            new MailboxForwardingRequest { Identity = "cstone", ForwardingSmtpAddress = "finance-archive@atlas-tech.com", DeliverToMailboxAndForward = true },
            CorrelationId.From("sim-forward"));

        var user = await provider.GetUserAsync("cstone", CorrelationId.From("sim-created-user"));
        var mailbox = await provider.GetMailboxAsync("cstone", CorrelationId.From("sim-created-mailbox"));
        var reset = await provider.ResetStateAsync(CorrelationId.From("sim-reset"));
        var afterReset = await provider.SearchUsersAsync("cstone", CorrelationId.From("sim-after-reset"));

        Assert.True(create.Value!.Changed);
        Assert.True(addGroup.Value!.Changed);
        Assert.True(update.Value!.Changed);
        Assert.True(forwarding.Value!.Changed);
        Assert.Equal("Senior Analyst", user.Value!.Title);
        Assert.Contains("GG-Finance", user.Value.Groups);
        Assert.Equal("finance-archive@atlas-tech.com", mailbox.Value!.ForwardingSmtpAddress);
        Assert.True(reset.Value!.Changed);
        Assert.Contains(afterReset.Warnings, warning => warning.Code == "Simulator.UserGenerated");
    }

    [Fact]
    public async Task ReportingAndConfigurationPreview_ReturnStableCounts()
    {
        var provider = new DirectorySimulatorProvider();

        var preview = await provider.GetConfigurationPreviewAsync(CorrelationId.From("sim-config-preview"));
        var reports = await provider.GetReportsAsync(CorrelationId.From("sim-reports"));

        Assert.True(preview.Succeeded);
        Assert.Equal("4", preview.Value!.Values["Users"]);
        Assert.Contains(reports.Value!, report => report.ReportId == "sim.devices" && report.RecordCount == 6);
    }

    [Fact]
    public void ProviderAssembly_DoesNotReferencePowerShell()
    {
        var assembly = typeof(DirectorySimulatorProvider).Assembly;
        var references = assembly.GetReferencedAssemblies().Select(reference => reference.Name).ToArray();

        Assert.DoesNotContain("System.Management.Automation", references);
    }

    private static SimulatorUserSummary CreateUser(string samAccountName, string displayName)
    {
        return new SimulatorUserSummary
        {
            SamAccountName = samAccountName,
            DisplayName = displayName,
            GivenName = displayName.Split(' ')[0],
            Surname = displayName.Split(' ')[1],
            UserPrincipalName = $"{samAccountName}@atlas-tech.com",
            Mail = $"{samAccountName}@atlas-tech.com",
            Enabled = true,
            Source = "DirectorySimulator"
        };
    }
}
