using HAP.Contracts;

namespace HAP.Providers.Abstractions;

public interface IDirectoryReadCapability
{
    Task<OperationResult<SimulatorUserSummary?>> GetUserAsync(string identity, CorrelationId correlationId, CancellationToken cancellationToken = default);

    Task<OperationResult<SimulatorUserSummary?>> GetManagerAsync(string identity, CorrelationId correlationId, CancellationToken cancellationToken = default);

    Task<OperationResult<IReadOnlyList<DirectoryGroupSummary>>> GetGroupsAsync(string identity, CorrelationId correlationId, CancellationToken cancellationToken = default);

    Task<OperationResult<IReadOnlyList<SimulatorUserSummary>>> GetDirectReportsAsync(string identity, CorrelationId correlationId, CancellationToken cancellationToken = default);
}

public interface IDirectoryAttributeReadCapability
{
    Task<OperationResult<DirectoryObjectAttributeSet>> GetDirectoryAttributesAsync(string identity, CorrelationId correlationId, CancellationToken cancellationToken = default);
}

public interface IDirectoryGroupLookupCapability
{
    Task<OperationResult<IReadOnlyList<DirectoryGroupSummary>>> SearchGroupsAsync(string query, CorrelationId correlationId, CancellationToken cancellationToken = default);
}

public interface IDeviceReadCapability
{
    Task<OperationResult<IReadOnlyList<ManagedDeviceSummary>>> GetManagedDevicesAsync(string identity, CorrelationId correlationId, CancellationToken cancellationToken = default);

    Task<OperationResult<IReadOnlyList<ManagedDeviceSummary>>> SearchDevicesAsync(string query, CorrelationId correlationId, CancellationToken cancellationToken = default);
}

public interface IDeviceActionCapability
{
    Task<OperationResult<DeviceSecretRevealResult>> RevealDeviceSecretAsync(DeviceSecretRevealRequest request, CorrelationId correlationId, CancellationToken cancellationToken = default);

    Task<OperationResult<DeviceLifecycleResult>> RetireDeviceAsync(DeviceLifecycleRequest request, CorrelationId correlationId, CancellationToken cancellationToken = default);

    Task<OperationResult<DeviceLifecycleResult>> DeleteDeviceAsync(DeviceLifecycleRequest request, CorrelationId correlationId, CancellationToken cancellationToken = default);
}

public interface IGraphReadCapability
{
    Task<OperationResult<GraphProfileSummary?>> GetGraphProfileAsync(string identity, CorrelationId correlationId, CancellationToken cancellationToken = default);

    Task<OperationResult<AuthenticationPostureSummary?>> GetAuthenticationPostureAsync(string identity, CorrelationId correlationId, CancellationToken cancellationToken = default);
}

public interface IExchangeReadCapability
{
    Task<OperationResult<MailboxSummary?>> GetMailboxAsync(string identity, CorrelationId correlationId, CancellationToken cancellationToken = default);

    Task<OperationResult<MailboxStatisticsSummary?>> GetMailboxStatisticsAsync(string identity, CorrelationId correlationId, CancellationToken cancellationToken = default);

    Task<OperationResult<IReadOnlyList<MailboxDelegationSummary>>> GetMailboxDelegationsAsync(string identity, CorrelationId correlationId, CancellationToken cancellationToken = default);

    Task<OperationResult<IReadOnlyList<DistributionGroupSummary>>> GetDistributionGroupsAsync(string identity, CorrelationId correlationId, CancellationToken cancellationToken = default);
}

public interface IConfigurationPreviewCapability
{
    Task<OperationResult<ConfigurationPreviewSummary>> GetConfigurationPreviewAsync(CorrelationId correlationId, CancellationToken cancellationToken = default);
}

public interface IReportingReadCapability
{
    Task<OperationResult<IReadOnlyList<ReportingSummary>>> GetReportsAsync(CorrelationId correlationId, CancellationToken cancellationToken = default);
}

public interface ISimulatorWriteCapability
{
    Task<OperationResult<ProviderChangeResult>> CreateUserAsync(UserCreateRequest request, CorrelationId correlationId, CancellationToken cancellationToken = default);

    Task<OperationResult<ProviderChangeResult>> UpdateUserAttributesAsync(UserUpdateRequest request, CorrelationId correlationId, CancellationToken cancellationToken = default);

    Task<OperationResult<ProviderChangeResult>> SetManagerAsync(ManagerChangeRequest request, CorrelationId correlationId, CancellationToken cancellationToken = default);

    Task<OperationResult<ProviderChangeResult>> AddGroupMembershipAsync(MembershipChangeRequest request, CorrelationId correlationId, CancellationToken cancellationToken = default);

    Task<OperationResult<ProviderChangeResult>> RemoveGroupMembershipAsync(MembershipChangeRequest request, CorrelationId correlationId, CancellationToken cancellationToken = default);

    Task<OperationResult<ProviderChangeResult>> SetMailboxForwardingAsync(MailboxForwardingRequest request, CorrelationId correlationId, CancellationToken cancellationToken = default);

    Task<OperationResult<ProviderChangeResult>> SetGalVisibilityAsync(GalVisibilityRequest request, CorrelationId correlationId, CancellationToken cancellationToken = default);

    Task<OperationResult<ProviderChangeResult>> AddMailboxDelegationAsync(MailboxDelegationChangeRequest request, CorrelationId correlationId, CancellationToken cancellationToken = default);

    Task<OperationResult<ProviderChangeResult>> EnableRemoteMailboxAsync(MailboxProvisioningRequest request, CorrelationId correlationId, CancellationToken cancellationToken = default);

    Task<OperationResult<ProviderChangeResult>> ResetStateAsync(CorrelationId correlationId, CancellationToken cancellationToken = default);
}
