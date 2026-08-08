using HAP.Application.NewUser;
using HAP.Contracts;
using HAP.Providers.Abstractions;
using Xunit;

namespace HAP.Application.Tests;

public sealed class NativeNewUserWizardTests
{
    [Fact]
    public async Task Preflight_BlocksDuplicateSamAccountName()
    {
        var preflight = new NativeNewUserPreflightService(new FakeLookupProvider(new[] { User("cstone") }));

        var result = await preflight.BuildPlanAsync(Request("cstone"), CorrelationId.From("new-user-duplicate"));

        Assert.True(result.Succeeded);
        Assert.Equal("Blocked", result.Status);
        Assert.False(result.Value!.CanExecute);
        Assert.Contains(result.Value.Steps, step => step.StepId == NewUserPlanStepIds.CheckUniqueness && step.IsBlocking);
    }

    [Fact]
    public async Task Preflight_CreatesReadyDeterministicPlan()
    {
        var preflight = new NativeNewUserPreflightService(new FakeLookupProvider(Array.Empty<SimulatorUserSummary>()));

        var result = await preflight.BuildPlanAsync(Request("cstone"), CorrelationId.From("new-user-ready"));

        Assert.True(result.Succeeded);
        Assert.Equal("Ready", result.Status);
        Assert.True(result.Value!.CanExecute);
        Assert.Equal("new-user:cstone", result.Value.PlanId);
        Assert.Equal(new[] { "validate-runtime", "check-uniqueness", "create-directory-user", "set-manager" }, result.Value.Steps.Select(step => step.StepId));
    }

    [Fact]
    public async Task Execution_RejectsBlockedPlanWithoutProviderCall()
    {
        var executor = new NativeNewUserExecutionService(new FakeWriter());
        var plan = new NewUserExecutionPlan
        {
            PlanId = "blocked",
            Request = Request("cstone"),
            Steps = new[] { new NewUserPlanStep { StepId = NewUserPlanStepIds.CheckUniqueness, ProviderId = "ActiveDirectory", Operation = "CheckUniqueness", IsBlocking = true } }
        };

        var result = await executor.ExecuteAsync(plan, CorrelationId.From("new-user-blocked"));

        Assert.False(result.Succeeded);
        Assert.Equal("Blocked", result.Status);
    }

    [Fact]
    public async Task Execution_RunsPlanStepsInOrder()
    {
        var writer = new FakeWriter();
        var preflight = new NativeNewUserPreflightService(new FakeLookupProvider(Array.Empty<SimulatorUserSummary>()));
        var plan = (await preflight.BuildPlanAsync(Request("cstone"), CorrelationId.From("new-user-plan"))).Value!;
        var executor = new NativeNewUserExecutionService(writer);

        var result = await executor.ExecuteAsync(plan, CorrelationId.From("new-user-exec"));

        Assert.True(result.Succeeded);
        Assert.Equal("Completed", result.Status);
        Assert.Equal(new[] { "CheckUniqueness", "CreateUser", "SetManager" }, result.Value!.Steps.Select(step => step.Operation));
        Assert.Equal(new[] { "CreateUser", "SetManager" }, writer.Operations);
    }

    [Fact]
    public async Task Execution_RoutesMailboxProvisioningToExchangeWriter()
    {
        var directoryWriter = new FakeWriter();
        var exchangeWriter = new FakeWriter();
        var configuration = NewUserOnboardingConfiguration.FromProfileJson(
            """
            {
              "Defaults": {
                "UpnSuffix": "littleinnovation.tech",
                "RemoteRoutingDomain": "littleinnovation.mail.onmicrosoft.us"
              }
            }
            """);
        var preflight = new NativeNewUserPreflightService(new FakeLookupProvider(Array.Empty<SimulatorUserSummary>()), configuration);
        var plan = (await preflight.BuildPlanAsync(Request("cstone") with { CreateMailbox = true }, CorrelationId.From("new-user-mailbox-plan"))).Value!;
        var executor = new NativeNewUserExecutionService(directoryWriter, exchangeWriter);

        var result = await executor.ExecuteAsync(plan, CorrelationId.From("new-user-mailbox-exec"));

        Assert.True(result.Succeeded);
        Assert.Contains("CreateUser", directoryWriter.Operations);
        Assert.DoesNotContain("EnableRemoteMailbox", directoryWriter.Operations);
        Assert.Contains("EnableRemoteMailbox", exchangeWriter.Operations);
        Assert.Equal("cstone@littleinnovation.mail.onmicrosoft.us", exchangeWriter.LastMailboxProvisioning?.RemoteRoutingAddress);
    }

