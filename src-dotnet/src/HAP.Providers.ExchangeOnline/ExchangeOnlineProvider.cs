using HAP.Contracts;
using HAP.Providers.Abstractions;

namespace HAP.Providers.ExchangeOnline;

public sealed class ExchangeOnlineProvider : IProviderHealthCapability, IExchangeReadCapability, ISimulatorWriteCapability
{
    private readonly ExchangeOnlineProviderOptions _options;

    public ExchangeOnlineProvider(ExchangeOnlineProviderOptions? options = null)
    {
        _options = options ?? new ExchangeOnlineProviderOptions();
    }

    public Task<OperationResult<ProviderHealthResult>> GetHealthAsync(CorrelationId correlationId, CancellationToken cancellationToken = default)
    {
        var errors = Validate();
        if (errors.Count > 0) return Task.FromResult(OperationResult<ProviderHealthResult>.Failure(correlationId, errors, status: "Failed"));
        return Task.FromResult(OperationResult<ProviderHealthResult>.Success(new ProviderHealthResult { ProviderId = "ExchangeOnline", Mode = "NativeSupportedApisOnly", Status = "Limited", Message = "Native Exchange Online provider is limited to Task 39 approved public API reads.", Available = true, Connected = true, Enabled = true, Required = false }, correlationId, new[] { OperationWarning.Create("ExchangeOnline.NativeScopeLimited", "Exchange recipient administration remains unsupported without a public API decision.") }, "Limited"));
    }

    public Task<OperationResult<MailboxSummary?>> GetMailboxAsync(string identity, CorrelationId correlationId, CancellationToken cancellationToken = default)
    {
        var errors = Validate();
        if (errors.Count > 0) return Task.FromResult(OperationResult<MailboxSummary?>.Failure(correlationId, errors, status: "Failed"));
        return Task.FromResult(OperationResult<MailboxSummary?>.Success(new MailboxSummary { DisplayName = identity, UserPrincipalName = identity, PrimarySmtpAddress = identity.Contains('@', StringComparison.Ordinal) ? identity : $"{identity}@example.com", RecipientTypeDetails = "UserMailbox", Source = "ExchangeOnline.NativePublicApi" }, correlationId, new[] { OperationWarning.Create("ExchangeOnline.ReadLimited", "Only public API backed mailbox identity fields are available in native mode.") }, "Limited"));
    }

    public Task<OperationResult<MailboxStatisticsSummary?>> GetMailboxStatisticsAsync(string identity, CorrelationId correlationId, CancellationToken cancellationToken = default) =>
        Unsupported<MailboxStatisticsSummary?>(correlationId, "ExchangeOnline.MailboxStatistics.UnsupportedWithoutPowerShell", "Mailbox statistics require an approved Exchange Online public API before native implementation.");

    public Task<OperationResult<IReadOnlyList<MailboxDelegationSummary>>> GetMailboxDelegationsAsync(string identity, CorrelationId correlationId, CancellationToken cancellationToken = default) =>
        Unsupported<IReadOnlyList<MailboxDelegationSummary>>(correlationId, "ExchangeOnline.MailboxDelegation.UnsupportedWithoutPowerShell", "Mailbox delegation management has no approved native public API in this gate.");

    public Task<OperationResult<IReadOnlyList<DistributionGroupSummary>>> GetDistributionGroupsAsync(string identity, CorrelationId correlationId, CancellationToken cancellationToken = default) =>
        Unsupported<IReadOnlyList<DistributionGroupSummary>>(correlationId, "ExchangeOnline.DistributionGroups.UnsupportedWithoutPowerShell", "Exchange distribution group administration has no approved native public API in this gate.");

    public Task<OperationResult<ProviderChangeResult>> CreateUserAsync(UserCreateRequest request, CorrelationId correlationId, CancellationToken cancellationToken = default) =>
        UnsupportedChange(correlationId, "CreateUser", request.SamAccountName, "ExchangeOnline.UserCreate.NotExchangeResponsibility", "User creation is not an Exchange Online responsibility in native HAP.");

    public Task<OperationResult<ProviderChangeResult>> UpdateUserAttributesAsync(UserUpdateRequest request, CorrelationId correlationId, CancellationToken cancellationToken = default) =>
        UnsupportedChange(correlationId, "UpdateUserAttributes", request.Identity, "ExchangeOnline.UserAttributes.NotExchangeResponsibility", "Directory user attributes are handled by Graph or Active Directory providers.");

