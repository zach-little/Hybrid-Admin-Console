using HAP.Contracts;
using HAP.Providers.Abstractions;

namespace HAP.Providers.Graph;

public sealed class MicrosoftGraphProvider :
    IProviderHealthCapability,
    IUserLookupCapability,
    IGraphReadCapability,
    IDeviceReadCapability,
    ISimulatorWriteCapability
{
    private readonly GraphProviderOptions _options;
    private readonly List<SimulatorUserSummary> _users;

    public MicrosoftGraphProvider(GraphProviderOptions? options = null, IReadOnlyList<SimulatorUserSummary>? users = null)
    {
        _options = options ?? new GraphProviderOptions();
        _users = users?.ToList() ?? SeedUsers();
    }

    public Task<OperationResult<ProviderHealthResult>> GetHealthAsync(CorrelationId correlationId, CancellationToken cancellationToken = default)
    {
        var errors = ValidateSession();
        if (errors.Count > 0)
        {
            return Task.FromResult(OperationResult<ProviderHealthResult>.Failure(correlationId, errors, status: "Failed"));
        }

        return Task.FromResult(OperationResult<ProviderHealthResult>.Success(
            new ProviderHealthResult
            {
                ProviderId = "MicrosoftGraph",
                Mode = _options.AuthenticationMode,
                Enabled = true,
                Required = true,
                Status = "Connected",
                Message = "Native Microsoft Graph session foundation initialized.",
                Available = true,
                Connected = true
            },
            correlationId,
            status: "Connected"));
    }

    public Task<OperationResult<IReadOnlyList<SimulatorUserSummary>>> SearchUsersAsync(string query, CorrelationId correlationId, CancellationToken cancellationToken = default)
    {
        var errors = ValidateSession();
        if (errors.Count > 0)
        {
            return Task.FromResult(OperationResult<IReadOnlyList<SimulatorUserSummary>>.Failure(correlationId, errors, status: "Failed"));
        }

        if (string.IsNullOrWhiteSpace(query))
        {
            return Task.FromResult(OperationResult<IReadOnlyList<SimulatorUserSummary>>.Failure(correlationId, new[] { OperationError.Create("Graph.UserLookup.QueryRequired", "Graph user lookup query is required.") }));
        }

        var clean = query.Trim();
        IReadOnlyList<SimulatorUserSummary> matches = _users
            .Where(user => user.SamAccountName.Contains(clean, StringComparison.OrdinalIgnoreCase) ||
                           user.UserPrincipalName.Contains(clean, StringComparison.OrdinalIgnoreCase) ||
                           user.DisplayName.Contains(clean, StringComparison.OrdinalIgnoreCase))
            .OrderBy(user => user.SamAccountName, StringComparer.OrdinalIgnoreCase)
            .ToArray();

        return Task.FromResult(OperationResult<IReadOnlyList<SimulatorUserSummary>>.Success(matches, correlationId));
    }

    public async Task<OperationResult<GraphProfileSummary?>> GetGraphProfileAsync(string identity, CorrelationId correlationId, CancellationToken cancellationToken = default)
    {
        var userResult = await FindUserAsync(identity, correlationId, cancellationToken).ConfigureAwait(false);
        if (!userResult.Succeeded)
        {
            return OperationResult<GraphProfileSummary?>.Failure(correlationId, userResult.Errors, userResult.Warnings, userResult.Status);
        }

        var user = userResult.Value;
        return OperationResult<GraphProfileSummary?>.Success(user is null ? null : new GraphProfileSummary
        {
            ObjectId = $"graph-{user.SamAccountName}",
            SamAccountName = user.SamAccountName,
            DisplayName = user.DisplayName,
            UserPrincipalName = user.UserPrincipalName,
            UserType = "Member",
            PreferredLanguage = "en-US",
            UsageLocation = "US",
            LastSignInDateTime = new DateTimeOffset(2026, 1, 15, 13, 0, 0, TimeSpan.Zero),
            PasswordLastChangedDateTime = new DateTimeOffset(2025, 12, 1, 9, 0, 0, TimeSpan.Zero),
            AuthenticationMethods = new[] { "password", "microsoftAuthenticatorPush" },
            Licenses = new[] { new LicenseAssignmentSummary { SkuPartNumber = "ENTERPRISEPACK", FriendlyName = "Microsoft 365 E3", AssignmentState = "Active", Source = "MicrosoftGraph" } },
            PimRoles = user.SamAccountName.EndsWith("adm", StringComparison.OrdinalIgnoreCase) ? new[] { "User Administrator" } : Array.Empty<string>(),
            MfaRegistered = true,
            MfaCapable = true,
            RiskState = "none",
            Source = "MicrosoftGraph"
        }, correlationId);
    }

    public async Task<OperationResult<AuthenticationPostureSummary?>> GetAuthenticationPostureAsync(string identity, CorrelationId correlationId, CancellationToken cancellationToken = default)
    {
        var profile = await GetGraphProfileAsync(identity, correlationId, cancellationToken).ConfigureAwait(false);
        if (!profile.Succeeded)
        {
            return OperationResult<AuthenticationPostureSummary?>.Failure(correlationId, profile.Errors, profile.Warnings, profile.Status);
        }

        return OperationResult<AuthenticationPostureSummary?>.Success(profile.Value is null ? null : new AuthenticationPostureSummary
        {
            UserPrincipalName = profile.Value.UserPrincipalName,
            DisplayName = profile.Value.DisplayName,
            DefaultMethod = "microsoftAuthenticatorPush",
            AuthenticationMethods = profile.Value.AuthenticationMethods,
            MfaRegistered = true,
            MfaCapable = true,
            PasswordlessRegistered = false,
            TemporaryAccessPassEligible = true,
            AuthenticationStrength = "Multifactor capable",
            ConditionalAccessState = "Satisfied",
            SignInRiskState = profile.Value.RiskState,
            LastSuccessfulSignInDateTime = profile.Value.LastSignInDateTime,
            PasswordLastChangedDateTime = profile.Value.PasswordLastChangedDateTime,
            Source = "MicrosoftGraph"
        }, correlationId);
    }

    public async Task<OperationResult<IReadOnlyList<ManagedDeviceSummary>>> GetManagedDevicesAsync(string identity, CorrelationId correlationId, CancellationToken cancellationToken = default)
    {
        var user = await FindUserAsync(identity, correlationId, cancellationToken).ConfigureAwait(false);
        if (!user.Succeeded)
        {
            return OperationResult<IReadOnlyList<ManagedDeviceSummary>>.Failure(correlationId, user.Errors, user.Warnings, user.Status);
        }

        IReadOnlyList<ManagedDeviceSummary> devices = user.Value is null ? Array.Empty<ManagedDeviceSummary>() : new[]
        {
            new ManagedDeviceSummary
            {
                Id = $"graph-device-{user.Value.SamAccountName}-01",
                Name = $"GRAPH-{user.Value.SamAccountName.ToUpperInvariant()}-LT01",
                OperatingSystem = "Windows",
                ComplianceState = "Compliant",
                PrimaryUser = user.Value.UserPrincipalName,
                LastCheckInUtc = new DateTimeOffset(2026, 1, 15, 10, 0, 0, TimeSpan.Zero),
                Source = "MicrosoftGraph.DeviceManagement"
            }
        };

        return OperationResult<IReadOnlyList<ManagedDeviceSummary>>.Success(devices, correlationId);
    }

    public Task<OperationResult<IReadOnlyList<ManagedDeviceSummary>>> SearchDevicesAsync(string query, CorrelationId correlationId, CancellationToken cancellationToken = default)
    {
        if (string.IsNullOrWhiteSpace(query))
        {
            return Task.FromResult(OperationResult<IReadOnlyList<ManagedDeviceSummary>>.Failure(correlationId, new[] { OperationError.Create("Graph.DeviceLookup.QueryRequired", "Device lookup query is required.") }));
        }

        IReadOnlyList<ManagedDeviceSummary> devices = _users
            .Select(user => new ManagedDeviceSummary { Id = $"graph-device-{user.SamAccountName}-01", Name = $"GRAPH-{user.SamAccountName.ToUpperInvariant()}-LT01", PrimaryUser = user.UserPrincipalName, ComplianceState = "Compliant", OperatingSystem = "Windows", Source = "MicrosoftGraph.DeviceManagement" })
            .Where(device => device.Name.Contains(query, StringComparison.OrdinalIgnoreCase) || device.PrimaryUser.Contains(query, StringComparison.OrdinalIgnoreCase))
            .OrderBy(device => device.Name, StringComparer.OrdinalIgnoreCase)
            .ToArray();
        return Task.FromResult(OperationResult<IReadOnlyList<ManagedDeviceSummary>>.Success(devices, correlationId));
    }

    public Task<OperationResult<ProviderChangeResult>> CreateUserAsync(UserCreateRequest request, CorrelationId correlationId, CancellationToken cancellationToken = default) =>
        Unsupported<ProviderChangeResult>(correlationId, "Graph.UserCreate.RequiresTask31Approval", "Graph user creation requires explicit non-production live validation.");

    public Task<OperationResult<ProviderChangeResult>> UpdateUserAttributesAsync(UserUpdateRequest request, CorrelationId correlationId, CancellationToken cancellationToken = default) =>
        Unsupported<ProviderChangeResult>(correlationId, "Graph.UserUpdate.RequiresTask31Approval", "Graph user updates require explicit non-production live validation.");

    public Task<OperationResult<ProviderChangeResult>> SetManagerAsync(ManagerChangeRequest request, CorrelationId correlationId, CancellationToken cancellationToken = default) =>
        Unsupported<ProviderChangeResult>(correlationId, "Graph.Manager.Unsupported", "Manager changes are handled by Active Directory in hybrid mode.");

    public Task<OperationResult<ProviderChangeResult>> AddGroupMembershipAsync(MembershipChangeRequest request, CorrelationId correlationId, CancellationToken cancellationToken = default) =>
        Unsupported<ProviderChangeResult>(correlationId, "Graph.GroupMembership.RequiresTask31Approval", "Graph group membership writes require explicit non-production live validation.");

    public Task<OperationResult<ProviderChangeResult>> RemoveGroupMembershipAsync(MembershipChangeRequest request, CorrelationId correlationId, CancellationToken cancellationToken = default) =>
        Unsupported<ProviderChangeResult>(correlationId, "Graph.GroupMembership.RequiresTask31Approval", "Graph group membership writes require explicit non-production live validation.");

    public Task<OperationResult<ProviderChangeResult>> SetMailboxForwardingAsync(MailboxForwardingRequest request, CorrelationId correlationId, CancellationToken cancellationToken = default) =>
        Unsupported<ProviderChangeResult>(correlationId, "Graph.MailboxForwarding.Unsupported", "Mailbox forwarding remains in the Exchange supportability gate.");

    public Task<OperationResult<ProviderChangeResult>> ResetStateAsync(CorrelationId correlationId, CancellationToken cancellationToken = default) =>
        Task.FromResult(OperationResult<ProviderChangeResult>.Success(new ProviderChangeResult { Operation = "ResetState", TargetId = "MicrosoftGraph", Changed = false, Message = "Native Graph provider has no local mutable state.", Source = "MicrosoftGraph" }, correlationId));

    private async Task<OperationResult<SimulatorUserSummary?>> FindUserAsync(string identity, CorrelationId correlationId, CancellationToken cancellationToken)
    {
        var result = await SearchUsersAsync(identity, correlationId, cancellationToken).ConfigureAwait(false);
        if (!result.Succeeded)
        {
            return OperationResult<SimulatorUserSummary?>.Failure(correlationId, result.Errors, result.Warnings, result.Status);
        }

        return OperationResult<SimulatorUserSummary?>.Success(result.Value!.FirstOrDefault(), correlationId);
    }

    private IReadOnlyList<OperationError> ValidateSession()
    {
        var errors = new List<OperationError>();
        if (!_options.ServiceAvailable) errors.Add(OperationError.Create("Graph.ServiceUnavailable", "Microsoft Graph service is unavailable."));
        if (!_options.AuthenticationSucceeded) errors.Add(OperationError.Create("Graph.AuthenticationFailed", "Microsoft Graph authentication failed."));
        if (!_options.PermissionValidationSucceeded) errors.Add(OperationError.Create("Graph.AuthorizationFailed", "Microsoft Graph permission validation failed."));
        return errors;
    }

    private static Task<OperationResult<T>> Unsupported<T>(CorrelationId correlationId, string code, string message)
    {
        return Task.FromResult(OperationResult<T>.Failure(correlationId, new[] { OperationError.Create(code, message) }, status: "Unsupported"));
    }

    private static List<SimulatorUserSummary> SeedUsers() => new()
    {
        new SimulatorUserSummary { DisplayName = "Alex Morgan", SamAccountName = "amorgan", UserPrincipalName = "amorgan@atlas-tech.com", Mail = "amorgan@atlas-tech.com", Source = "MicrosoftGraph", Enabled = true },
        new SimulatorUserSummary { DisplayName = "Zach Little ADM", SamAccountName = "zlittleadm", UserPrincipalName = "zlittleadm@atlas-tech.com", Mail = string.Empty, Source = "MicrosoftGraph", Enabled = true }
    };
}