    [Fact]
    public async Task Preflight_ResolvesOnboardingRulesFromJsonConfiguration()
    {
        var configuration = NewUserOnboardingConfiguration.FromProfileJson(
            """
            {
              "Defaults": {
                "UpnSuffix": "littleinnovation.tech",
                "Company": "Little Innovation",
                "RemoteRoutingDomain": "littleinnovation.mail.onmicrosoft.us",
                "DefaultTargetOu": "OU=Users,DC=littleinnovation,DC=tech"
              },
              "Departments": [
                {
                  "Key": "IT",
                  "Display": "Information Technology",
                  "DefaultGroups": [ "GG-IT-Users" ],
                  "TargetOuByLocation": {
                    "HQ": "OU=IT,OU=HQ,DC=littleinnovation,DC=tech"
                  }
                }
              ],
              "Locations": [
                {
                  "Key": "HQ",
                  "Display": "Headquarters",
                  "City": "Virginia Beach",
                  "State": "VA",
                  "PostalCode": "23452",
                  "GroupName": "GG-HQ-Users"
                }
              ],
              "Groups": {
                "Always": [ "GG-All-Employees" ],
                "CacGroup": "GG-CAC-Holders"
              },
              "AttributeMappings": [
                { "Name": "extensionAttribute1", "Value": "{{DepartmentKey}}/{{LocationKey}}" }
              ]
            }
            """);
        var preflight = new NativeNewUserPreflightService(new FakeLookupProvider(Array.Empty<SimulatorUserSummary>()), configuration);
        var request = Request("cstone") with
        {
            Department = "Information Technology",
            Office = "Headquarters",
            EmployeeId = "12345",
            BadgeId = "B-12345",
            RequiresCac = true,
            CreateMailbox = true
        };

        var result = await preflight.BuildPlanAsync(request, CorrelationId.From("new-user-configured"));

        Assert.True(result.Succeeded);
        Assert.True(result.Value!.CanExecute);
        Assert.Equal("OU=IT,OU=HQ,DC=littleinnovation,DC=tech", result.Value.ResolvedOnboarding.TargetOu);
        Assert.Equal("cstone@littleinnovation.tech", result.Value.ResolvedOnboarding.UserPrincipalName);
        Assert.Equal("cstone@littleinnovation.mail.onmicrosoft.us", result.Value.ResolvedOnboarding.RemoteRoutingAddress);
        Assert.Contains("GG-All-Employees", result.Value.ResolvedOnboarding.Groups);
        Assert.Contains("GG-HQ-Users", result.Value.ResolvedOnboarding.Groups);
        Assert.Contains("GG-IT-Users", result.Value.ResolvedOnboarding.Groups);
        Assert.Contains("GG-CAC-Holders", result.Value.ResolvedOnboarding.Groups);
        Assert.Equal("B-12345", result.Value.ResolvedOnboarding.AdditionalAttributes["badgeID"]);
        Assert.Equal("IT/HQ", result.Value.ResolvedOnboarding.AdditionalAttributes["extensionAttribute1"]);
        Assert.Contains(result.Value.Steps, step => step.StepId == NewUserPlanStepIds.EnableRemoteMailbox);
    }

    [Fact]
    public async Task Preflight_BlocksEnabledCustomPowerShellUntilRunnerIsConfigured()
    {
        var configuration = NewUserOnboardingConfiguration.FromProfileJson(
            """
            {
              "CustomPowerShellSteps": [
                {
                  "Id": "ticketing",
                  "DisplayName": "Create ticketing account",
                  "Enabled": true,
                  "Command": "Invoke-CustomOnboarding"
                }
              ]
            }
            """);
        var preflight = new NativeNewUserPreflightService(new FakeLookupProvider(Array.Empty<SimulatorUserSummary>()), configuration);

        var result = await preflight.BuildPlanAsync(Request("cstone"), CorrelationId.From("new-user-custom-step"));

        Assert.True(result.Succeeded);
        Assert.Equal("Blocked", result.Status);
        Assert.False(result.Value!.CanExecute);
        Assert.Contains(result.Value.Steps, step => step.StepId == "custom-powershell:ticketing" && step.IsBlocking);
    }