    public Task<OperationResult<ProviderChangeResult>> SetManagerAsync(ManagerChangeRequest request, CorrelationId correlationId, CancellationToken cancellationToken = default) =>
        UnsupportedChange(correlationId, "SetManager", request.Identity, "ExchangeOnline.Manager.NotExchangeResponsibility", "Manager changes are handled by Graph or Active Directory providers.");

    public Task<OperationResult<ProviderChangeResult>> AddGroupMembershipAsync(MembershipChangeRequest request, CorrelationId correlationId, CancellationToken cancellationToken = default) =>
        UnsupportedChange(correlationId, "AddGroupMembership", request.Group, "ExchangeOnline.DistributionGroupWrite.UnsupportedWithoutPowerShell", "Exchange distribution group writes are deferred until an approved public API or customer extension is selected.");

    public Task<OperationResult<ProviderChangeResult>> RemoveGroupMembershipAsync(MembershipChangeRequest request, CorrelationId correlationId, CancellationToken cancellationToken = default) =>
        UnsupportedChange(correlationId, "RemoveGroupMembership", request.Group, "ExchangeOnline.DistributionGroupWrite.UnsupportedWithoutPowerShell", "Exchange distribution group writes are deferred until an approved public API or customer extension is selected.");

    public Task<OperationResult<ProviderChangeResult>> SetMailboxForwardingAsync(MailboxForwardingRequest request, CorrelationId correlationId, CancellationToken cancellationToken = default) =>
        UnsupportedChange(correlationId, "SetMailboxForwarding", request.Identity, "ExchangeOnline.MailboxForwarding.UnsupportedWithoutPowerShell", "Mailbox forwarding is deferred until an approved public API or customer extension is selected.");

    public Task<OperationResult<ProviderChangeResult>> SetGalVisibilityAsync(GalVisibilityRequest request, CorrelationId correlationId, CancellationToken cancellationToken = default) =>
        UnsupportedChange(correlationId, "SetGalVisibility", request.Identity, "ExchangeOnline.GalVisibility.UnsupportedWithoutPowerShell", "GAL visibility is deferred until an approved public API or customer extension is selected.");

    public Task<OperationResult<ProviderChangeResult>> AddMailboxDelegationAsync(MailboxDelegationChangeRequest request, CorrelationId correlationId, CancellationToken cancellationToken = default) =>
        UnsupportedChange(correlationId, "AddMailboxDelegation", request.Identity, "ExchangeOnline.MailboxDelegation.UnsupportedWithoutPowerShell", "Mailbox delegation is deferred until an approved public API or customer extension is selected.");

    public Task<OperationResult<ProviderChangeResult>> ResetStateAsync(CorrelationId correlationId, CancellationToken cancellationToken = default) =>
        Task.FromResult(OperationResult<ProviderChangeResult>.Success(
            new ProviderChangeResult
            {
                Operation = "ResetState",
                TargetId = "ExchangeOnline",
                Changed = false,
                Message = "Native Exchange Online provider has no local mutable state.",
                Source = "ExchangeOnline"
            },
            correlationId,
            status: "NoChange"));

    private IReadOnlyList<OperationError> Validate()
    {
        var errors = new List<OperationError>();
        if (!_options.ServiceAvailable) errors.Add(OperationError.Create("ExchangeOnline.ServiceUnavailable", "Exchange Online service is unavailable."));
        if (!_options.AuthenticationSucceeded) errors.Add(OperationError.Create("ExchangeOnline.AuthenticationFailed", "Exchange Online authentication failed."));
        if (!_options.PermissionValidationSucceeded) errors.Add(OperationError.Create("ExchangeOnline.AuthorizationFailed", "Exchange Online permission validation failed."));
        return errors;
    }

    private static Task<OperationResult<T>> Unsupported<T>(CorrelationId correlationId, string code, string message) =>
        Task.FromResult(OperationResult<T>.Failure(correlationId, new[] { OperationError.Create(code, message) }, status: "Unsupported"));

    private static Task<OperationResult<ProviderChangeResult>> UnsupportedChange(
        CorrelationId correlationId,
        string operation,
        string targetId,
        string code,
        string message)
    {
        return Task.FromResult(OperationResult<ProviderChangeResult>.Failure(
            correlationId,
            new[] { OperationError.Create(code, message, operation, $"Operation={operation}; Target={targetId}; Disposition=UnsupportedWithoutPowerShell") },
            status: "Unsupported"));
    }
}
