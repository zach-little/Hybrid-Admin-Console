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

    private sealed class FakeWriter : ISimulatorWriteCapability
    {
        public string Operation { get; private set; } = string.Empty;

        public Task<OperationResult<ProviderChangeResult>> AddGroupMembershipAsync(MembershipChangeRequest request, CorrelationId correlationId, CancellationToken cancellationToken = default)
        {
            Operation = "AddGroupMembership";
            return Success(correlationId);
        }

        public Task<OperationResult<ProviderChangeResult>> CreateUserAsync(UserCreateRequest request, CorrelationId correlationId, CancellationToken cancellationToken = default) => Success(correlationId);
        public Task<OperationResult<ProviderChangeResult>> UpdateUserAttributesAsync(UserUpdateRequest request, CorrelationId correlationId, CancellationToken cancellationToken = default) => Success(correlationId);
        public Task<OperationResult<ProviderChangeResult>> SetManagerAsync(ManagerChangeRequest request, CorrelationId correlationId, CancellationToken cancellationToken = default) => Success(correlationId);
        public Task<OperationResult<ProviderChangeResult>> RemoveGroupMembershipAsync(MembershipChangeRequest request, CorrelationId correlationId, CancellationToken cancellationToken = default) => Success(correlationId);
        public Task<OperationResult<ProviderChangeResult>> SetMailboxForwardingAsync(MailboxForwardingRequest request, CorrelationId correlationId, CancellationToken cancellationToken = default) => Success(correlationId);
        public Task<OperationResult<ProviderChangeResult>> SetGalVisibilityAsync(GalVisibilityRequest request, CorrelationId correlationId, CancellationToken cancellationToken = default) => Success(correlationId);
        public Task<OperationResult<ProviderChangeResult>> AddMailboxDelegationAsync(MailboxDelegationChangeRequest request, CorrelationId correlationId, CancellationToken cancellationToken = default) => Success(correlationId);
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
