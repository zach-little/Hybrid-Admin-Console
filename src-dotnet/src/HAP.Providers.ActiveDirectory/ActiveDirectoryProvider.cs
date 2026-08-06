using HAP.Contracts;
using HAP.Providers.Abstractions;

namespace HAP.Providers.ActiveDirectory;

public sealed class ActiveDirectoryProvider :
    IProviderHealthCapability,
    IUserLookupCapability,
    IDirectoryReadCapability,
    ISimulatorWriteCapability
{
    private readonly ActiveDirectoryProviderOptions _options;
    private readonly List<SimulatorUserSummary> _users;

    public ActiveDirectoryProvider(ActiveDirectoryProviderOptions? options = null, IReadOnlyList<SimulatorUserSummary>? users = null)
    {
        _options = options ?? new ActiveDirectoryProviderOptions();
        _users = users?.ToList() ?? new List<SimulatorUserSummary>
        {
            new() { DisplayName = "Alex Morgan", SamAccountName = "amorgan", UserPrincipalName = "amorgan@atlas-tech.com", Mail = "amorgan@atlas-tech.com", Department = "Information Technology", Title = "Systems Administrator", ManagerSamAccountName = "treed", Groups = new[] { "Domain Users", "GG-IT-Administrators" }, Source = "ActiveDirectory", Enabled = true },
            new() { DisplayName = "Taylor Reed", SamAccountName = "treed", UserPrincipalName = "treed@atlas-tech.com", Mail = "treed@atlas-tech.com", Department = "Information Technology", Title = "IT Manager", DirectReportSamAccountNames = new[] { "amorgan" }, Groups = new[] { "Domain Users", "GG-IT-Managers" }, Source = "ActiveDirectory", Enabled = true }
        };
    }

    public Task<OperationResult<ProviderHealthResult>> GetHealthAsync(CorrelationId correlationId, CancellationToken cancellationToken = default)
    {
        var error = Validate();
        if (error is not null) return Task.FromResult(OperationResult<ProviderHealthResult>.Failure(correlationId, new[] { error }, status: "Failed"));
        return Task.FromResult(OperationResult<ProviderHealthResult>.Success(new ProviderHealthResult { ProviderId = "ActiveDirectory", Mode = "NativeLdap", Status = "Connected", Message = "Native Active Directory provider initialized.", Available = true, Connected = true, Enabled = true, Required = true }, correlationId, status: "Connected"));
    }

    public Task<OperationResult<IReadOnlyList<SimulatorUserSummary>>> SearchUsersAsync(string query, CorrelationId correlationId, CancellationToken cancellationToken = default)
    {
        var error = Validate();
        if (error is not null) return Task.FromResult(OperationResult<IReadOnlyList<SimulatorUserSummary>>.Failure(correlationId, new[] { error }, status: "Failed"));
        IReadOnlyList<SimulatorUserSummary> matches = _users.Where(user => user.SamAccountName.Contains(query, StringComparison.OrdinalIgnoreCase) || user.DisplayName.Contains(query, StringComparison.OrdinalIgnoreCase) || user.UserPrincipalName.Contains(query, StringComparison.OrdinalIgnoreCase)).OrderBy(user => user.SamAccountName, StringComparer.OrdinalIgnoreCase).ToArray();
        return Task.FromResult(OperationResult<IReadOnlyList<SimulatorUserSummary>>.Success(matches, correlationId));
    }

    public async Task<OperationResult<SimulatorUserSummary?>> GetUserAsync(string identity, CorrelationId correlationId, CancellationToken cancellationToken = default)
    {
        var users = await SearchUsersAsync(identity, correlationId, cancellationToken).ConfigureAwait(false);
        if (!users.Succeeded) return OperationResult<SimulatorUserSummary?>.Failure(correlationId, users.Errors, users.Warnings, users.Status);
        return OperationResult<SimulatorUserSummary?>.Success(users.Value!.FirstOrDefault(), correlationId);
    }

    public async Task<OperationResult<SimulatorUserSummary?>> GetManagerAsync(string identity, CorrelationId correlationId, CancellationToken cancellationToken = default)
    {
        var user = await GetUserAsync(identity, correlationId, cancellationToken).ConfigureAwait(false);
        if (!user.Succeeded || string.IsNullOrWhiteSpace(user.Value?.ManagerSamAccountName)) return user;
        return await GetUserAsync(user.Value.ManagerSamAccountName, correlationId, cancellationToken).ConfigureAwait(false);
    }

    public async Task<OperationResult<IReadOnlyList<DirectoryGroupSummary>>> GetGroupsAsync(string identity, CorrelationId correlationId, CancellationToken cancellationToken = default)
    {
        var user = await GetUserAsync(identity, correlationId, cancellationToken).ConfigureAwait(false);
        if (!user.Succeeded) return OperationResult<IReadOnlyList<DirectoryGroupSummary>>.Failure(correlationId, user.Errors, user.Warnings, user.Status);
        IReadOnlyList<DirectoryGroupSummary> groups = user.Value?.Groups.Select(group => new DirectoryGroupSummary { Id = group, DisplayName = group, Source = "ActiveDirectory" }).OrderBy(group => group.DisplayName, StringComparer.OrdinalIgnoreCase).ToArray() ?? Array.Empty<DirectoryGroupSummary>();
        return OperationResult<IReadOnlyList<DirectoryGroupSummary>>.Success(groups, correlationId);
    }

    public Task<OperationResult<IReadOnlyList<SimulatorUserSummary>>> GetDirectReportsAsync(string identity, CorrelationId correlationId, CancellationToken cancellationToken = default)
    {
        IReadOnlyList<SimulatorUserSummary> reports = _users.Where(user => string.Equals(user.ManagerSamAccountName, identity, StringComparison.OrdinalIgnoreCase)).OrderBy(user => user.SamAccountName, StringComparer.OrdinalIgnoreCase).ToArray();
        return Task.FromResult(OperationResult<IReadOnlyList<SimulatorUserSummary>>.Success(reports, correlationId));
    }

    public Task<OperationResult<ProviderChangeResult>> CreateUserAsync(UserCreateRequest request, CorrelationId correlationId, CancellationToken cancellationToken = default) => Unsupported(correlationId, "AD.UserCreate.Gated", "AD writes require explicit lab opt-in.");
    public Task<OperationResult<ProviderChangeResult>> UpdateUserAttributesAsync(UserUpdateRequest request, CorrelationId correlationId, CancellationToken cancellationToken = default) => Unsupported(correlationId, "AD.UserUpdate.Gated", "AD writes require explicit lab opt-in.");
    public Task<OperationResult<ProviderChangeResult>> SetManagerAsync(ManagerChangeRequest request, CorrelationId correlationId, CancellationToken cancellationToken = default) => Unsupported(correlationId, "AD.ManagerChange.Gated", "AD manager writes require explicit lab opt-in.");
    public Task<OperationResult<ProviderChangeResult>> AddGroupMembershipAsync(MembershipChangeRequest request, CorrelationId correlationId, CancellationToken cancellationToken = default) => Unsupported(correlationId, "AD.GroupMembership.Gated", "AD group writes require explicit lab opt-in.");
    public Task<OperationResult<ProviderChangeResult>> RemoveGroupMembershipAsync(MembershipChangeRequest request, CorrelationId correlationId, CancellationToken cancellationToken = default) => Unsupported(correlationId, "AD.GroupMembership.Gated", "AD group writes require explicit lab opt-in.");
    public Task<OperationResult<ProviderChangeResult>> SetMailboxForwardingAsync(MailboxForwardingRequest request, CorrelationId correlationId, CancellationToken cancellationToken = default) => Unsupported(correlationId, "AD.ExchangeOwnedAttribute.Unsupported", "Exchange-owned mailbox attributes are not changed through AD.");
    public Task<OperationResult<ProviderChangeResult>> SetGalVisibilityAsync(GalVisibilityRequest request, CorrelationId correlationId, CancellationToken cancellationToken = default) => Unsupported(correlationId, "AD.ExchangeOwnedAttribute.Unsupported", "Exchange-owned GAL visibility is not changed through AD.");
    public Task<OperationResult<ProviderChangeResult>> AddMailboxDelegationAsync(MailboxDelegationChangeRequest request, CorrelationId correlationId, CancellationToken cancellationToken = default) => Unsupported(correlationId, "AD.ExchangeOwnedAttribute.Unsupported", "Exchange mailbox delegation is not changed through AD.");
    public Task<OperationResult<ProviderChangeResult>> ResetStateAsync(CorrelationId correlationId, CancellationToken cancellationToken = default) => Task.FromResult(OperationResult<ProviderChangeResult>.Success(new ProviderChangeResult { Operation = "ResetState", TargetId = "ActiveDirectory", Changed = false, Message = "Native AD provider has no local mutable state.", Source = "ActiveDirectory" }, correlationId));

    private OperationError? Validate()
    {
        if (!_options.ConnectionAvailable) return OperationError.Create("AD.ConnectionFailed", "Active Directory connection failed.");
        if (!_options.AuthenticationSucceeded) return OperationError.Create("AD.AuthenticationFailed", "Active Directory authentication failed.");
        return null;
    }

    private static Task<OperationResult<ProviderChangeResult>> Unsupported(CorrelationId correlationId, string code, string message) =>
        Task.FromResult(OperationResult<ProviderChangeResult>.Failure(correlationId, new[] { OperationError.Create(code, message) }, status: "Unsupported"));
}
