using HAP.Application.Capabilities;
using HAP.Application.UserAdministration;
using HAP.Application.Workflows;
using HAP.Contracts;
using HAP.Providers.Abstractions;
using Xunit;

namespace HAP.Application.Tests;

public sealed class NativeUserAdministrationAndWorkflowTests
{
    [Fact]
    public async Task UserAdministration_ReturnsUnavailableForDeferredExchangeAction()
    {
        var service = new NativeUserAdministrationService(new BuiltInCapabilityCatalog(), new Dictionary<string, ISimulatorWriteCapability>());

        var result = await service.InvokeAsync(
            new UserAdministrationActionRequest
            {
                ActionId = UserAdministrationActionIds.SetMailboxForwarding,
                ProviderId = "ExchangeOnline",
                Identity = "amorgan",
                Value = "archive@example.com"
            },
            CorrelationId.From("admin-exo"));

        Assert.True(result.Succeeded);
        Assert.Equal("Unavailable", result.Status);
        Assert.False(result.Value!.Available);
        Assert.Contains("deferred", result.Value.Message, StringComparison.OrdinalIgnoreCase);
    }

    [Fact]
    public async Task UserAdministration_InvokesAvailableSimulatorAction()
    {
        var writer = new FakeWriter();
        var service = new NativeUserAdministrationService(
            new BuiltInCapabilityCatalog(),
            new Dictionary<string, ISimulatorWriteCapability> { ["DirectorySimulator"] = writer });

        var result = await service.InvokeAsync(
            new UserAdministrationActionRequest
            {
                ActionId = UserAdministrationActionIds.AddGroupMembership,
                ProviderId = "DirectorySimulator",
                Identity = "amorgan",
                Value = "GG-Test"
            },
            CorrelationId.From("admin-sim"));

        Assert.True(result.Succeeded);
        Assert.True(result.Value!.Available);
        Assert.Equal("AddGroupMembership", writer.Operation);
    }

    [Fact]
    public void WorkflowExport_ProducesDeterministicJson()
    {
        var service = new NativeWorkflowExportService();

        var result = service.ExportJson(
            new WorkflowExportDocument
            {
                WorkflowName = "Devices",
                Columns = new[] { "Name", "Id" },
                Rows = new[]
                {
                    new Dictionary<string, string> { ["Id"] = "2", ["Name"] = "B" },
                    new Dictionary<string, string> { ["Id"] = "1", ["Name"] = "A" }
                }
            },
            CorrelationId.From("export"));

        Assert.True(result.Succeeded);
        Assert.Contains("\"SchemaVersion\": \"1.0\"", result.Value);
        Assert.True(result.Value!.IndexOf("\"Id\": \"1\"", StringComparison.Ordinal) < result.Value.IndexOf("\"Id\": \"2\"", StringComparison.Ordinal));
    }

    [Fact]
    public async Task WorkflowEngine_ExecutesJsonDefinedNativeProviderActions()
    {
        var writer = new FakeWriter();
        var definition = WorkflowDefinition.FromJson(
            """
            {
              "Id": "onboarding-basic",
              "Name": "Basic Onboarding",
              "Category": "Onboarding",
              "Actions": [
                {
                  "Id": "create-user",
                  "Name": "Create AD user",
                  "Type": "CreateAdUser",
                  "ProviderId": "ActiveDirectory",
                  "Inputs": {
                    "GivenName": "{{FirstName}}",
                    "Surname": "{{LastName}}",
                    "SamAccountName": "{{SamAccountName}}",
                    "UserPrincipalName": "{{SamAccountName}}@littleinnovation.tech",
                    "Attribute:badgeID": "{{BadgeId}}"
                  }
                },
                {
                  "Id": "vpn-group",
                  "Name": "Add VPN group",
                  "Type": "AddGroup",
                  "ProviderId": "ActiveDirectory",
                  "Inputs": {
                    "Identity": "{{SamAccountName}}",
                    "Group": "GG-VPN-Users"
                  }
                },
                {
                  "Id": "remote-mailbox",
                  "Name": "Enable mailbox",
                  "Type": "EnableRemoteMailbox",
                  "ProviderId": "ExchangeOnPremises",
                  "Inputs": {
                    "Identity": "{{SamAccountName}}",
                    "RemoteRoutingAddress": "{{SamAccountName}}@littleinnovation.mail.onmicrosoft.us"
                  }
                }
              ]
            }
            """);
        var engine = new WorkflowExecutionEngine(new NativeProviderWorkflowActionExecutor(
            new Dictionary<string, ISimulatorWriteCapability>
            {
                ["ActiveDirectory"] = writer,
                ["ExchangeOnPremises"] = writer
            }));

        var result = await engine.ExecuteAsync(
            new WorkflowExecutionRequest
            {
                Definition = definition,
                Variables = new Dictionary<string, string>
                {
                    ["FirstName"] = "Casey",
                    ["LastName"] = "Stone",
                    ["SamAccountName"] = "cstone",
                    ["BadgeId"] = "B-100"
                }
            },
            CorrelationId.From("workflow-onboarding"));

        Assert.True(result.Succeeded);
        Assert.Equal("Completed", result.Status);
        Assert.Equal(new[] { "CreateUser", "AddGroupMembership", "EnableRemoteMailbox" }, writer.Operations);
        Assert.Equal("B-100", writer.LastCreateUser?.OtherAttributes["badgeID"]);
    }