    private static NewUserPreflightRequest Request(string sam)
    {
        return new NewUserPreflightRequest
        {
            GivenName = "Casey",
            Surname = "Stone",
            SamAccountName = sam,
            Department = "Finance",
            Title = "Analyst",
            ManagerSamAccountName = "treed",
            Office = "Charlotte"
        };
    }

    private static SimulatorUserSummary User(string sam)
    {
        return new SimulatorUserSummary { SamAccountName = sam, UserPrincipalName = $"{sam}@example.com", DisplayName = sam, Enabled = true };
    }

    private sealed class FakeLookupProvider : IUserLookupCapability
    {
        private readonly IReadOnlyList<SimulatorUserSummary> _users;

        public FakeLookupProvider(IReadOnlyList<SimulatorUserSummary> users)
        {
            _users = users;
        }

        public Task<OperationResult<IReadOnlyList<SimulatorUserSummary>>> SearchUsersAsync(string query, CorrelationId correlationId, CancellationToken cancellationToken = default)
        {
            return Task.FromResult(OperationResult<IReadOnlyList<SimulatorUserSummary>>.Success(_users, correlationId));
        }
    }

    private sealed class FakeWriter : ISimulatorWriteCapability
    {
        private readonly List<string> _operations = new();

        public IReadOnlyList<string> Operations => _operations;

        public Task<OperationResult<ProviderChangeResult>> CreateUserAsync(UserCreateRequest request, CorrelationId correlationId, CancellationToken cancellationToken = default)
        {
            _operations.Add("CreateUser");
            return Success("CreateUser", request.SamAccountName, correlationId);
        }

        public Task<OperationResult<ProviderChangeResult>> SetManagerAsync(ManagerChangeRequest request, CorrelationId correlationId, CancellationToken cancellationToken = default)
        {
            _operations.Add("SetManager");
            return Success("SetManager", request.Identity, correlationId);
        }

        public Task<OperationResult<ProviderChangeResult>> UpdateUserAttributesAsync(UserUpdateRequest request, CorrelationId correlationId, CancellationToken cancellationToken = default) => Success("UpdateUserAttributes", request.Identity, correlationId);
        public Task<OperationResult<ProviderChangeResult>> AddGroupMembershipAsync(MembershipChangeRequest request, CorrelationId correlationId, CancellationToken cancellationToken = default) => Success("AddGroupMembership", request.Identity, correlationId);
        public Task<OperationResult<ProviderChangeResult>> RemoveGroupMembershipAsync(MembershipChangeRequest request, CorrelationId correlationId, CancellationToken cancellationToken = default) => Success("RemoveGroupMembership", request.Identity, correlationId);
        public Task<OperationResult<ProviderChangeResult>> SetMailboxForwardingAsync(MailboxForwardingRequest request, CorrelationId correlationId, CancellationToken cancellationToken = default) => Success("SetMailboxForwarding", request.Identity, correlationId);
        public Task<OperationResult<ProviderChangeResult>> SetGalVisibilityAsync(GalVisibilityRequest request, CorrelationId correlationId, CancellationToken cancellationToken = default) => Success("SetGalVisibility", request.Identity, correlationId);
        public Task<OperationResult<ProviderChangeResult>> AddMailboxDelegationAsync(MailboxDelegationChangeRequest request, CorrelationId correlationId, CancellationToken cancellationToken = default) => Success("AddMailboxDelegation", request.Identity, correlationId);
        public MailboxProvisioningRequest? LastMailboxProvisioning { get; private set; }
        public Task<OperationResult<ProviderChangeResult>> EnableRemoteMailboxAsync(MailboxProvisioningRequest request, CorrelationId correlationId, CancellationToken cancellationToken = default)
        {
            _operations.Add("EnableRemoteMailbox");
            LastMailboxProvisioning = request;
            return Success("EnableRemoteMailbox", request.Identity, correlationId);
        }
        public Task<OperationResult<ProviderChangeResult>> ResetStateAsync(CorrelationId correlationId, CancellationToken cancellationToken = default) => Success("ResetState", "test", correlationId);

        private static Task<OperationResult<ProviderChangeResult>> Success(string operation, string target, CorrelationId correlationId)
        {
            return Task.FromResult(OperationResult<ProviderChangeResult>.Success(
                new ProviderChangeResult { Operation = operation, TargetId = target, Changed = true, Message = $"{operation} completed.", Source = "Test" },
                correlationId,
                status: "Completed"));
        }
    }
}
