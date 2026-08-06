using HAP.Contracts;
using HAP.Providers.Abstractions;

namespace HAP.Providers.ExchangeOnPremises;

public sealed class ExchangeOnPremisesProvider : IProviderHealthCapability, IExchangeReadCapability, ISimulatorWriteCapability
{
    private readonly ExchangeOnPremisesProviderOptions _options;

    public ExchangeOnPremisesProvider(ExchangeOnPremisesProviderOptions? options = null)
    {
        _options = options ?? new ExchangeOnPremisesProviderOptions();
    }

    public Task<OperationResult<ProviderHealthResult>> GetHealthAsync(
        CorrelationId correlationId,
        CancellationToken cancellationToken = default)
    {
        var errors = ValidateConnection();
        if (errors.Count > 0)
        {
            return Task.FromResult(OperationResult<ProviderHealthResult>.Failure(correlationId, errors, status: "Failed"));
        }

        var warnings = _options.SupportedManagementApiAvailable
            ? Array.Empty<OperationWarning>()
            : new[] { OperationWarning.Create("ExchangeOnPremises.NativeScopeLimited", "No approved native Exchange on-premises management API is configured.") };

        return Task.FromResult(OperationResult<ProviderHealthResult>.Success(
            new ProviderHealthResult
            {
                ProviderId = "ExchangeOnPremises",
                Mode = "NativeSupportedApisOnly",
                Enabled = true,
                Required = false,
                Status = _options.SupportedManagementApiAvailable ? "Connected" : "Limited",
                Message = _options.SupportedManagementApiAvailable
                    ? "Native Exchange on-premises provider initialized."
                    : "Exchange on-premises administration is limited until a supported non-PowerShell management path is configured.",
                Available = true,
                Connected = _options.SupportedManagementApiAvailable
            },
            correlationId,
            warnings,
            _options.SupportedManagementApiAvailable ? "Connected" : "Limited"));
    }

    public Task<OperationResult<MailboxSummary?>> GetMailboxAsync(string identity, CorrelationId correlationId, CancellationToken cancellationToken = default) =>
        Unsupported<MailboxSummary?>(correlationId, "ExchangeOnPremises.MailboxRead.UnsupportedWithoutApprovedApi", "Mailbox recipient reads require an approved non-PowerShell Exchange on-premises management API.");

    public Task<OperationResult<MailboxStatisticsSummary?>> GetMailboxStatisticsAsync(string identity, CorrelationId correlationId, CancellationToken cancellationToken = default) =>
        Unsupported<MailboxStatisticsSummary?>(correlationId, "ExchangeOnPremises.MailboxStatistics.UnsupportedWithoutApprovedApi", "Mailbox statistics require an approved non-PowerShell Exchange on-premises management API.");

    public Task<OperationResult<IReadOnlyList<MailboxDelegationSummary>>> GetMailboxDelegationsAsync(string identity, CorrelationId correlationId, CancellationToken cancellationToken = default) =>
        Unsupported<IReadOnlyList<MailboxDelegationSummary>>(correlationId, "ExchangeOnPremises.MailboxDelegation.UnsupportedWithoutApprovedApi", "Mailbox delegation reads require an approved non-PowerShell Exchange on-premises management API.");

    public Task<OperationResult<IReadOnlyList<DistributionGroupSummary>>> GetDistributionGroupsAsync(string identity, CorrelationId correlationId, CancellationToken cancellationToken = default) =>
        Unsupported<IReadOnlyList<DistributionGroupSummary>>(correlationId, "ExchangeOnPremises.DistributionGroups.UnsupportedWithoutApprovedApi", "Distribution group administration requires an approved non-PowerShell Exchange on-premises management API.");

    public Task<OperationResult<ProviderChangeResult>> CreateUserAsync(UserCreateRequest request, CorrelationId correlationId, CancellationToken cancellationToken = default) =>
        UnsupportedChange(correlationId, "CreateUser", request.SamAccountName, "ExchangeOnPremises.UserCreate.NotExchangeResponsibility", "User creation is not an Exchange on-premises responsibility in native HAP.");

    public Task<OperationResult<ProviderChangeResult>> UpdateUserAttributesAsync(UserUpdateRequest request, CorrelationId correlationId, CancellationToken cancellationToken = default) =>
        UnsupportedChange(correlationId, "UpdateUserAttributes", request.Identity, "ExchangeOnPremises.UserAttributes.NotExchangeResponsibility", "Directory user attributes are handled by Active Directory.");