    [Fact]
    public async Task WorkflowEngine_RequiresExplicitRunnerForPowerShellActions()
    {
        var definition = WorkflowDefinition.FromJson(
            """
            {
              "Id": "customer-extension",
              "Name": "Customer Extension",
              "Actions": [
                {
                  "Id": "servicenow",
                  "Name": "Create ServiceNow account",
                  "Type": "ExecutePowerShell",
                  "Inputs": {
                    "Command": "New-ServiceNowUser -Sam {{SamAccountName}}"
                  }
                }
              ]
            }
            """);
        var engine = new WorkflowExecutionEngine(new NativeProviderWorkflowActionExecutor(new Dictionary<string, ISimulatorWriteCapability>()));

        var result = await engine.ExecuteAsync(
            new WorkflowExecutionRequest
            {
                Definition = definition,
                Variables = new Dictionary<string, string> { ["SamAccountName"] = "cstone" }
            },
            CorrelationId.From("workflow-powershell"));

        Assert.True(result.Succeeded);
        Assert.Single(result.Value!.Actions);
        Assert.True(result.Value.Actions[0].Skipped);
        Assert.Equal("RunnerRequired", result.Value.Actions[0].Status);
    }

    private sealed class FakeWriter : ISimulatorWriteCapability
    {
        public string Operation { get; private set; } = string.Empty;
        private readonly List<string> _operations = new();

        public IReadOnlyList<string> Operations => _operations;

        public UserCreateRequest? LastCreateUser { get; private set; }

        public Task<OperationResult<ProviderChangeResult>> AddGroupMembershipAsync(MembershipChangeRequest request, CorrelationId correlationId, CancellationToken cancellationToken = default)
        {
            Operation = "AddGroupMembership";
            _operations.Add(Operation);
            return Success(correlationId);
        }

        public Task<OperationResult<ProviderChangeResult>> CreateUserAsync(UserCreateRequest request, CorrelationId correlationId, CancellationToken cancellationToken = default)
        {
            Operation = "CreateUser";
            _operations.Add(Operation);
            LastCreateUser = request;
            return Success(correlationId);
        }

        public Task<OperationResult<ProviderChangeResult>> UpdateUserAttributesAsync(UserUpdateRequest request, CorrelationId correlationId, CancellationToken cancellationToken = default) => Success(correlationId);
        public Task<OperationResult<ProviderChangeResult>> SetManagerAsync(ManagerChangeRequest request, CorrelationId correlationId, CancellationToken cancellationToken = default) => Success(correlationId);
        public Task<OperationResult<ProviderChangeResult>> RemoveGroupMembershipAsync(MembershipChangeRequest request, CorrelationId correlationId, CancellationToken cancellationToken = default) => Success(correlationId);
        public Task<OperationResult<ProviderChangeResult>> SetMailboxForwardingAsync(MailboxForwardingRequest request, CorrelationId correlationId, CancellationToken cancellationToken = default) => Success(correlationId);
        public Task<OperationResult<ProviderChangeResult>> SetGalVisibilityAsync(GalVisibilityRequest request, CorrelationId correlationId, CancellationToken cancellationToken = default) => Success(correlationId);
        public Task<OperationResult<ProviderChangeResult>> AddMailboxDelegationAsync(MailboxDelegationChangeRequest request, CorrelationId correlationId, CancellationToken cancellationToken = default) => Success(correlationId);
        public Task<OperationResult<ProviderChangeResult>> EnableRemoteMailboxAsync(MailboxProvisioningRequest request, CorrelationId correlationId, CancellationToken cancellationToken = default)
        {
            Operation = "EnableRemoteMailbox";
            _operations.Add(Operation);
            return Success(correlationId);
        }

        public Task<OperationResult<ProviderChangeResult>> ResetStateAsync(CorrelationId correlationId, CancellationToken cancellationToken = default) => Success(correlationId);

        private static Task<OperationResult<ProviderChangeResult>> Success(CorrelationId correlationId)
        {
            return Task.FromResult(OperationResult<ProviderChangeResult>.Success(
                new ProviderChangeResult { Changed = true, Message = "Done", Source = "Test" },
                correlationId,
                status: "Completed"));
        }
    }
}
