using System.Globalization;
using System.Net.Http.Headers;
using System.Security.Cryptography;
using System.Security.Cryptography.X509Certificates;
using System.Text;
using System.Text.Json;
using Azure.Core;
using Azure.Identity;
using HAP.Contracts;
using HAP.Providers.Abstractions;
using Microsoft.Graph;
using Microsoft.Graph.Models;
using Microsoft.Graph.Models.ODataErrors;
using HapOperationError = HAP.Contracts.OperationError;

namespace HAP.Providers.Graph;

public sealed class MicrosoftGraphProvider :
    IProviderHealthCapability,
    IUserLookupCapability,
    IGraphReadCapability,
    IDeviceReadCapability,
    IDeviceActionCapability,
    ISimulatorWriteCapability
{
    private static readonly HttpClient Http = new();
    private readonly GraphProviderOptions _options;
    private readonly List<SimulatorUserSummary> _users;
    private GraphServiceClient? _client;
    private TokenCredential? _credential;

    public MicrosoftGraphProvider(GraphProviderOptions? options = null, IReadOnlyList<SimulatorUserSummary>? users = null)
    {
        _options = options ?? new GraphProviderOptions();
        _users = users?.ToList() ?? SeedUsers();
    }

    public async Task<OperationResult<ProviderHealthResult>> GetHealthAsync(CorrelationId correlationId, CancellationToken cancellationToken = default)
    {
        var errors = ValidateSession();
        if (errors.Count > 0)
        {
            return OperationResult<ProviderHealthResult>.Failure(correlationId, errors, status: "Failed");
        }

        if (_options.UseLiveGraph)
        {
            var client = CreateClientResult(correlationId);
            if (!client.Succeeded)
            {
                return OperationResult<ProviderHealthResult>.Failure(correlationId, client.Errors, client.Warnings, client.Status);
            }

            try
            {
                _ = await client.Value!.Users.GetAsync(request =>
                {
                    request.QueryParameters.Top = 1;
                    request.QueryParameters.Select = new[] { "id" };
                }, cancellationToken).ConfigureAwait(false);
            }
            catch (Exception ex)
            {
                return OperationResult<ProviderHealthResult>.Failure(correlationId, new[] { HapOperationError.Create("Graph.Health.LiveQueryFailed", $"Microsoft Graph health query failed: {FriendlyError(ex)}") }, status: "Failed");
            }
        }

        return OperationResult<ProviderHealthResult>.Success(
            new ProviderHealthResult
            {
                ProviderId = "MicrosoftGraph",
                Mode = _options.UseLiveGraph ? $"{_options.AuthenticationMode}.Sdk.{CloudLabel()}" : _options.AuthenticationMode,
                Enabled = true,
                Required = true,
                Status = "Connected",
                Message = _options.UseLiveGraph ? "Microsoft Graph SDK client initialized." : "Native Microsoft Graph simulation provider initialized.",
                Available = true,
                Connected = true
            },
            correlationId,
            status: "Connected");
    }

    public async Task<OperationResult<string>> GetAccessTokenAsync(CorrelationId correlationId, CancellationToken cancellationToken = default)
    {
        var errors = ValidateSession();
        if (errors.Count > 0)
        {
            return OperationResult<string>.Failure(correlationId, errors, status: "Failed");
        }

        if (string.IsNullOrWhiteSpace(_options.TenantId) || string.IsNullOrWhiteSpace(_options.ClientId))
        {
            return OperationResult<string>.Failure(correlationId, new[] { HapOperationError.Create("Graph.ProfileMissing", "Tenant ID and Client ID are required for live Microsoft Graph.") }, status: "Failed");
        }

        try
        {
            var token = await CreateCredential().GetTokenAsync(new TokenRequestContext(GetScopes()), cancellationToken).ConfigureAwait(false);
            return OperationResult<string>.Success(token.Token, correlationId, status: "Loaded");
        }
        catch (Exception ex)
        {
            return OperationResult<string>.Failure(correlationId, new[] { HapOperationError.Create("Graph.TokenAcquireFailed", $"Microsoft Graph token acquisition failed: {FriendlyError(ex)}") }, status: "Failed");
        }
    }

    public async Task<OperationResult<IReadOnlyList<SimulatorUserSummary>>> SearchUsersAsync(string query, CorrelationId correlationId, CancellationToken cancellationToken = default)
    {
        var errors = ValidateSession();
        if (errors.Count > 0)
        {
            return OperationResult<IReadOnlyList<SimulatorUserSummary>>.Failure(correlationId, errors, status: "Failed");
        }

        if (string.IsNullOrWhiteSpace(query))
        {
            return OperationResult<IReadOnlyList<SimulatorUserSummary>>.Failure(correlationId, new[] { HapOperationError.Create("Graph.UserLookup.QueryRequired", "Graph user lookup query is required.") });
        }

        if (_options.UseLiveGraph)
        {
            return await SearchLiveUsersAsync(query, correlationId, cancellationToken).ConfigureAwait(false);
        }

        var clean = query.Trim();
        IReadOnlyList<SimulatorUserSummary> matches = _users
            .Where(user => user.SamAccountName.Contains(clean, StringComparison.OrdinalIgnoreCase) ||
                           user.UserPrincipalName.Contains(clean, StringComparison.OrdinalIgnoreCase) ||
                           user.DisplayName.Contains(clean, StringComparison.OrdinalIgnoreCase))
            .OrderBy(user => user.SamAccountName, StringComparer.OrdinalIgnoreCase)
            .ToArray();

        return OperationResult<IReadOnlyList<SimulatorUserSummary>>.Success(matches, correlationId);
    }

    public async Task<OperationResult<GraphProfileSummary?>> GetGraphProfileAsync(string identity, CorrelationId correlationId, CancellationToken cancellationToken = default)
    {
        if (_options.UseLiveGraph)
        {
            return await GetLiveGraphProfileAsync(identity, correlationId, cancellationToken).ConfigureAwait(false);
        }

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
            DefaultMethod = profile.Value.AuthenticationMethods.FirstOrDefault(method => !method.Equals("password", StringComparison.OrdinalIgnoreCase)) ?? "password",
            AuthenticationMethods = profile.Value.AuthenticationMethods,
            MfaRegistered = profile.Value.MfaRegistered,
            MfaCapable = profile.Value.MfaCapable,
            PasswordlessRegistered = profile.Value.AuthenticationMethods.Any(IsPasswordlessMethod),
            TemporaryAccessPassEligible = true,
            AuthenticationStrength = profile.Value.MfaCapable ? "Multifactor capable" : "Single-factor only",
            ConditionalAccessState = "Not evaluated by Graph read APIs",
            SignInRiskState = profile.Value.RiskState,
            LastSuccessfulSignInDateTime = profile.Value.LastSignInDateTime,
            PasswordLastChangedDateTime = profile.Value.PasswordLastChangedDateTime,
            Source = profile.Value.Source
        }, correlationId);
    }

    public async Task<OperationResult<IReadOnlyList<ManagedDeviceSummary>>> GetManagedDevicesAsync(string identity, CorrelationId correlationId, CancellationToken cancellationToken = default)
    {
        if (_options.UseLiveGraph)
        {
            var user = await FindLiveUserAsync(identity, correlationId, cancellationToken).ConfigureAwait(false);
            if (!user.Succeeded)
            {
                return OperationResult<IReadOnlyList<ManagedDeviceSummary>>.Failure(correlationId, user.Errors, user.Warnings, user.Status);
            }

            if (user.Value is null)
            {
                return OperationResult<IReadOnlyList<ManagedDeviceSummary>>.Success(Array.Empty<ManagedDeviceSummary>(), correlationId, status: "NotFound");
            }

            try
            {
                var devices = await CreateClient().Users[user.Value.Id].ManagedDevices.GetAsync(request =>
                {
                    request.QueryParameters.Select = new[] { "id", "deviceName", "operatingSystem", "complianceState", "userPrincipalName", "lastSyncDateTime", "azureADDeviceId" };
                    request.QueryParameters.Top = 50;
                }, cancellationToken).ConfigureAwait(false);

                return OperationResult<IReadOnlyList<ManagedDeviceSummary>>.Success(
                    devices?.Value?.Select(MapManagedDevice).OrderBy(device => device.Name, StringComparer.OrdinalIgnoreCase).ToArray() ?? Array.Empty<ManagedDeviceSummary>(),
                    correlationId,
                    status: "Loaded");
            }
            catch (Exception ex)
            {
                return OperationResult<IReadOnlyList<ManagedDeviceSummary>>.Failure(correlationId, new[] { HapOperationError.Create("Graph.ManagedDevices.LiveQueryFailed", $"Microsoft Graph managed device read failed: {FriendlyError(ex)}") }, status: "Failed");
            }
        }

        var simulatedUser = await FindUserAsync(identity, correlationId, cancellationToken).ConfigureAwait(false);
        if (!simulatedUser.Succeeded)
        {
            return OperationResult<IReadOnlyList<ManagedDeviceSummary>>.Failure(correlationId, simulatedUser.Errors, simulatedUser.Warnings, simulatedUser.Status);
        }

        IReadOnlyList<ManagedDeviceSummary> simulatedDevices = simulatedUser.Value is null ? Array.Empty<ManagedDeviceSummary>() : new[]
        {
            new ManagedDeviceSummary
            {
                Id = $"graph-device-{simulatedUser.Value.SamAccountName}-01",
                Name = $"GRAPH-{simulatedUser.Value.SamAccountName.ToUpperInvariant()}-LT01",
                OperatingSystem = "Windows",
                ComplianceState = "Compliant",
                PrimaryUser = simulatedUser.Value.UserPrincipalName,
                LastCheckInUtc = new DateTimeOffset(2026, 1, 15, 10, 0, 0, TimeSpan.Zero),
                Source = "MicrosoftGraph.DeviceManagement"
            }
        };

        return OperationResult<IReadOnlyList<ManagedDeviceSummary>>.Success(simulatedDevices, correlationId);
    }

    public async Task<OperationResult<IReadOnlyList<ManagedDeviceSummary>>> SearchDevicesAsync(string query, CorrelationId correlationId, CancellationToken cancellationToken = default)
    {
        if (string.IsNullOrWhiteSpace(query))
        {
            return OperationResult<IReadOnlyList<ManagedDeviceSummary>>.Failure(correlationId, new[] { HapOperationError.Create("Graph.DeviceLookup.QueryRequired", "Device lookup query is required.") });
        }

        if (_options.UseLiveGraph)
        {
            try
            {
                var clean = EscapeODataString(query.Trim());
                var liveDevices = await CreateClient().DeviceManagement.ManagedDevices.GetAsync(request =>
                {
                    request.QueryParameters.Select = new[] { "id", "deviceName", "operatingSystem", "complianceState", "userPrincipalName", "lastSyncDateTime", "azureADDeviceId" };
                    request.QueryParameters.Filter = $"startswith(deviceName,'{clean}')";
                    request.QueryParameters.Top = 50;
                }, cancellationToken).ConfigureAwait(false);

                return OperationResult<IReadOnlyList<ManagedDeviceSummary>>.Success(
                    liveDevices?.Value?.Select(MapManagedDevice).OrderBy(device => device.Name, StringComparer.OrdinalIgnoreCase).ToArray() ?? Array.Empty<ManagedDeviceSummary>(),
                    correlationId,
                    status: liveDevices?.Value?.Count > 0 ? "Loaded" : "NoMatches");
            }
            catch (Exception ex)
            {
                return OperationResult<IReadOnlyList<ManagedDeviceSummary>>.Failure(correlationId, new[] { HapOperationError.Create("Graph.DeviceLookup.LiveQueryFailed", $"Microsoft Graph device lookup failed: {FriendlyError(ex)}") }, status: "Failed");
            }
        }

        IReadOnlyList<ManagedDeviceSummary> devices = _users
            .Select(user => new ManagedDeviceSummary { Id = $"graph-device-{user.SamAccountName}-01", Name = $"GRAPH-{user.SamAccountName.ToUpperInvariant()}-LT01", PrimaryUser = user.UserPrincipalName, ComplianceState = "Compliant", OperatingSystem = "Windows", Source = "MicrosoftGraph.DeviceManagement" })
            .Where(device => device.Name.Contains(query, StringComparison.OrdinalIgnoreCase) || device.PrimaryUser.Contains(query, StringComparison.OrdinalIgnoreCase))
            .OrderBy(device => device.Name, StringComparer.OrdinalIgnoreCase)
            .ToArray();
        return OperationResult<IReadOnlyList<ManagedDeviceSummary>>.Success(devices, correlationId);
    }

    public async Task<OperationResult<DeviceSecretRevealResult>> RevealDeviceSecretAsync(DeviceSecretRevealRequest request, CorrelationId correlationId, CancellationToken cancellationToken = default)
    {
        if (!_options.UseLiveGraph)
        {
            var simulated = request.SecretKind == DeviceSecretKind.BitLockerRecoveryKey
                ? $"SIM-GRAPH-BL-{request.Device.Name}-000000"
                : $"SIM-GRAPH-LAPS-{request.Device.Name}!";
            return OperationResult<DeviceSecretRevealResult>.Success(new DeviceSecretRevealResult
            {
                DeviceId = request.Device.Id,
                DeviceName = request.Device.Name,
                SecretKind = request.SecretKind,
                Secret = simulated,
                Metadata = "Simulation Graph secret.",
                Source = "MicrosoftGraph.Simulation"
            }, correlationId, status: "Revealed");
        }

        try
        {
            var result = request.SecretKind == DeviceSecretKind.BitLockerRecoveryKey
                ? await RevealBitLockerKeyAsync(request.Device, cancellationToken).ConfigureAwait(false)
                : await RevealLapsPasswordAsync(request.Device, cancellationToken).ConfigureAwait(false);
            return OperationResult<DeviceSecretRevealResult>.Success(result, correlationId, status: "Revealed");
        }
        catch (Exception ex)
        {
            return OperationResult<DeviceSecretRevealResult>.Failure(correlationId, new[] { HapOperationError.Create("Graph.DeviceSecret.RevealFailed", $"Microsoft Graph secret reveal failed: {FriendlyError(ex)}") }, status: "Failed");
        }
    }

    public async Task<OperationResult<DeviceLifecycleResult>> RetireDeviceAsync(DeviceLifecycleRequest request, CorrelationId correlationId, CancellationToken cancellationToken = default)
    {
        if (request.Target is not DeviceActionTarget.Intune and not DeviceActionTarget.All)
        {
            return OperationResult<DeviceLifecycleResult>.Success(Lifecycle("RetireDevice", request.Target, false, "Retire applies to Intune managed devices only."), correlationId, status: "Skipped");
        }

        if (!_options.UseLiveGraph)
        {
            return OperationResult<DeviceLifecycleResult>.Success(Lifecycle("RetireDevice", DeviceActionTarget.Intune, true, $"Simulation retired Intune device {request.Device.Name}."), correlationId, status: "Retired");
        }

        try
        {
            await SendGraphNoContentAsync(HttpMethod.Post, $"/deviceManagement/managedDevices/{Uri.EscapeDataString(request.Device.Id)}/retire", cancellationToken).ConfigureAwait(false);
            return OperationResult<DeviceLifecycleResult>.Success(Lifecycle("RetireDevice", DeviceActionTarget.Intune, true, $"Retire requested for Intune device {request.Device.Name}."), correlationId, status: "Retired");
        }
        catch (Exception ex)
        {
            return OperationResult<DeviceLifecycleResult>.Failure(correlationId, new[] { HapOperationError.Create("Graph.Intune.RetireFailed", $"Intune retire failed: {FriendlyError(ex)}") }, status: "Failed");
        }
    }

    public async Task<OperationResult<DeviceLifecycleResult>> DeleteDeviceAsync(DeviceLifecycleRequest request, CorrelationId correlationId, CancellationToken cancellationToken = default)
    {
        if (!_options.UseLiveGraph)
        {
            return OperationResult<DeviceLifecycleResult>.Success(Lifecycle("DeleteDevice", request.Target, true, $"Simulation deleted {request.Device.Name} from {request.Target}."), correlationId, status: "Deleted");
        }

        try
        {
            if (request.Target is DeviceActionTarget.Intune or DeviceActionTarget.All)
            {
                await SendGraphNoContentAsync(HttpMethod.Delete, $"/deviceManagement/managedDevices/{Uri.EscapeDataString(request.Device.Id)}", cancellationToken).ConfigureAwait(false);
                if (request.Target == DeviceActionTarget.Intune)
                {
                    return OperationResult<DeviceLifecycleResult>.Success(Lifecycle("DeleteDevice", DeviceActionTarget.Intune, true, $"Deleted Intune managed device {request.Device.Name}."), correlationId, status: "Deleted");
                }
            }

            if (request.Target is DeviceActionTarget.EntraId or DeviceActionTarget.All)
            {
                var entraObjectId = await ResolveEntraDeviceObjectIdAsync(request.Device, cancellationToken).ConfigureAwait(false);
                await SendGraphNoContentAsync(HttpMethod.Delete, $"/devices/{Uri.EscapeDataString(entraObjectId)}", cancellationToken).ConfigureAwait(false);
                var message = request.Target == DeviceActionTarget.All
                    ? $"Deleted Intune and Entra records for {request.Device.Name}."
                    : $"Deleted Entra device {request.Device.Name}.";
                return OperationResult<DeviceLifecycleResult>.Success(Lifecycle("DeleteDevice", request.Target, true, message), correlationId, status: "Deleted");
            }

            return OperationResult<DeviceLifecycleResult>.Success(Lifecycle("DeleteDevice", request.Target, false, "Graph provider skipped non-Graph target."), correlationId, status: "Skipped");
        }
        catch (Exception ex)
        {
            return OperationResult<DeviceLifecycleResult>.Failure(correlationId, new[] { HapOperationError.Create("Graph.Device.DeleteFailed", $"Microsoft Graph device delete failed: {FriendlyError(ex)}") }, status: "Failed");
        }
    }

    public Task<OperationResult<ProviderChangeResult>> CreateUserAsync(UserCreateRequest request, CorrelationId correlationId, CancellationToken cancellationToken = default) =>
        Unsupported<ProviderChangeResult>(correlationId, "Graph.UserCreate.Unsupported", "Graph user creation is handled through Active Directory for the current hybrid workflow.");

    public Task<OperationResult<ProviderChangeResult>> UpdateUserAttributesAsync(UserUpdateRequest request, CorrelationId correlationId, CancellationToken cancellationToken = default) =>
        Unsupported<ProviderChangeResult>(correlationId, "Graph.UserUpdate.Unsupported", "Graph user updates are handled through Active Directory for the current hybrid workflow.");

    public Task<OperationResult<ProviderChangeResult>> SetManagerAsync(ManagerChangeRequest request, CorrelationId correlationId, CancellationToken cancellationToken = default) =>
        Unsupported<ProviderChangeResult>(correlationId, "Graph.Manager.Unsupported", "Manager changes are handled by Active Directory in hybrid mode.");

    public Task<OperationResult<ProviderChangeResult>> AddGroupMembershipAsync(MembershipChangeRequest request, CorrelationId correlationId, CancellationToken cancellationToken = default) =>
        Unsupported<ProviderChangeResult>(correlationId, "Graph.GroupMembership.Unsupported", "Group membership writes are handled by Active Directory in hybrid mode.");

    public Task<OperationResult<ProviderChangeResult>> RemoveGroupMembershipAsync(MembershipChangeRequest request, CorrelationId correlationId, CancellationToken cancellationToken = default) =>
        Unsupported<ProviderChangeResult>(correlationId, "Graph.GroupMembership.Unsupported", "Group membership writes are handled by Active Directory in hybrid mode.");

    public Task<OperationResult<ProviderChangeResult>> SetMailboxForwardingAsync(MailboxForwardingRequest request, CorrelationId correlationId, CancellationToken cancellationToken = default) =>
        Unsupported<ProviderChangeResult>(correlationId, "Graph.MailboxForwarding.Unsupported", "Mailbox forwarding remains in the Exchange supportability gate.");

    public Task<OperationResult<ProviderChangeResult>> SetGalVisibilityAsync(GalVisibilityRequest request, CorrelationId correlationId, CancellationToken cancellationToken = default) =>
        Unsupported<ProviderChangeResult>(correlationId, "Graph.GalVisibility.Unsupported", "GAL visibility remains in the Exchange supportability gate.");

    public Task<OperationResult<ProviderChangeResult>> AddMailboxDelegationAsync(MailboxDelegationChangeRequest request, CorrelationId correlationId, CancellationToken cancellationToken = default) =>
        Unsupported<ProviderChangeResult>(correlationId, "Graph.MailboxDelegation.Unsupported", "Mailbox delegation remains in the Exchange supportability gate.");

    public Task<OperationResult<ProviderChangeResult>> EnableRemoteMailboxAsync(MailboxProvisioningRequest request, CorrelationId correlationId, CancellationToken cancellationToken = default) =>
        Unsupported<ProviderChangeResult>(correlationId, "Graph.RemoteMailbox.Unsupported", "Remote mailbox provisioning is handled by Exchange on-premises in hybrid mode.");

    public Task<OperationResult<ProviderChangeResult>> ResetStateAsync(CorrelationId correlationId, CancellationToken cancellationToken = default) =>
        Task.FromResult(OperationResult<ProviderChangeResult>.Success(new ProviderChangeResult { Operation = "ResetState", TargetId = "MicrosoftGraph", Changed = false, Message = "Native Graph provider has no local mutable state.", Source = "MicrosoftGraph" }, correlationId));

    private async Task<OperationResult<IReadOnlyList<SimulatorUserSummary>>> SearchLiveUsersAsync(string query, CorrelationId correlationId, CancellationToken cancellationToken)
    {
        try
        {
            var clean = EscapeODataString(query.Trim());
            var users = await CreateClient().Users.GetAsync(request =>
            {
                request.QueryParameters.Top = 25;
                request.QueryParameters.Select = UserSelect;
                request.QueryParameters.Filter = $"startswith(displayName,'{clean}') or startswith(userPrincipalName,'{clean}') or startswith(mail,'{clean}') or startswith(onPremisesSamAccountName,'{clean}')";
                request.Headers.Add("ConsistencyLevel", "eventual");
            }, cancellationToken).ConfigureAwait(false);

            var matches = users?.Value?.Select(MapUser).OrderBy(user => user.SamAccountName, StringComparer.OrdinalIgnoreCase).ToArray() ?? Array.Empty<SimulatorUserSummary>();
            return OperationResult<IReadOnlyList<SimulatorUserSummary>>.Success(matches, correlationId, status: matches.Length == 0 ? "NoMatches" : "Loaded");
        }
        catch (Exception ex)
        {
            return OperationResult<IReadOnlyList<SimulatorUserSummary>>.Failure(correlationId, new[] { HapOperationError.Create("Graph.UserLookup.LiveQueryFailed", $"Microsoft Graph user lookup failed: {FriendlyError(ex)}") }, status: "Failed");
        }
    }

    private async Task<OperationResult<GraphProfileSummary?>> GetLiveGraphProfileAsync(string identity, CorrelationId correlationId, CancellationToken cancellationToken)
    {
        var userResult = await FindLiveUserAsync(identity, correlationId, cancellationToken).ConfigureAwait(false);
        if (!userResult.Succeeded)
        {
            return OperationResult<GraphProfileSummary?>.Failure(correlationId, userResult.Errors, userResult.Warnings, userResult.Status);
        }

        var user = userResult.Value;
        if (user is null)
        {
            return OperationResult<GraphProfileSummary?>.Success(null, correlationId, status: "NotFound");
        }

        try
        {
            var licenseTask = GetLicensesAsync(user.Id!, cancellationToken);
            var authTask = GetAuthenticationMethodsAsync(user.Id!, cancellationToken);
            var rolesTask = GetRoleNamesAsync(user.Id!, cancellationToken);
            var riskTask = GetRiskStateAsync(user.Id!, cancellationToken);
            await Task.WhenAll(licenseTask, authTask, rolesTask, riskTask).ConfigureAwait(false);

            var methods = authTask.Result;
            return OperationResult<GraphProfileSummary?>.Success(new GraphProfileSummary
            {
                ObjectId = user.Id ?? string.Empty,
                SamAccountName = FirstNonEmpty(user.OnPremisesSamAccountName, GetSamFromUpn(user.UserPrincipalName)),
                DisplayName = user.DisplayName ?? string.Empty,
                UserPrincipalName = user.UserPrincipalName ?? string.Empty,
                UserType = user.UserType ?? string.Empty,
                PreferredLanguage = user.PreferredLanguage ?? string.Empty,
                UsageLocation = user.UsageLocation ?? string.Empty,
                LastSignInDateTime = user.SignInActivity?.LastSignInDateTime,
                LastNonInteractiveSignInDateTime = user.SignInActivity?.LastNonInteractiveSignInDateTime,
                PasswordLastChangedDateTime = user.LastPasswordChangeDateTime,
                AuthenticationMethods = methods,
                Licenses = licenseTask.Result,
                PimRoles = rolesTask.Result,
                MfaRegistered = methods.Any(method => !method.Equals("passwordAuthenticationMethod", StringComparison.OrdinalIgnoreCase)),
                MfaCapable = methods.Any(method => !method.Equals("passwordAuthenticationMethod", StringComparison.OrdinalIgnoreCase)),
                RiskState = riskTask.Result,
                Source = "MicrosoftGraph.Sdk"
            }, correlationId, status: "Loaded");
        }
        catch (Exception ex)
        {
            return OperationResult<GraphProfileSummary?>.Failure(correlationId, new[] { HapOperationError.Create("Graph.Profile.LiveQueryFailed", $"Microsoft Graph profile read failed: {FriendlyError(ex)}") }, status: "Failed");
        }
    }

    private async Task<OperationResult<User?>> FindLiveUserAsync(string identity, CorrelationId correlationId, CancellationToken cancellationToken)
    {
        try
        {
            var clean = identity.Trim();
            if (string.IsNullOrWhiteSpace(clean))
            {
                return OperationResult<User?>.Success(null, correlationId, status: "NotFound");
            }

            if (clean.Contains('@', StringComparison.Ordinal))
            {
                var direct = await CreateClient().Users[clean].GetAsync(request =>
                {
                    request.QueryParameters.Select = UserSelect;
                }, cancellationToken).ConfigureAwait(false);
                return OperationResult<User?>.Success(direct, correlationId, status: direct is null ? "NotFound" : "Loaded");
            }

            var escaped = EscapeODataString(clean);
            var users = await CreateClient().Users.GetAsync(request =>
            {
                request.QueryParameters.Top = 1;
                request.QueryParameters.Select = UserSelect;
                request.QueryParameters.Filter = $"onPremisesSamAccountName eq '{escaped}' or mail eq '{escaped}' or userPrincipalName eq '{escaped}'";
                request.Headers.Add("ConsistencyLevel", "eventual");
            }, cancellationToken).ConfigureAwait(false);

            return OperationResult<User?>.Success(users?.Value?.FirstOrDefault(), correlationId, status: users?.Value?.Count > 0 ? "Loaded" : "NotFound");
        }
        catch (Exception ex)
        {
            return OperationResult<User?>.Failure(correlationId, new[] { HapOperationError.Create("Graph.UserRead.LiveQueryFailed", $"Microsoft Graph user read failed: {FriendlyError(ex)}") }, status: "Failed");
        }
    }

    private async Task<IReadOnlyList<LicenseAssignmentSummary>> GetLicensesAsync(string userId, CancellationToken cancellationToken)
    {
        try
        {
            var licenses = await CreateClient().Users[userId].LicenseDetails.GetAsync(request =>
            {
                request.QueryParameters.Select = new[] { "skuId", "skuPartNumber" };
            }, cancellationToken).ConfigureAwait(false);

            return licenses?.Value?.Select(item => new LicenseAssignmentSummary
            {
                SkuId = item.SkuId?.ToString() ?? string.Empty,
                SkuPartNumber = item.SkuPartNumber ?? string.Empty,
                FriendlyName = FriendlyLicenseName(item.SkuPartNumber ?? string.Empty),
                AssignmentState = "Active",
                Source = "MicrosoftGraph.Sdk"
            }).OrderBy(item => item.FriendlyName, StringComparer.OrdinalIgnoreCase).ToArray() ?? Array.Empty<LicenseAssignmentSummary>();
        }
        catch
        {
            return Array.Empty<LicenseAssignmentSummary>();
        }
    }

    private async Task<IReadOnlyList<string>> GetAuthenticationMethodsAsync(string userId, CancellationToken cancellationToken)
    {
        try
        {
            var methods = await CreateClient().Users[userId].Authentication.Methods.GetAsync(cancellationToken: cancellationToken).ConfigureAwait(false);
            return methods?.Value?
                .Select(method => FirstNonEmpty(method.OdataType?.Replace("#microsoft.graph.", string.Empty, StringComparison.OrdinalIgnoreCase) ?? string.Empty, method.GetType().Name))
                .Where(method => !string.IsNullOrWhiteSpace(method))
                .Distinct(StringComparer.OrdinalIgnoreCase)
                .OrderBy(method => method, StringComparer.OrdinalIgnoreCase)
                .ToArray() ?? Array.Empty<string>();
        }
        catch
        {
            return Array.Empty<string>();
        }
    }

    private async Task<IReadOnlyList<string>> GetRoleNamesAsync(string userId, CancellationToken cancellationToken)
    {
        var names = new List<string>();
        try
        {
            var active = await CreateClient().RoleManagement.Directory.RoleAssignmentScheduleInstances.GetAsync(request =>
            {
                request.QueryParameters.Filter = $"principalId eq '{EscapeODataString(userId)}'";
                request.QueryParameters.Expand = new[] { "roleDefinition($select=displayName)" };
                request.QueryParameters.Top = 100;
            }, cancellationToken).ConfigureAwait(false);
            names.AddRange(active?.Value?.Select(item => item.RoleDefinition?.DisplayName ?? string.Empty) ?? Array.Empty<string>());
        }
        catch
        {
        }

        try
        {
            var eligible = await CreateClient().RoleManagement.Directory.RoleEligibilityScheduleInstances.GetAsync(request =>
            {
                request.QueryParameters.Filter = $"principalId eq '{EscapeODataString(userId)}'";
                request.QueryParameters.Expand = new[] { "roleDefinition($select=displayName)" };
                request.QueryParameters.Top = 100;
            }, cancellationToken).ConfigureAwait(false);
            names.AddRange(eligible?.Value?.Select(item => item.RoleDefinition?.DisplayName ?? string.Empty) ?? Array.Empty<string>());
        }
        catch
        {
        }

        return names.Where(name => !string.IsNullOrWhiteSpace(name)).Distinct(StringComparer.OrdinalIgnoreCase).OrderBy(name => name, StringComparer.OrdinalIgnoreCase).ToArray();
    }

    private async Task<string> GetRiskStateAsync(string userId, CancellationToken cancellationToken)
    {
        try
        {
            var risk = await CreateClient().IdentityProtection.RiskyUsers[userId].GetAsync(request =>
            {
                request.QueryParameters.Select = new[] { "riskState" };
            }, cancellationToken).ConfigureAwait(false);
            return risk?.RiskState?.ToString() ?? "none";
        }
        catch
        {
            return "none";
        }
    }

    private GraphServiceClient CreateClient()
    {
        var result = CreateClientResult(CorrelationId.New());
        if (!result.Succeeded)
        {
            throw new InvalidOperationException(string.Join(" ", result.Errors.Select(error => error.Message)));
        }

        return result.Value!;
    }

    private async Task<DeviceSecretRevealResult> RevealBitLockerKeyAsync(ManagedDeviceSummary device, CancellationToken cancellationToken)
    {
        var deviceId = FirstNonEmpty(device.EntraDeviceId, device.Id);
        using var list = await SendGraphJsonAsync(HttpMethod.Get, $"/informationProtection/bitlocker/recoveryKeys?$filter=deviceId eq '{EscapeODataString(deviceId)}'&$select=id,deviceId,createdDateTime,volumeType", cancellationToken).ConfigureAwait(false);
        var first = list.RootElement.TryGetProperty("value", out var values) && values.ValueKind == JsonValueKind.Array
            ? values.EnumerateArray().FirstOrDefault()
            : default;
        var keyId = first.ValueKind == JsonValueKind.Object && first.TryGetProperty("id", out var idProperty) ? idProperty.GetString() ?? string.Empty : string.Empty;
        if (string.IsNullOrWhiteSpace(keyId))
        {
            throw new InvalidOperationException("No BitLocker recovery key was found for the selected device.");
        }

        using var key = await SendGraphJsonAsync(HttpMethod.Get, $"/informationProtection/bitlocker/recoveryKeys/{Uri.EscapeDataString(keyId)}?$select=id,key,deviceId,createdDateTime,volumeType", cancellationToken).ConfigureAwait(false);
        var secret = GetJsonString(key.RootElement, "key");
        return new DeviceSecretRevealResult
        {
            DeviceId = deviceId,
            DeviceName = device.Name,
            SecretKind = DeviceSecretKind.BitLockerRecoveryKey,
            Secret = secret,
            Metadata = $"Key id: {keyId}; Created: {GetJsonString(key.RootElement, "createdDateTime")}; Volume: {GetJsonString(key.RootElement, "volumeType")}",
            Source = "MicrosoftGraph.BitLocker"
        };
    }

    private async Task<DeviceSecretRevealResult> RevealLapsPasswordAsync(ManagedDeviceSummary device, CancellationToken cancellationToken)
    {
        var deviceId = FirstNonEmpty(device.EntraDeviceId, device.Id);
        using var document = await SendGraphJsonAsync(HttpMethod.Get, $"/directory/deviceLocalCredentials/{Uri.EscapeDataString(deviceId)}?$select=deviceName,credentials,lastBackupDateTime", cancellationToken).ConfigureAwait(false);
        var password = string.Empty;
        var account = string.Empty;
        if (document.RootElement.TryGetProperty("credentials", out var credentials) && credentials.ValueKind == JsonValueKind.Array)
        {
            var first = credentials.EnumerateArray().FirstOrDefault();
            if (first.ValueKind == JsonValueKind.Object)
            {
                account = GetJsonString(first, "accountName");
                var encoded = GetJsonString(first, "passwordBase64");
                if (!string.IsNullOrWhiteSpace(encoded))
                {
                    password = Encoding.UTF8.GetString(Convert.FromBase64String(encoded));
                }
            }
        }

        if (string.IsNullOrWhiteSpace(password))
        {
            throw new InvalidOperationException("No LAPS password was returned for the selected device.");
        }

        return new DeviceSecretRevealResult
        {
            DeviceId = deviceId,
            DeviceName = device.Name,
            SecretKind = DeviceSecretKind.LapsPassword,
            Secret = password,
            Metadata = $"Account: {account}; Last backup: {GetJsonString(document.RootElement, "lastBackupDateTime")}",
            Source = "MicrosoftGraph.LAPS"
        };
    }

    private async Task<JsonDocument> SendGraphJsonAsync(HttpMethod method, string path, CancellationToken cancellationToken)
    {
        using var response = await SendGraphAsync(method, path, cancellationToken).ConfigureAwait(false);
        var content = await response.Content.ReadAsStringAsync(cancellationToken).ConfigureAwait(false);
        if (!response.IsSuccessStatusCode)
        {
            throw new InvalidOperationException($"{(int)response.StatusCode} {response.ReasonPhrase}: {content}");
        }

        return JsonDocument.Parse(string.IsNullOrWhiteSpace(content) ? "{}" : content);
    }

    private async Task SendGraphNoContentAsync(HttpMethod method, string path, CancellationToken cancellationToken)
    {
        using var response = await SendGraphAsync(method, path, cancellationToken).ConfigureAwait(false);
        var content = await response.Content.ReadAsStringAsync(cancellationToken).ConfigureAwait(false);
        if (!response.IsSuccessStatusCode)
        {
            throw new InvalidOperationException($"{(int)response.StatusCode} {response.ReasonPhrase}: {content}");
        }
    }

    private async Task<string> ResolveEntraDeviceObjectIdAsync(ManagedDeviceSummary device, CancellationToken cancellationToken)
    {
        if (!string.IsNullOrWhiteSpace(device.EntraDeviceId))
        {
            using var byDeviceId = await SendGraphJsonAsync(HttpMethod.Get, $"/devices?$filter=deviceId eq '{EscapeODataString(device.EntraDeviceId)}'&$select=id,deviceId,displayName", cancellationToken).ConfigureAwait(false);
            var resolved = FirstValueId(byDeviceId.RootElement);
            if (!string.IsNullOrWhiteSpace(resolved))
            {
                return resolved;
            }
        }

        using var byName = await SendGraphJsonAsync(HttpMethod.Get, $"/devices?$filter=displayName eq '{EscapeODataString(device.Name)}'&$select=id,deviceId,displayName", cancellationToken).ConfigureAwait(false);
        var named = FirstValueId(byName.RootElement);
        if (!string.IsNullOrWhiteSpace(named))
        {
            return named;
        }

        throw new InvalidOperationException("Unable to resolve the Entra device object ID for the selected device.");
    }

    private static string FirstValueId(JsonElement root)
    {
        if (root.TryGetProperty("value", out var values) && values.ValueKind == JsonValueKind.Array)
        {
            var first = values.EnumerateArray().FirstOrDefault();
            if (first.ValueKind == JsonValueKind.Object)
            {
                return GetJsonString(first, "id");
            }
        }

        return string.Empty;
    }

    private async Task<HttpResponseMessage> SendGraphAsync(HttpMethod method, string path, CancellationToken cancellationToken)
    {
        var credential = CreateCredential();
        var token = await credential.GetTokenAsync(new TokenRequestContext(GetScopes()), cancellationToken).ConfigureAwait(false);
        using var request = new HttpRequestMessage(method, $"{GetGraphBaseUrl()}{path}");
        request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", token.Token);
        request.Headers.Accept.Add(new MediaTypeWithQualityHeaderValue("application/json"));
        request.Headers.TryAddWithoutValidation("ConsistencyLevel", "eventual");
        return await Http.SendAsync(request, cancellationToken).ConfigureAwait(false);
    }

    private static DeviceLifecycleResult Lifecycle(string operation, DeviceActionTarget target, bool changed, string message)
    {
        return new DeviceLifecycleResult
        {
            Operation = operation,
            Target = target.ToString(),
            Changed = changed,
            Message = message,
            Source = "MicrosoftGraph.Sdk"
        };
    }

    private OperationResult<GraphServiceClient> CreateClientResult(CorrelationId correlationId)
    {
        if (_client is not null)
        {
            return OperationResult<GraphServiceClient>.Success(_client, correlationId, status: "Cached");
        }

        if (string.IsNullOrWhiteSpace(_options.TenantId) || string.IsNullOrWhiteSpace(_options.ClientId))
        {
            return OperationResult<GraphServiceClient>.Failure(correlationId, new[] { HapOperationError.Create("Graph.ProfileMissing", "Tenant ID and Client ID are required for live Microsoft Graph.") }, status: "Failed");
        }

        try
        {
            var credential = CreateCredential();
            _client = new GraphServiceClient(credential, GetScopes());
            _client.RequestAdapter.BaseUrl = GetGraphBaseUrl();
            return OperationResult<GraphServiceClient>.Success(_client, correlationId, status: "Created");
        }
        catch (Exception ex)
        {
            return OperationResult<GraphServiceClient>.Failure(correlationId, new[] { HapOperationError.Create("Graph.ClientCreateFailed", $"Microsoft Graph SDK client creation failed: {FriendlyError(ex)}") }, status: "Failed");
        }
    }

    private TokenCredential CreateCredential()
    {
        if (_credential is not null)
        {
            return _credential;
        }

        if (_options.AuthenticationMode.Equals("Delegated", StringComparison.OrdinalIgnoreCase))
        {
            _credential = new SinglePromptTokenCredential(new InteractiveBrowserCredential(new InteractiveBrowserCredentialOptions
            {
                TenantId = _options.TenantId,
                ClientId = _options.ClientId,
                AuthorityHost = AuthorityHost(),
                RedirectUri = new Uri("http://localhost"),
                TokenCachePersistenceOptions = new TokenCachePersistenceOptions
                {
                    Name = BuildTokenCacheName()
                }
            }));
            return _credential;
        }

        if (_options.CredentialMode.Equals("SecretReference", StringComparison.OrdinalIgnoreCase) && !string.IsNullOrWhiteSpace(_options.ClientSecret))
        {
            _credential = new ClientSecretCredential(_options.TenantId, _options.ClientId, _options.ClientSecret, new ClientSecretCredentialOptions { AuthorityHost = AuthorityHost() });
            return _credential;
        }

        _credential = new ClientCertificateCredential(_options.TenantId, _options.ClientId, FindCertificate(), new ClientCertificateCredentialOptions { AuthorityHost = AuthorityHost() });
        return _credential;
    }

    private X509Certificate2 FindCertificate()
    {
        if (!string.IsNullOrWhiteSpace(_options.CertificatePath))
        {
            return new X509Certificate2(_options.CertificatePath, (string?)null, X509KeyStorageFlags.MachineKeySet | X509KeyStorageFlags.EphemeralKeySet);
        }

        var thumbprint = NormalizeThumbprint(_options.CertificateThumbprint);
        if (string.IsNullOrWhiteSpace(thumbprint))
        {
            throw new InvalidOperationException("Certificate thumbprint or certificate path is required for app-only certificate authentication.");
        }

        foreach (var location in new[] { StoreLocation.CurrentUser, StoreLocation.LocalMachine })
        {
            using var store = new X509Store(StoreName.My, location);
            store.Open(OpenFlags.ReadOnly);
            var match = store.Certificates.Find(X509FindType.FindByThumbprint, thumbprint, validOnly: false).OfType<X509Certificate2>().FirstOrDefault();
            if (match is not null)
            {
                return match;
            }
        }

        throw new InvalidOperationException($"Certificate thumbprint {thumbprint} was not found in CurrentUser or LocalMachine personal stores.");
    }

    private string[] GetScopes()
    {
        if (_options.Scopes.Count > 0)
        {
            return _options.Scopes.ToArray();
        }

        return new[] { $"{GetGraphResource().TrimEnd('/')}/.default" };
    }

    private string BuildTokenCacheName()
    {
        var cacheKey = $"{_options.CloudEnvironment}|{_options.TenantId}|{_options.ClientId}";
        var hash = Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(cacheKey)))[..16];
        return $"HAP.Graph.{hash}";
    }

    private sealed class SinglePromptTokenCredential : TokenCredential
    {
        private static readonly TimeSpan RefreshWindow = TimeSpan.FromMinutes(5);
        private readonly TokenCredential _inner;
        private readonly SemaphoreSlim _gate = new(1, 1);
        private readonly Dictionary<string, AccessToken> _tokens = new(StringComparer.Ordinal);

        public SinglePromptTokenCredential(TokenCredential inner)
        {
            _inner = inner;
        }

        public override AccessToken GetToken(TokenRequestContext requestContext, CancellationToken cancellationToken)
        {
            var key = CacheKey(requestContext);
            _gate.Wait(cancellationToken);
            try
            {
                if (TryGetUsableToken(key, out var token))
                {
                    return token;
                }

                token = _inner.GetToken(requestContext, cancellationToken);
                _tokens[key] = token;
                return token;
            }
            finally
            {
                _gate.Release();
            }
        }

        public override async ValueTask<AccessToken> GetTokenAsync(TokenRequestContext requestContext, CancellationToken cancellationToken)
        {
            var key = CacheKey(requestContext);
            await _gate.WaitAsync(cancellationToken).ConfigureAwait(false);
            try
            {
                if (TryGetUsableToken(key, out var token))
                {
                    return token;
                }

                token = await _inner.GetTokenAsync(requestContext, cancellationToken).ConfigureAwait(false);
                _tokens[key] = token;
                return token;
            }
            finally
            {
                _gate.Release();
            }
        }

        private bool TryGetUsableToken(string key, out AccessToken token)
        {
            if (_tokens.TryGetValue(key, out token) && token.ExpiresOn > DateTimeOffset.UtcNow.Add(RefreshWindow))
            {
                return true;
            }

            token = default;
            return false;
        }

        private static string CacheKey(TokenRequestContext requestContext)
        {
            return string.Join(" ", requestContext.Scopes.OrderBy(scope => scope, StringComparer.OrdinalIgnoreCase));
        }
    }

    private Uri AuthorityHost()
    {
        return IsGovernmentCloud()
            ? AzureAuthorityHosts.AzureGovernment
            : AzureAuthorityHosts.AzurePublicCloud;
    }

    private string GetGraphResource()
    {
        return IsGovernmentCloud() ? "https://graph.microsoft.us" : "https://graph.microsoft.com";
    }

    private string GetGraphBaseUrl()
    {
        return $"{GetGraphResource()}/v1.0";
    }

    private bool IsGovernmentCloud()
    {
        var cloud = _options.CloudEnvironment ?? string.Empty;
        return cloud.Contains("GCC High", StringComparison.OrdinalIgnoreCase)
            || cloud.Contains("GCCHigh", StringComparison.OrdinalIgnoreCase)
            || cloud.Contains("DoD", StringComparison.OrdinalIgnoreCase);
    }

    private string CloudLabel()
    {
        return IsGovernmentCloud() ? "USGov" : "Global";
    }

    private async Task<OperationResult<SimulatorUserSummary?>> FindUserAsync(string identity, CorrelationId correlationId, CancellationToken cancellationToken)
    {
        var result = await SearchUsersAsync(identity, correlationId, cancellationToken).ConfigureAwait(false);
        if (!result.Succeeded)
        {
            return OperationResult<SimulatorUserSummary?>.Failure(correlationId, result.Errors, result.Warnings, result.Status);
        }

        return OperationResult<SimulatorUserSummary?>.Success(result.Value!.FirstOrDefault(), correlationId);
    }

    private IReadOnlyList<HapOperationError> ValidateSession()
    {
        var errors = new List<HapOperationError>();
        if (!_options.ServiceAvailable) errors.Add(HapOperationError.Create("Graph.ServiceUnavailable", "Microsoft Graph service is unavailable."));
        if (!_options.AuthenticationSucceeded) errors.Add(HapOperationError.Create("Graph.AuthenticationFailed", "Microsoft Graph authentication failed."));
        if (!_options.PermissionValidationSucceeded) errors.Add(HapOperationError.Create("Graph.AuthorizationFailed", "Microsoft Graph permission validation failed."));
        return errors;
    }

    private static Task<OperationResult<T>> Unsupported<T>(CorrelationId correlationId, string code, string message)
    {
        return Task.FromResult(OperationResult<T>.Failure(correlationId, new[] { HapOperationError.Create(code, message) }, status: "Unsupported"));
    }

    private SimulatorUserSummary MapUser(User user)
    {
        return new SimulatorUserSummary
        {
            DisplayName = user.DisplayName ?? string.Empty,
            GivenName = user.GivenName ?? string.Empty,
            Surname = user.Surname ?? string.Empty,
            SamAccountName = FirstNonEmpty(user.OnPremisesSamAccountName, GetSamFromUpn(user.UserPrincipalName)),
            UserPrincipalName = user.UserPrincipalName ?? string.Empty,
            Mail = user.Mail ?? string.Empty,
            Department = user.Department ?? string.Empty,
            Title = user.JobTitle ?? string.Empty,
            Company = user.CompanyName ?? string.Empty,
            Office = user.OfficeLocation ?? string.Empty,
            EmployeeId = user.EmployeeId ?? string.Empty,
            Enabled = user.AccountEnabled == true,
            Source = _options.UseLiveGraph ? "MicrosoftGraph.Sdk" : "MicrosoftGraph"
        };
    }

    private static ManagedDeviceSummary MapManagedDevice(ManagedDevice device)
    {
        return new ManagedDeviceSummary
        {
            Id = device.Id ?? string.Empty,
            EntraDeviceId = device.AzureADDeviceId ?? string.Empty,
            ActiveDirectoryIdentity = device.DeviceName ?? string.Empty,
            Name = device.DeviceName ?? string.Empty,
            OperatingSystem = device.OperatingSystem ?? string.Empty,
            ComplianceState = device.ComplianceState?.ToString() ?? string.Empty,
            PrimaryUser = device.UserPrincipalName ?? string.Empty,
            LastCheckInUtc = device.LastSyncDateTime,
            Source = "MicrosoftGraph.Intune"
        };
    }

    private static List<SimulatorUserSummary> SeedUsers() => new()
    {
        new SimulatorUserSummary { DisplayName = "Alex Morgan", SamAccountName = "amorgan", UserPrincipalName = "amorgan@littleinnovation.tech", Mail = "amorgan@littleinnovation.tech", Source = "MicrosoftGraph", Enabled = true },
        new SimulatorUserSummary { DisplayName = "Zach Little ADM", SamAccountName = "zlittleadm", UserPrincipalName = "zlittleadm@littleinnovation.tech", Mail = string.Empty, Source = "MicrosoftGraph", Enabled = true }
    };

    private static readonly string[] UserSelect =
    {
        "id", "displayName", "userPrincipalName", "mail", "onPremisesSamAccountName",
        "givenName", "surname", "department", "jobTitle", "companyName", "officeLocation",
        "employeeId", "accountEnabled", "userType", "preferredLanguage", "usageLocation",
        "lastPasswordChangeDateTime", "signInActivity"
    };

    private static string EscapeODataString(string value) => (value ?? string.Empty).Replace("'", "''", StringComparison.Ordinal);

    private static string NormalizeThumbprint(string value) => new((value ?? string.Empty).Where(Uri.IsHexDigit).Select(char.ToUpperInvariant).ToArray());

    private static string GetSamFromUpn(string? upn)
    {
        var value = upn ?? string.Empty;
        var at = value.IndexOf('@', StringComparison.Ordinal);
        return at > 0 ? value[..at] : value;
    }

    private static string FirstNonEmpty(params string?[] values) => values.FirstOrDefault(value => !string.IsNullOrWhiteSpace(value)) ?? string.Empty;

    private static string GetJsonString(JsonElement element, string propertyName)
    {
        return element.ValueKind == JsonValueKind.Object &&
               element.TryGetProperty(propertyName, out var value) &&
               value.ValueKind != JsonValueKind.Null
            ? value.ToString() ?? string.Empty
            : string.Empty;
    }

    private static bool IsPasswordlessMethod(string method)
    {
        return method.Contains("fido", StringComparison.OrdinalIgnoreCase)
            || method.Contains("windowsHello", StringComparison.OrdinalIgnoreCase)
            || method.Contains("temporaryAccessPass", StringComparison.OrdinalIgnoreCase);
    }

    private static string FriendlyLicenseName(string skuPartNumber)
    {
        return skuPartNumber.ToUpperInvariant() switch
        {
            "ENTERPRISEPACK" => "Microsoft 365 E3",
            "SPE_E3" => "Microsoft 365 E3",
            "SPE_E5" => "Microsoft 365 E5",
            "ENTERPRISEPREMIUM" => "Office 365 E5",
            "VISIOCLIENT" => "Visio Plan 2",
            "PROJECTPROFESSIONAL" => "Project Plan 3",
            "EMSPREMIUM" => "Enterprise Mobility + Security E5",
            "EMS" => "Enterprise Mobility + Security E3",
            _ => skuPartNumber
        };
    }

    private static string FriendlyError(Exception ex)
    {
        return ex is ODataError odata
            ? FirstNonEmpty(odata.Error?.Message, odata.Message)
            : ex.Message;
    }
}