    public Task<OperationResult<ProviderChangeResult>> SetManagerAsync(ManagerChangeRequest request, CorrelationId correlationId, CancellationToken cancellationToken = default) =>
        UnsupportedChange(correlationId, "SetManager", request.Identity, "ExchangeOnPremises.Manager.NotExchangeResponsibility", "Manager changes are handled by Active Directory.");

    public Task<OperationResult<ProviderChangeResult>> AddGroupMembershipAsync(MembershipChangeRequest request, CorrelationId correlationId, CancellationToken cancellationToken = default) =>
        UnsupportedChange(correlationId, "AddDistributionGroupMembership", request.Group, "ExchangeOnPremises.DistributionGroupWrite.UnsupportedWithoutApprovedApi", "Distribution group writes require an approved non-PowerShell Exchange on-premises management API or customer extension.");

    public Task<OperationResult<ProviderChangeResult>> RemoveGroupMembershipAsync(MembershipChangeRequest request, CorrelationId correlationId, CancellationToken cancellationToken = default) =>
        UnsupportedChange(correlationId, "RemoveDistributionGroupMembership", request.Group, "ExchangeOnPremises.DistributionGroupWrite.UnsupportedWithoutApprovedApi", "Distribution group writes require an approved non-PowerShell Exchange on-premises management API or customer extension.");

    public Task<OperationResult<ProviderChangeResult>> SetMailboxForwardingAsync(MailboxForwardingRequest request, CorrelationId correlationId, CancellationToken cancellationToken = default) =>
        UnsupportedChange(correlationId, "SetMailboxForwarding", request.Identity, "ExchangeOnPremises.MailboxForwarding.UnsupportedWithoutApprovedApi", "Mailbox forwarding requires an approved non-PowerShell Exchange on-premises management API or customer extension.");

    public Task<OperationResult<ProviderChangeResult>> SetGalVisibilityAsync(GalVisibilityRequest request, CorrelationId correlationId, CancellationToken cancellationToken = default) =>
        UnsupportedChange(correlationId, "SetGalVisibility", request.Identity, "ExchangeOnPremises.GalVisibility.UnsupportedWithoutApprovedApi", "GAL visibility requires an approved non-PowerShell Exchange on-premises management API or customer extension.");

    public Task<OperationResult<ProviderChangeResult>> AddMailboxDelegationAsync(MailboxDelegationChangeRequest request, CorrelationId correlationId, CancellationToken cancellationToken = default) =>
        UnsupportedChange(correlationId, "AddMailboxDelegation", request.Identity, "ExchangeOnPremises.MailboxDelegation.UnsupportedWithoutApprovedApi", "Mailbox delegation requires an approved non-PowerShell Exchange on-premises management API or customer extension.");

    public Task<OperationResult<ProviderChangeResult>> ResetStateAsync(CorrelationId correlationId, CancellationToken cancellationToken = default) =>
        Task.FromResult(OperationResult<ProviderChangeResult>.Success(
            new ProviderChangeResult
            {
                Operation = "ResetState",
                TargetId = "ExchangeOnPremises",
                Changed = false,
                Message = "Native Exchange on-premises provider has no local mutable state.",
                Source = "ExchangeOnPremises"
            },
            correlationId,
            status: "NoChange"));

    private IReadOnlyList<OperationError> ValidateConnection()
    {
        var errors = new List<OperationError>();
        if (!_options.ConnectionAvailable)
        {
            errors.Add(OperationError.Create("ExchangeOnPremises.ConnectionFailed", "Exchange on-premises connection failed."));
        }

        if (!_options.AuthenticationSucceeded)
        {
            errors.Add(OperationError.Create("ExchangeOnPremises.AuthenticationFailed", "Exchange on-premises authentication failed."));
        }

        return errors;
    }

    private static Task<OperationResult<T>> Unsupported<T>(CorrelationId correlationId, string code, string message)
    {
        return Task.FromResult(OperationResult<T>.Failure(
            correlationId,
            new[] { OperationError.Create(code, message) },
            status: "Unsupported"));
    }

    private static Task<OperationResult<ProviderChangeResult>> UnsupportedChange(
        CorrelationId correlationId,
        string operation,
        string targetId,
        string code,
        string message)
    {
        return Task.FromResult(OperationResult<ProviderChangeResult>.Failure(
            correlationId,
            new[] { OperationError.Create(code, message, operation, $"Operation={operation}; Target={targetId}; Disposition=UnsupportedWithoutApprovedApi") },
            status: "Unsupported"));
    }
}
