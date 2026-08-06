using HAP.Contracts;
using HAP.Providers.Abstractions;
using System.Security.Cryptography;
using System.Text;

namespace HAP.Providers.Simulator;

public sealed class DirectorySimulatorProvider :
    IProviderHealthCapability,
    IUserLookupCapability,
    IDirectoryReadCapability,
    IDirectoryAttributeReadCapability,
    IDeviceReadCapability,
    IGraphReadCapability,
    IExchangeReadCapability,
    IConfigurationPreviewCapability,
    IReportingReadCapability,
    ISimulatorWriteCapability
{
    public static ProviderDescriptor Descriptor { get; } = ProviderDescriptor.Create(
        "DirectorySimulator",
        "Directory Simulator",
        "HAP",
        "1.0.0",
        "1.0",
        ProviderImplementationKind.Native,
        new[]
        {
            ProviderCapability.Create(ProviderCapabilityIds.ProviderHealth, "Provider health"),
            ProviderCapability.Create(ProviderCapabilityIds.UserLookup, "User lookup"),
            ProviderCapability.Create(ProviderCapabilityIds.GroupMembership, "Group membership"),
            ProviderCapability.Create(ProviderCapabilityIds.DeviceLookup, "Device lookup"),
            ProviderCapability.Create(ProviderCapabilityIds.LicenseAssignment, "License assignment"),
            ProviderCapability.Create(ProviderCapabilityIds.Reporting, "Reporting"),
            ProviderCapability.Create(ProviderCapabilityIds.SecurityRead, "Security read"),
            ProviderCapability.Create(ProviderCapabilityIds.UserProvisioning, "User provisioning"),
            ProviderCapability.Create(ProviderCapabilityIds.UserUpdate, "User update")
        });

    private readonly DirectorySimulatorOptions _options;
    private readonly SemaphoreSlim _stateLock = new(1, 1);
    private List<SimulatorUserSummary> _users;
    private Dictionary<string, List<ManagedDeviceSummary>> _devices;
    private Dictionary<string, MailboxSummary> _mailboxes;
    private Dictionary<string, List<MailboxDelegationSummary>> _mailboxDelegations;

    public DirectorySimulatorProvider(DirectorySimulatorOptions? options = null)
        : this(options, DirectorySimulatorSeedData.Users)
    {
    }

    public DirectorySimulatorProvider(
        DirectorySimulatorOptions? options,
        IReadOnlyList<SimulatorUserSummary> users)
    {
        _options = options ?? new DirectorySimulatorOptions();
        _users = users.ToList();
        _devices = CreateSeedDevices(_users);
        _mailboxes = CreateSeedMailboxes(_users);
        _mailboxDelegations = CreateSeedMailboxDelegations(_mailboxes);
    }

    public async Task<OperationResult<ProviderHealthResult>> GetHealthAsync(
        CorrelationId correlationId,
        CancellationToken cancellationToken = default)
    {
        var validation = await ValidateReadyAsync(correlationId, cancellationToken).ConfigureAwait(false);
        if (validation is not null)
        {
            return OperationResult<ProviderHealthResult>.Failure(correlationId, validation);
        }

        return OperationResult<ProviderHealthResult>.Success(
            new ProviderHealthResult
            {
                ProviderId = "DirectorySimulator",
                Mode = "Simulation",
                Enabled = _options.Enabled,
                Required = _options.Required,
                Status = "Connected",
                Message = "Directory Simulator initialized.",
                Available = true,
                Connected = true,
                LastError = string.Empty
            },
            correlationId,
            status: "Connected");
    }

    public async Task<OperationResult<IReadOnlyList<SimulatorUserSummary>>> SearchUsersAsync(
        string query,
        CorrelationId correlationId,
        CancellationToken cancellationToken = default)
    {
        var validation = await ValidateReadyAsync(correlationId, cancellationToken).ConfigureAwait(false);
        if (validation is not null)
        {
            return OperationResult<IReadOnlyList<SimulatorUserSummary>>.Failure(correlationId, validation);
        }

        if (string.IsNullOrWhiteSpace(query))
        {
            return OperationResult<IReadOnlyList<SimulatorUserSummary>>.Failure(
                correlationId,
                new[] { OperationError.Create("Simulator.UserLookup.QueryRequired", "User lookup query is required.") });
        }

        if (_options.SimulatedDelayMilliseconds > 0)
        {
            try
            {
                using var timeout = new CancellationTokenSource(_options.TimeoutMilliseconds);
                using var linked = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken, timeout.Token);
                await Task.Delay(_options.SimulatedDelayMilliseconds, linked.Token).ConfigureAwait(false);
            }
            catch (OperationCanceledException) when (!cancellationToken.IsCancellationRequested)
            {
                return OperationResult<IReadOnlyList<SimulatorUserSummary>>.Failure(
                    correlationId,
                    new[] { OperationError.Create("Simulator.OperationTimeout", "Directory Simulator operation timed out.") },
                    status: "TimedOut");
            }
        }

        if (cancellationToken.IsCancellationRequested)
        {
            return Cancelled<IReadOnlyList<SimulatorUserSummary>>(correlationId);
        }

        var warnings = new List<OperationWarning>();
        var matches = FindSeededUsers(query).ToArray();
        if (_options.IncludePartialFixture && IsPartialQuery(query))
        {
            warnings.Add(OperationWarning.Create("Simulator.UserLookup.PartialUserData", "Simulator user record is missing optional fields."));
            return OperationResult<IReadOnlyList<SimulatorUserSummary>>.Success(
                new[] { DirectorySimulatorSeedData.PartialUser },
                correlationId,
                warnings);
        }

        if (matches.Length > 1)
        {
            warnings.Add(OperationWarning.Create("Simulator.UserLookup.MultipleMatches", "Multiple simulator users matched the query; results were returned in deterministic order."));
        }

        if (matches.Length == 0 && _options.AllowGeneratedFallbackUsers)
        {
            warnings.Add(OperationWarning.Create("Simulator.UserGenerated", "No seeded simulator user matched the query; a deterministic fallback user was generated."));
            matches = new[] { CreateGeneratedUser(query) };
        }

        return OperationResult<IReadOnlyList<SimulatorUserSummary>>.Success(
            matches.OrderBy(user => user.SamAccountName, StringComparer.OrdinalIgnoreCase).ToArray(),
            correlationId,
            warnings);
    }

    public async Task<OperationResult<SimulatorUserSummary?>> GetUserAsync(
        string identity,
        CorrelationId correlationId,
        CancellationToken cancellationToken = default)
    {
        var search = await SearchUsersAsync(identity, correlationId, cancellationToken).ConfigureAwait(false);
        if (!search.Succeeded)
        {
            return OperationResult<SimulatorUserSummary?>.Failure(correlationId, search.Errors, search.Warnings, search.Status);
        }

        return OperationResult<SimulatorUserSummary?>.Success(search.Value!.FirstOrDefault(), correlationId, search.Warnings, search.Status);
    }

    public async Task<OperationResult<SimulatorUserSummary?>> GetManagerAsync(
        string identity,
        CorrelationId correlationId,
        CancellationToken cancellationToken = default)
    {
        var userResult = await GetUserAsync(identity, correlationId, cancellationToken).ConfigureAwait(false);
        if (!userResult.Succeeded)
        {
            return userResult;
        }

        var managerSam = userResult.Value?.ManagerSamAccountName ?? string.Empty;
        if (string.IsNullOrWhiteSpace(managerSam))
        {
            return OperationResult<SimulatorUserSummary?>.Success(null, correlationId, status: "NoManager");
        }

        return await GetUserAsync(managerSam, correlationId, cancellationToken).ConfigureAwait(false);
    }

    public async Task<OperationResult<IReadOnlyList<DirectoryGroupSummary>>> GetGroupsAsync(
        string identity,
        CorrelationId correlationId,
        CancellationToken cancellationToken = default)
    {
        var userResult = await GetUserAsync(identity, correlationId, cancellationToken).ConfigureAwait(false);
        if (!userResult.Succeeded)
        {
            return OperationResult<IReadOnlyList<DirectoryGroupSummary>>.Failure(correlationId, userResult.Errors, userResult.Warnings, userResult.Status);
        }

        var groups = userResult.Value?.Groups
            .Distinct(StringComparer.OrdinalIgnoreCase)
            .OrderBy(group => group, StringComparer.OrdinalIgnoreCase)
            .Select(group => new DirectoryGroupSummary
            {
                Id = StableId(group),
                DisplayName = group,
                Mail = group.StartsWith("DL-", StringComparison.OrdinalIgnoreCase) ? $"{group.ToLowerInvariant()}@atlas-tech.com" : string.Empty,
                SecurityIdentifier = $"S-1-5-21-SIM-{StableNumber(group):000000}",
                Source = "DirectorySimulator.ActiveDirectory"
            })
            .ToArray() ?? Array.Empty<DirectoryGroupSummary>();

        return OperationResult<IReadOnlyList<DirectoryGroupSummary>>.Success(groups, correlationId);
    }

    public async Task<OperationResult<IReadOnlyList<DirectoryGroupSummary>>> SearchGroupsAsync(
        string query,
        CorrelationId correlationId,
        CancellationToken cancellationToken = default)
    {
        var validation = await ValidateReadyAsync(correlationId, cancellationToken).ConfigureAwait(false);
        if (validation is not null)
        {
            return OperationResult<IReadOnlyList<DirectoryGroupSummary>>.Failure(correlationId, validation);
        }

        if (string.IsNullOrWhiteSpace(query))
        {
            return OperationResult<IReadOnlyList<DirectoryGroupSummary>>.Failure(
                correlationId,
                new[] { OperationError.Create("Simulator.GroupLookup.QueryRequired", "Group lookup query is required.") });
        }

        var groups = _users
            .SelectMany(user => user.Groups)
            .Distinct(StringComparer.OrdinalIgnoreCase)
            .Where(group => group.Contains(query.Trim(), StringComparison.OrdinalIgnoreCase))
            .OrderBy(group => group, StringComparer.OrdinalIgnoreCase)
            .Select(group => new DirectoryGroupSummary
            {
                Id = StableId(group),
                DisplayName = group,
                Mail = group.StartsWith("DL-", StringComparison.OrdinalIgnoreCase) ? $"{group.ToLowerInvariant()}@atlas-tech.com" : string.Empty,
                SecurityIdentifier = $"S-1-5-21-SIM-{StableNumber(group):000000}",
                Source = "DirectorySimulator.ActiveDirectory"
            })
            .ToArray();

        return OperationResult<IReadOnlyList<DirectoryGroupSummary>>.Success(groups, correlationId, status: groups.Length == 0 ? "NoMatches" : "Found");
    }

    public async Task<OperationResult<IReadOnlyList<SimulatorUserSummary>>> GetDirectReportsAsync(
        string identity,
        CorrelationId correlationId,
        CancellationToken cancellationToken = default)
    {
        var userResult = await GetUserAsync(identity, correlationId, cancellationToken).ConfigureAwait(false);
        if (!userResult.Succeeded)
        {
            return OperationResult<IReadOnlyList<SimulatorUserSummary>>.Failure(correlationId, userResult.Errors, userResult.Warnings, userResult.Status);
        }

        var reportSams = userResult.Value?.DirectReportSamAccountNames ?? Array.Empty<string>();
        var reports = _users
            .Where(user => reportSams.Contains(user.SamAccountName, StringComparer.OrdinalIgnoreCase))
            .OrderBy(user => user.SamAccountName, StringComparer.OrdinalIgnoreCase)
            .ToArray();

        return OperationResult<IReadOnlyList<SimulatorUserSummary>>.Success(reports, correlationId);
    }

    public async Task<OperationResult<DirectoryObjectAttributeSet>> GetDirectoryAttributesAsync(
        string identity,
        CorrelationId correlationId,
        CancellationToken cancellationToken = default)
    {
        var userResult = await GetUserAsync(identity, correlationId, cancellationToken).ConfigureAwait(false);
        if (!userResult.Succeeded)
        {
            return OperationResult<DirectoryObjectAttributeSet>.Failure(correlationId, userResult.Errors, userResult.Warnings, userResult.Status);
        }

        if (userResult.Value is null)
        {
            return OperationResult<DirectoryObjectAttributeSet>.Failure(
                correlationId,
                new[] { OperationError.Create("Simulator.DirectoryAttributes.NotFound", "User was not found.") },
                status: "NotFound");
        }

        var user = userResult.Value;
        return OperationResult<DirectoryObjectAttributeSet>.Success(
            new DirectoryObjectAttributeSet
            {
                Identity = user.SamAccountName,
                DistinguishedName = user.DistinguishedName,
                ObjectClass = "user",
                SchemaSource = "DirectorySimulator.LatestAdExchangeBaseline",
                Attributes = BuildDirectoryAttributes(user)
            },
            correlationId,
            status: "Loaded");
    }

    public async Task<OperationResult<IReadOnlyList<ManagedDeviceSummary>>> GetManagedDevicesAsync(
        string identity,
        CorrelationId correlationId,
        CancellationToken cancellationToken = default)
    {
        var validation = await ValidateReadyAsync(correlationId, cancellationToken).ConfigureAwait(false);
        if (validation is not null)
        {
            return OperationResult<IReadOnlyList<ManagedDeviceSummary>>.Failure(correlationId, validation);
        }

        var user = FindSeededUsers(identity).FirstOrDefault() ?? CreateGeneratedUser(identity);
        var devices = _devices.TryGetValue(user.SamAccountName, out var seeded)
            ? seeded
            : CreateGeneratedDevices(user).ToList();

        return OperationResult<IReadOnlyList<ManagedDeviceSummary>>.Success(
            devices.OrderBy(device => device.Name, StringComparer.OrdinalIgnoreCase).ToArray(),
            correlationId);
    }

    public async Task<OperationResult<IReadOnlyList<ManagedDeviceSummary>>> SearchDevicesAsync(
        string query,
        CorrelationId correlationId,
        CancellationToken cancellationToken = default)
    {
        var validation = await ValidateReadyAsync(correlationId, cancellationToken).ConfigureAwait(false);
        if (validation is not null)
        {
            return OperationResult<IReadOnlyList<ManagedDeviceSummary>>.Failure(correlationId, validation);
        }

        if (string.IsNullOrWhiteSpace(query))
        {
            return OperationResult<IReadOnlyList<ManagedDeviceSummary>>.Failure(
                correlationId,
                new[] { OperationError.Create("Simulator.DeviceLookup.QueryRequired", "Device lookup query is required.") });
        }

        var needle = query.Trim();
        var devices = _devices.Values
            .SelectMany(value => value)
            .Where(device =>
                device.Name.Contains(needle, StringComparison.OrdinalIgnoreCase) ||
                device.Id.Contains(needle, StringComparison.OrdinalIgnoreCase) ||
                device.PrimaryUser.Contains(needle, StringComparison.OrdinalIgnoreCase))
            .OrderBy(device => device.Name, StringComparer.OrdinalIgnoreCase)
            .ToArray();

        return OperationResult<IReadOnlyList<ManagedDeviceSummary>>.Success(devices, correlationId);
    }

    public async Task<OperationResult<GraphProfileSummary?>> GetGraphProfileAsync(
        string identity,
        CorrelationId correlationId,
        CancellationToken cancellationToken = default)
    {
        var userResult = await GetUserAsync(identity, correlationId, cancellationToken).ConfigureAwait(false);
        if (!userResult.Succeeded)
        {
            return OperationResult<GraphProfileSummary?>.Failure(correlationId, userResult.Errors, userResult.Warnings, userResult.Status);
        }

        var user = userResult.Value;
        if (user is null)
        {
            return OperationResult<GraphProfileSummary?>.Success(null, correlationId, status: "NotFound");
        }

        var methods = GetMethods(user.SamAccountName);
        var profile = new GraphProfileSummary
        {
            ObjectId = StableId(user.UserPrincipalName),
            SamAccountName = user.SamAccountName,
            DisplayName = user.DisplayName,
            UserPrincipalName = user.UserPrincipalName,
            UserType = "Member",
            PreferredLanguage = "en-US",
            UsageLocation = "US",
            LastSignInDateTime = StableDate(user.SamAccountName, 5, 13),
            LastNonInteractiveSignInDateTime = StableDate(user.SamAccountName, 6, 4),
            PasswordLastChangedDateTime = StableDate(user.UserPrincipalName, 90, 9),
            AuthenticationMethods = methods,
            Licenses = GetLicenses(user).ToArray(),
            PimRoles = GetPimRoles(user).ToArray(),
            MfaRegistered = methods.Any(method => method != "password"),
            MfaCapable = methods.Any(method => method != "password"),
            RiskState = "none",
            Source = "DirectorySimulator.MicrosoftGraph"
        };

        return OperationResult<GraphProfileSummary?>.Success(profile, correlationId);
    }

    public async Task<OperationResult<AuthenticationPostureSummary?>> GetAuthenticationPostureAsync(
        string identity,
        CorrelationId correlationId,
        CancellationToken cancellationToken = default)
    {
        var graphResult = await GetGraphProfileAsync(identity, correlationId, cancellationToken).ConfigureAwait(false);
        if (!graphResult.Succeeded)
        {
            return OperationResult<AuthenticationPostureSummary?>.Failure(correlationId, graphResult.Errors, graphResult.Warnings, graphResult.Status);
        }

        var profile = graphResult.Value;
        if (profile is null)
        {
            return OperationResult<AuthenticationPostureSummary?>.Success(null, correlationId, status: "NotFound");
        }

        var strongMethodCount = profile.AuthenticationMethods.Count(method => method is not "password" and not "sms" and not "voiceMobile");
        var mfaMethodCount = profile.AuthenticationMethods.Count(method => method != "password");
        var passwordlessMethodCount = profile.AuthenticationMethods.Count(method => method is "fido2SecurityKey" or "windowsHelloForBusiness" or "temporaryAccessPass");

        return OperationResult<AuthenticationPostureSummary?>.Success(
            new AuthenticationPostureSummary
            {
                UserPrincipalName = profile.UserPrincipalName,
                DisplayName = profile.DisplayName,
                DefaultMethod = profile.AuthenticationMethods.Count > 1 ? profile.AuthenticationMethods[1] : "password",
                AuthenticationMethods = profile.AuthenticationMethods,
                MfaRegistered = mfaMethodCount > 0,
                MfaCapable = mfaMethodCount > 0,
                PasswordlessRegistered = passwordlessMethodCount > 0,
                TemporaryAccessPassEligible = StableNumber(profile.SamAccountName) % 3 != 0,
                AuthenticationStrength = strongMethodCount > 0 ? "Phishing-resistant capable" : mfaMethodCount > 0 ? "Multifactor capable" : "Single-factor only",
                ConditionalAccessState = mfaMethodCount > 0 ? "Satisfied" : "Requires registration",
                SignInRiskState = new[] { "none", "low", "none", "none", "medium" }[StableNumber(profile.SamAccountName) % 5],
                LastMfaRegistrationDateTime = mfaMethodCount > 0 ? StableDate(profile.SamAccountName, 120, 10) : null,
                LastSuccessfulSignInDateTime = StableDate(profile.SamAccountName, 72, 12),
                PasswordLastChangedDateTime = profile.PasswordLastChangedDateTime,
                Source = "DirectorySimulator.MicrosoftGraph.Authentication"
            },
            correlationId);
    }

    public async Task<OperationResult<MailboxSummary?>> GetMailboxAsync(
        string identity,
        CorrelationId correlationId,
        CancellationToken cancellationToken = default)
    {
        var userResult = await GetUserAsync(identity, correlationId, cancellationToken).ConfigureAwait(false);
        if (!userResult.Succeeded)
        {
            return OperationResult<MailboxSummary?>.Failure(correlationId, userResult.Errors, userResult.Warnings, userResult.Status);
        }

        var user = userResult.Value;
        if (user is null)
        {
            return OperationResult<MailboxSummary?>.Success(null, correlationId, status: "NotFound");
        }

        if (!_mailboxes.TryGetValue(user.SamAccountName, out var mailbox))
        {
            mailbox = CreateMailbox(user);
            _mailboxes[user.SamAccountName] = mailbox;
        }

        return OperationResult<MailboxSummary?>.Success(mailbox, correlationId);
    }

    public async Task<OperationResult<MailboxStatisticsSummary?>> GetMailboxStatisticsAsync(
        string identity,
        CorrelationId correlationId,
        CancellationToken cancellationToken = default)
    {
        var userResult = await GetUserAsync(identity, correlationId, cancellationToken).ConfigureAwait(false);
        if (!userResult.Succeeded)
        {
            return OperationResult<MailboxStatisticsSummary?>.Failure(correlationId, userResult.Errors, userResult.Warnings, userResult.Status);
        }

        var user = userResult.Value;
        return OperationResult<MailboxStatisticsSummary?>.Success(
            user is null ? null : new MailboxStatisticsSummary
            {
                DisplayName = user.DisplayName,
                TotalItemSize = "1.8 GB",
                ItemCount = 18432,
                LastLogonTime = StableDate(user.SamAccountName, 14, 8)
            },
            correlationId);
    }

    public async Task<OperationResult<IReadOnlyList<MailboxDelegationSummary>>> GetMailboxDelegationsAsync(
        string identity,
        CorrelationId correlationId,
        CancellationToken cancellationToken = default)
    {
        var mailboxResult = await GetMailboxAsync(identity, correlationId, cancellationToken).ConfigureAwait(false);
        if (!mailboxResult.Succeeded)
        {
            return OperationResult<IReadOnlyList<MailboxDelegationSummary>>.Failure(correlationId, mailboxResult.Errors, mailboxResult.Warnings, mailboxResult.Status);
        }

        var mailbox = mailboxResult.Value;
        var delegations = mailbox is null
            ? Array.Empty<MailboxDelegationSummary>()
            : _mailboxDelegations.TryGetValue(mailbox.UserPrincipalName, out var existing)
                ? existing.ToArray()
                : Array.Empty<MailboxDelegationSummary>();

        return OperationResult<IReadOnlyList<MailboxDelegationSummary>>.Success(delegations, correlationId);
    }

    public async Task<OperationResult<IReadOnlyList<DistributionGroupSummary>>> GetDistributionGroupsAsync(
        string identity,
        CorrelationId correlationId,
        CancellationToken cancellationToken = default)
    {
        var userResult = await GetUserAsync(identity, correlationId, cancellationToken).ConfigureAwait(false);
        if (!userResult.Succeeded)
        {
            return OperationResult<IReadOnlyList<DistributionGroupSummary>>.Failure(correlationId, userResult.Errors, userResult.Warnings, userResult.Status);
        }

        var user = userResult.Value;
        var groups = user is null
            ? Array.Empty<DistributionGroupSummary>()
            : new[]
            {
                CreateDistributionGroup($"DL-{user.Department.Replace(" ", string.Empty, StringComparison.Ordinal)}-Announcements"),
                CreateDistributionGroup($"DL-{user.Office}-Staff")
            }
            .Concat(user.Groups.Where(group => group.StartsWith("DL-", StringComparison.OrdinalIgnoreCase)).Select(CreateDistributionGroup))
            .GroupBy(group => group.DisplayName, StringComparer.OrdinalIgnoreCase)
            .Select(group => group.First())
            .ToArray();

        return OperationResult<IReadOnlyList<DistributionGroupSummary>>.Success(groups, correlationId);
    }

    public Task<OperationResult<ConfigurationPreviewSummary>> GetConfigurationPreviewAsync(
        CorrelationId correlationId,
        CancellationToken cancellationToken = default)
    {
        _ = cancellationToken;
        return Task.FromResult(OperationResult<ConfigurationPreviewSummary>.Success(
            new ConfigurationPreviewSummary
            {
                ProviderId = "DirectorySimulator",
                Mode = "Simulation",
                Values = new Dictionary<string, string>
                {
                    ["Users"] = _users.Count.ToString(),
                    ["Devices"] = _devices.Values.Sum(devices => devices.Count).ToString(),
                    ["AllowGeneratedFallbackUsers"] = _options.AllowGeneratedFallbackUsers.ToString()
                }
            },
            correlationId));
    }

    public Task<OperationResult<IReadOnlyList<ReportingSummary>>> GetReportsAsync(
        CorrelationId correlationId,
        CancellationToken cancellationToken = default)
    {
        _ = cancellationToken;
        IReadOnlyList<ReportingSummary> reports = new[]
        {
            new ReportingSummary { ReportId = "sim.users", Name = "Simulator users", RecordCount = _users.Count, Source = "DirectorySimulator" },
            new ReportingSummary { ReportId = "sim.devices", Name = "Simulator devices", RecordCount = _devices.Values.Sum(devices => devices.Count), Source = "DirectorySimulator" },
            new ReportingSummary { ReportId = "sim.mailboxes", Name = "Simulator mailboxes", RecordCount = _mailboxes.Count, Source = "DirectorySimulator" }
        };

        return Task.FromResult(OperationResult<IReadOnlyList<ReportingSummary>>.Success(reports, correlationId));
    }

    public async Task<OperationResult<ProviderChangeResult>> CreateUserAsync(
        UserCreateRequest request,
        CorrelationId correlationId,
        CancellationToken cancellationToken = default)
    {
        var validation = await ValidateReadyAsync(correlationId, cancellationToken).ConfigureAwait(false);
        if (validation is not null)
        {
            return OperationResult<ProviderChangeResult>.Failure(correlationId, validation);
        }

        if (string.IsNullOrWhiteSpace(request.SamAccountName) || string.IsNullOrWhiteSpace(request.GivenName) || string.IsNullOrWhiteSpace(request.Surname))
        {
            return OperationResult<ProviderChangeResult>.Failure(
                correlationId,
                new[] { OperationError.Create("Simulator.UserCreate.RequiredFieldsMissing", "Given name, surname, and SAM account name are required.") });
        }

        await _stateLock.WaitAsync(cancellationToken).ConfigureAwait(false);
        try
        {
            if (_users.Any(user => string.Equals(user.SamAccountName, request.SamAccountName, StringComparison.OrdinalIgnoreCase)))
            {
                return OperationResult<ProviderChangeResult>.Success(Change("CreateUser", request.SamAccountName, false, "User already exists."), correlationId, status: "AlreadyExists");
            }

            var user = CreateUser(request.GivenName, request.Surname, request.SamAccountName, request.Department, request.Title, request.ManagerSamAccountName, Array.Empty<string>(), new[] { "Domain Users" }, request.Office);
            _users.Add(user);
            _devices[user.SamAccountName] = CreateGeneratedDevices(user).ToList();
            _mailboxes[user.SamAccountName] = CreateMailbox(user);
            _mailboxDelegations[user.UserPrincipalName] = new List<MailboxDelegationSummary>();
            return OperationResult<ProviderChangeResult>.Success(Change("CreateUser", user.SamAccountName, true, "User created."), correlationId, status: "Created");
        }
        finally
        {
            _stateLock.Release();
        }
    }

    public async Task<OperationResult<ProviderChangeResult>> UpdateUserAttributesAsync(
        UserUpdateRequest request,
        CorrelationId correlationId,
        CancellationToken cancellationToken = default)
    {
        if (string.IsNullOrWhiteSpace(request.Identity))
        {
            return OperationResult<ProviderChangeResult>.Failure(correlationId, new[] { OperationError.Create("Simulator.UserUpdate.IdentityRequired", "User identity is required.") });
        }

        await _stateLock.WaitAsync(cancellationToken).ConfigureAwait(false);
        try
        {
            var index = _users.FindIndex(user => Matches(user, request.Identity));
            if (index < 0)
            {
                return OperationResult<ProviderChangeResult>.Failure(correlationId, new[] { OperationError.Create("Simulator.UserUpdate.NotFound", "User was not found.") }, status: "NotFound");
            }

            var user = _users[index];
            _users[index] = user with
            {
                DisplayName = ValueOrExisting(request.Attributes, "DisplayName", user.DisplayName),
                GivenName = ValueOrExisting(request.Attributes, "GivenName", user.GivenName),
                Surname = ValueOrExisting(request.Attributes, "Surname", user.Surname),
                SamAccountName = ValueOrExisting(request.Attributes, "SamAccountName", user.SamAccountName),
                UserPrincipalName = ValueOrExisting(request.Attributes, "UserPrincipalName", user.UserPrincipalName),
                Mail = ValueOrExisting(request.Attributes, "Mail", user.Mail),
                Department = ValueOrExisting(request.Attributes, "Department", user.Department),
                Title = ValueOrExisting(request.Attributes, "Title", user.Title),
                Company = ValueOrExisting(request.Attributes, "Company", user.Company),
                Office = ValueOrExisting(request.Attributes, "Office", user.Office),
                EmployeeId = ValueOrExisting(request.Attributes, "EmployeeId", user.EmployeeId),
                DistinguishedName = ValueOrExisting(request.Attributes, "DistinguishedName", user.DistinguishedName),
                ManagerSamAccountName = ValueOrExisting(request.Attributes, "ManagerSamAccountName", user.ManagerSamAccountName),
                DirectReportSamAccountNames = ListOrExisting(request.Attributes, "DirectReportSamAccountNames", user.DirectReportSamAccountNames),
                Groups = ListOrExisting(request.Attributes, "Groups", user.Groups),
                Enabled = BoolOrExisting(request.Attributes, "Enabled", user.Enabled),
                LockedOut = BoolOrExisting(request.Attributes, "LockedOut", user.LockedOut)
            };

            return OperationResult<ProviderChangeResult>.Success(Change("UpdateUserAttributes", user.SamAccountName, true, "User attributes updated."), correlationId, status: "Updated");
        }
        finally
        {
            _stateLock.Release();
        }
    }

    public async Task<OperationResult<ProviderChangeResult>> SetManagerAsync(
        ManagerChangeRequest request,
        CorrelationId correlationId,
        CancellationToken cancellationToken = default)
    {
        await _stateLock.WaitAsync(cancellationToken).ConfigureAwait(false);
        try
        {
            var index = _users.FindIndex(user => Matches(user, request.Identity));
            var manager = _users.FirstOrDefault(user => Matches(user, request.ManagerIdentity));
            if (index < 0 || manager is null)
            {
                return OperationResult<ProviderChangeResult>.Failure(correlationId, new[] { OperationError.Create("Simulator.ManagerChange.NotFound", "User or manager was not found.") }, status: "NotFound");
            }

            var user = _users[index];
            if (string.Equals(user.SamAccountName, manager.SamAccountName, StringComparison.OrdinalIgnoreCase))
            {
                return OperationResult<ProviderChangeResult>.Failure(correlationId, new[] { OperationError.Create("Simulator.ManagerChange.SelfManager", "A user cannot be their own manager.") });
            }

            _users[index] = user with { ManagerSamAccountName = manager.SamAccountName };
            return OperationResult<ProviderChangeResult>.Success(Change("SetManager", user.SamAccountName, true, "Manager updated."), correlationId, status: "Updated");
        }
        finally
        {
            _stateLock.Release();
        }
    }

    public Task<OperationResult<ProviderChangeResult>> AddGroupMembershipAsync(
        MembershipChangeRequest request,
        CorrelationId correlationId,
        CancellationToken cancellationToken = default)
    {
        return ChangeGroupMembershipAsync(request, correlationId, add: true, cancellationToken);
    }

    public Task<OperationResult<ProviderChangeResult>> RemoveGroupMembershipAsync(
        MembershipChangeRequest request,
        CorrelationId correlationId,
        CancellationToken cancellationToken = default)
    {
        return ChangeGroupMembershipAsync(request, correlationId, add: false, cancellationToken);
    }

    public async Task<OperationResult<ProviderChangeResult>> SetMailboxForwardingAsync(
        MailboxForwardingRequest request,
        CorrelationId correlationId,
        CancellationToken cancellationToken = default)
    {
        await _stateLock.WaitAsync(cancellationToken).ConfigureAwait(false);
        try
        {
            var user = _users.FirstOrDefault(item => Matches(item, request.Identity));
            if (user is null)
            {
                return OperationResult<ProviderChangeResult>.Failure(correlationId, new[] { OperationError.Create("Simulator.MailboxForwarding.NotFound", "Mailbox user was not found.") }, status: "NotFound");
            }

            var mailbox = _mailboxes.TryGetValue(user.SamAccountName, out var existing) ? existing : CreateMailbox(user);
            _mailboxes[user.SamAccountName] = mailbox with
            {
                ForwardingSmtpAddress = request.ForwardingSmtpAddress,
                DeliverToMailboxAndForward = request.DeliverToMailboxAndForward
            };

            return OperationResult<ProviderChangeResult>.Success(Change("SetMailboxForwarding", user.SamAccountName, true, "Mailbox forwarding updated."), correlationId, status: "Updated");
        }
        finally
        {
            _stateLock.Release();
        }
    }

    public async Task<OperationResult<ProviderChangeResult>> SetGalVisibilityAsync(
        GalVisibilityRequest request,
        CorrelationId correlationId,
        CancellationToken cancellationToken = default)
    {
        await _stateLock.WaitAsync(cancellationToken).ConfigureAwait(false);
        try
        {
            var user = _users.FirstOrDefault(item => Matches(item, request.Identity));
            if (user is null)
            {
                return OperationResult<ProviderChangeResult>.Failure(correlationId, new[] { OperationError.Create("Simulator.GalVisibility.NotFound", "Mailbox user was not found.") }, status: "NotFound");
            }

            var mailbox = _mailboxes.TryGetValue(user.SamAccountName, out var existing) ? existing : CreateMailbox(user);
            _mailboxes[user.SamAccountName] = mailbox with { HiddenFromAddressListsEnabled = request.HiddenFromAddressListsEnabled };
            return OperationResult<ProviderChangeResult>.Success(Change("SetGalVisibility", user.SamAccountName, true, request.HiddenFromAddressListsEnabled ? "Mailbox hidden from GAL." : "Mailbox shown in GAL."), correlationId, status: "Updated");
        }
        finally
        {
            _stateLock.Release();
        }
    }

    public async Task<OperationResult<ProviderChangeResult>> AddMailboxDelegationAsync(
        MailboxDelegationChangeRequest request,
        CorrelationId correlationId,
        CancellationToken cancellationToken = default)
    {
        if (string.IsNullOrWhiteSpace(request.Identity) || string.IsNullOrWhiteSpace(request.Trustee))
        {
            return OperationResult<ProviderChangeResult>.Failure(correlationId, new[] { OperationError.Create("Simulator.MailboxDelegation.RequiredFieldsMissing", "Identity and trustee are required.") });
        }

        await _stateLock.WaitAsync(cancellationToken).ConfigureAwait(false);
        try
        {
            var user = _users.FirstOrDefault(item => Matches(item, request.Identity));
            if (user is null)
            {
                return OperationResult<ProviderChangeResult>.Failure(correlationId, new[] { OperationError.Create("Simulator.MailboxDelegation.NotFound", "Mailbox user was not found.") }, status: "NotFound");
            }

            var mailbox = _mailboxes.TryGetValue(user.SamAccountName, out var existing) ? existing : CreateMailbox(user);
            var key = mailbox.UserPrincipalName;
            if (!_mailboxDelegations.TryGetValue(key, out var delegations))
            {
                delegations = new List<MailboxDelegationSummary>();
                _mailboxDelegations[key] = delegations;
            }

            var exists = delegations.Any(item =>
                string.Equals(item.Trustee, request.Trustee, StringComparison.OrdinalIgnoreCase) &&
                string.Equals(item.AccessRights, request.AccessRights, StringComparison.OrdinalIgnoreCase));
            if (!exists)
            {
                delegations.Add(new MailboxDelegationSummary { Trustee = request.Trustee.Trim(), AccessRights = request.AccessRights, Identity = mailbox.PrimarySmtpAddress });
            }

            return OperationResult<ProviderChangeResult>.Success(Change("AddMailboxDelegation", user.SamAccountName, !exists, exists ? "Mailbox delegation already exists." : "Mailbox delegation added."), correlationId, status: exists ? "NoChange" : "Updated");
        }
        finally
        {
            _stateLock.Release();
        }
    }

    public async Task<OperationResult<ProviderChangeResult>> ResetStateAsync(
        CorrelationId correlationId,
        CancellationToken cancellationToken = default)
    {
        await _stateLock.WaitAsync(cancellationToken).ConfigureAwait(false);
        try
        {
            _users = DirectorySimulatorSeedData.Users.ToList();
            _devices = CreateSeedDevices(_users);
            _mailboxes = CreateSeedMailboxes(_users);
            _mailboxDelegations = CreateSeedMailboxDelegations(_mailboxes);
            return OperationResult<ProviderChangeResult>.Success(Change("ResetState", "DirectorySimulator", true, "Simulator state reset."), correlationId, status: "Reset");
        }
        finally
        {
            _stateLock.Release();
        }
    }

    private async Task<IReadOnlyList<OperationError>?> ValidateReadyAsync(
        CorrelationId correlationId,
        CancellationToken cancellationToken)
    {
        _ = correlationId;
        if (cancellationToken.IsCancellationRequested)
        {
            return new[] { OperationError.Create("Simulator.OperationCancelled", "Directory Simulator operation was cancelled.") };
        }

        if (!_options.ConfigurationValid)
        {
            return new[] { OperationError.Create("Simulator.ConfigurationInvalid", "Directory Simulator configuration is invalid.") };
        }

        if (!_options.Enabled || !_options.ProviderAvailable)
        {
            return new[] { OperationError.Create("Simulator.ProviderUnavailable", "Directory Simulator provider is unavailable.") };
        }

        await Task.CompletedTask.ConfigureAwait(false);
        return null;
    }

    private IEnumerable<SimulatorUserSummary> FindSeededUsers(string query)
    {
        var clean = NormalizeQuery(query);
        foreach (var user in _users)
        {
            var aliases = new[]
            {
                user.SamAccountName,
                user.DisplayName,
                user.UserPrincipalName,
                $"{user.GivenName} {user.Surname}"
            };

            if (aliases.Any(alias => NormalizeQuery(alias).Contains(clean, StringComparison.OrdinalIgnoreCase)))
            {
                yield return user;
            }
        }
    }

    private static SimulatorUserSummary CreateGeneratedUser(string query)
    {
        var parts = query.Split(new[] { ' ', '.', '_', '@', '-' }, StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries);
        var first = ToTitle(parts.Length >= 1 ? parts[0] : "Sample");
        var last = ToTitle(parts.Length >= 2 ? parts[1] : "User");
        var sam = string.Concat(first[0], last).ToLowerInvariant();
        return new SimulatorUserSummary
        {
            DisplayName = $"{first} {last}",
            GivenName = first,
            Surname = last,
            SamAccountName = sam,
            UserPrincipalName = $"{sam}@atlas-tech.com",
            Mail = $"{sam}@atlas-tech.com",
            Department = "Information Technology",
            Title = "Systems Specialist",
            Company = "Atlas",
            Office = "Charleston",
            EmployeeId = $"SIM-{sam.ToUpperInvariant()}",
            DistinguishedName = $"CN={first} {last},OU=Users,OU=Information Technology,OU=Atlas,DC=atlas-tech,DC=com",
            ManagerSamAccountName = "treed",
            Groups = new[] { "Domain Users", "GG-InformationTechnology", "GG-VPN" },
            Enabled = true,
            LockedOut = false,
            Source = "DirectorySimulator"
        };
    }

    private static SimulatorUserSummary CreateUser(
        string firstName,
        string lastName,
        string samAccountName,
        string department,
        string title,
        string managerSamAccountName,
        IReadOnlyList<string> directReports,
        IReadOnlyList<string> groups,
        string office)
    {
        var cleanDepartment = string.IsNullOrWhiteSpace(department) ? "General" : department.Trim();
        var cleanOffice = string.IsNullOrWhiteSpace(office) ? "Default" : office.Trim();
        var displayName = $"{firstName.Trim()} {lastName.Trim()}";
        return new SimulatorUserSummary
        {
            DisplayName = displayName,
            GivenName = firstName.Trim(),
            Surname = lastName.Trim(),
            SamAccountName = samAccountName.Trim().ToLowerInvariant(),
            UserPrincipalName = $"{samAccountName.Trim().ToLowerInvariant()}@atlas-tech.com",
            Mail = $"{samAccountName.Trim().ToLowerInvariant()}@atlas-tech.com",
            Department = cleanDepartment,
            Title = string.IsNullOrWhiteSpace(title) ? "User" : title.Trim(),
            Company = "Atlas",
            Office = cleanOffice,
            EmployeeId = $"SIM-{samAccountName.Trim().ToUpperInvariant()}",
            DistinguishedName = $"CN={displayName},OU=Users,OU={cleanDepartment},OU=Atlas,DC=atlas-tech,DC=com",
            ManagerSamAccountName = managerSamAccountName.Trim(),
            DirectReportSamAccountNames = directReports,
            Groups = groups,
            Enabled = true,
            LockedOut = false,
            Source = "DirectorySimulator"
        };
    }

    private async Task<OperationResult<ProviderChangeResult>> ChangeGroupMembershipAsync(
        MembershipChangeRequest request,
        CorrelationId correlationId,
        bool add,
        CancellationToken cancellationToken)
    {
        if (string.IsNullOrWhiteSpace(request.Identity) || string.IsNullOrWhiteSpace(request.Group))
        {
            return OperationResult<ProviderChangeResult>.Failure(
                correlationId,
                new[] { OperationError.Create("Simulator.GroupMembership.RequiredFieldsMissing", "Identity and group are required.") });
        }

        await _stateLock.WaitAsync(cancellationToken).ConfigureAwait(false);
        try
        {
            var index = _users.FindIndex(user => Matches(user, request.Identity));
            if (index < 0)
            {
                return OperationResult<ProviderChangeResult>.Failure(correlationId, new[] { OperationError.Create("Simulator.GroupMembership.NotFound", "User was not found.") }, status: "NotFound");
            }

            var user = _users[index];
            var groups = user.Groups.ToList();
            var exists = groups.Contains(request.Group, StringComparer.OrdinalIgnoreCase);
            if (add && !exists)
            {
                groups.Add(request.Group);
            }
            else if (!add && exists)
            {
                groups.RemoveAll(group => string.Equals(group, request.Group, StringComparison.OrdinalIgnoreCase));
            }

            _users[index] = user with { Groups = groups.OrderBy(group => group, StringComparer.OrdinalIgnoreCase).ToArray() };
            return OperationResult<ProviderChangeResult>.Success(
                Change(add ? "AddGroupMembership" : "RemoveGroupMembership", user.SamAccountName, add != exists, "Group membership processed."),
                correlationId,
                status: add == exists ? "NoChange" : "Updated");
        }
        finally
        {
            _stateLock.Release();
        }
    }

    private static ProviderChangeResult Change(string operation, string targetId, bool changed, string message)
    {
        return new ProviderChangeResult
        {
            Operation = operation,
            TargetId = targetId,
            Changed = changed,
            Message = message,
            Source = "DirectorySimulator"
        };
    }

    private static bool Matches(SimulatorUserSummary user, string identity)
    {
        return new[] { user.SamAccountName, user.UserPrincipalName, user.DisplayName, user.Mail }
            .Any(value => string.Equals(value, identity, StringComparison.OrdinalIgnoreCase));
    }

    private static IReadOnlyList<DirectoryAttributeValue> BuildDirectoryAttributes(SimulatorUserSummary user)
    {
        var proxyAddresses = string.IsNullOrWhiteSpace(user.Mail)
            ? Array.Empty<string>()
            : new[] { $"SMTP:{user.Mail}", $"smtp:{user.SamAccountName}@example.com" };

        return new[]
        {
            Attribute("cn", user.DisplayName),
            Attribute("name", user.DisplayName),
            Attribute("displayName", user.DisplayName),
            Attribute("givenName", user.GivenName),
            Attribute("sn", user.Surname),
            Attribute("sAMAccountName", user.SamAccountName),
            Attribute("userPrincipalName", user.UserPrincipalName),
            Attribute("mail", user.Mail),
            Attribute("mailNickname", user.SamAccountName),
            Attribute("proxyAddresses", proxyAddresses, isSingleValued: false),
            Attribute("department", user.Department),
            Attribute("title", user.Title),
            Attribute("company", user.Company),
            Attribute("physicalDeliveryOfficeName", user.Office),
            Attribute("employeeID", user.EmployeeId),
            Attribute("BadgeID", user.EmployeeId),
            Attribute("EmployeeNumber", user.EmployeeId),
            Attribute("employeeNumber", user.EmployeeId),
            Attribute("manager", user.ManagerSamAccountName),
            Attribute("directReports", user.DirectReportSamAccountNames, isSingleValued: false, isReadOnly: true),
            Attribute("memberOf", user.Groups, isSingleValued: false, isReadOnly: true),
            Attribute("distinguishedName", user.DistinguishedName, isReadOnly: true),
            Attribute("objectClass", new[] { "top", "person", "organizationalPerson", "user" }, isSingleValued: false, isReadOnly: true),
            Attribute("objectGUID", StableId(user.SamAccountName), isReadOnly: true),
            Attribute("objectSid", $"S-1-5-21-SIM-{StableNumber(user.SamAccountName):000000}", isReadOnly: true),
            Attribute("userAccountControl", user.Enabled ? "512" : "514"),
            Attribute("lockoutTime", user.LockedOut ? "1" : "0"),
            Attribute("msExchHideFromAddressLists", "False"),
            Attribute("targetAddress", string.Empty),
            Attribute("legacyExchangeDN", $"/o=HAP/ou=Exchange Administrative Group/cn=Recipients/cn={user.SamAccountName}"),
            Attribute("msExchRecipientDisplayType", "1073741824"),
            Attribute("msExchRecipientTypeDetails", "1"),
            Attribute("msExchRemoteRecipientType", string.Empty)
        };
    }

    private static DirectoryAttributeValue Attribute(
        string name,
        string value,
        bool isSingleValued = true,
        bool isReadOnly = false,
        string syntax = "String")
    {
        return Attribute(name, string.IsNullOrWhiteSpace(value) ? Array.Empty<string>() : new[] { value }, isSingleValued, isReadOnly, syntax);
    }

    private static DirectoryAttributeValue Attribute(
        string name,
        IReadOnlyList<string> values,
        bool isSingleValued = true,
        bool isReadOnly = false,
        string syntax = "String")
    {
        return new DirectoryAttributeValue
        {
            Name = name,
            DisplayName = name,
            Values = values,
            IsSingleValued = isSingleValued,
            IsReadOnly = isReadOnly,
            Syntax = syntax,
            Source = "DirectorySimulator"
        };
    }

    private static string ValueOrExisting(IReadOnlyDictionary<string, string> values, string key, string existing)
    {
        return values.TryGetValue(key, out var value) && !string.IsNullOrWhiteSpace(value) ? value.Trim() : existing;
    }

    private static bool BoolOrExisting(IReadOnlyDictionary<string, string> values, string key, bool existing)
    {
        return values.TryGetValue(key, out var value) && bool.TryParse(value, out var parsed) ? parsed : existing;
    }

    private static IReadOnlyList<string> ListOrExisting(IReadOnlyDictionary<string, string> values, string key, IReadOnlyList<string> existing)
    {
        return values.TryGetValue(key, out var value)
            ? value.Split(new[] { ';', ',' }, StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries)
            : existing;
    }

    private static Dictionary<string, List<ManagedDeviceSummary>> CreateSeedDevices(IEnumerable<SimulatorUserSummary> users)
    {
        var devices = new Dictionary<string, List<ManagedDeviceSummary>>(StringComparer.OrdinalIgnoreCase);
        foreach (var user in users)
        {
            devices[user.SamAccountName] = user.SamAccountName.ToLowerInvariant() switch
            {
                "rwilliams" => new() { CreateDevice("sim-device-rwilliams-01", "SIM-RWILLIAMS-PAW", user.UserPrincipalName, "Compliant", 3) },
                "treed" => new()
                {
                    CreateDevice("sim-device-treed-01", "SIM-TREED-LT01", user.UserPrincipalName, "Compliant", 6),
                    CreateDevice("sim-device-treed-02", "SIM-TREED-TAB01", user.UserPrincipalName, "Unknown", 36)
                },
                "amorgan" => new()
                {
                    CreateDevice("sim-device-amorgan-01", "SIM-AMORGAN-LT01", user.UserPrincipalName, "Compliant", 2),
                    CreateDevice("sim-device-amorgan-02", "SIM-AMORGAN-PAW01", user.UserPrincipalName, "Compliant", 5)
                },
                "jlee" => new() { CreateDevice("sim-device-jlee-01", "SIM-JLEE-LT01", user.UserPrincipalName, "Compliant", 8) },
                _ => CreateGeneratedDevices(user).ToList()
            };
        }

        return devices;
    }

    private static IEnumerable<ManagedDeviceSummary> CreateGeneratedDevices(SimulatorUserSummary user)
    {
        if (StableNumber(user.SamAccountName) % 4 == 0)
        {
            return Array.Empty<ManagedDeviceSummary>();
        }

        return new[]
        {
            CreateDevice(
                $"sim-device-{user.SamAccountName}-01",
                $"SIM-{user.SamAccountName.ToUpperInvariant()}-LT01",
                user.UserPrincipalName,
                StableNumber(user.SamAccountName) % 5 == 0 ? "NonCompliant" : "Compliant",
                StableNumber(user.SamAccountName) % 96 + 1)
        };
    }

    private static ManagedDeviceSummary CreateDevice(string id, string name, string primaryUser, string complianceState, int lastCheckInHoursAgo)
    {
        return new ManagedDeviceSummary
        {
            Id = id,
            Name = name,
            OperatingSystem = "Windows 11 Enterprise",
            ComplianceState = complianceState,
            PrimaryUser = primaryUser,
            LastCheckInUtc = new DateTimeOffset(2026, 1, 15, 12, 0, 0, TimeSpan.Zero).AddHours(-lastCheckInHoursAgo),
            Source = "DirectorySimulator.MicrosoftGraph.Devices"
        };
    }

    private static Dictionary<string, MailboxSummary> CreateSeedMailboxes(IEnumerable<SimulatorUserSummary> users)
    {
        return users.ToDictionary(user => user.SamAccountName, CreateMailbox, StringComparer.OrdinalIgnoreCase);
    }

    private static Dictionary<string, List<MailboxDelegationSummary>> CreateSeedMailboxDelegations(IReadOnlyDictionary<string, MailboxSummary> mailboxes)
    {
        return mailboxes.Values.ToDictionary(
            mailbox => mailbox.UserPrincipalName,
            mailbox => new List<MailboxDelegationSummary>
            {
                new() { Trustee = "IT Service Desk", AccessRights = "FullAccess", Identity = mailbox.PrimarySmtpAddress },
                new() { Trustee = "Taylor Reed", AccessRights = "SendAs", Identity = mailbox.PrimarySmtpAddress }
            },
            StringComparer.OrdinalIgnoreCase);
    }

    private static MailboxSummary CreateMailbox(SimulatorUserSummary user)
    {
        return new MailboxSummary
        {
            DisplayName = user.DisplayName,
            PrimarySmtpAddress = user.Mail,
            UserPrincipalName = user.UserPrincipalName,
            RecipientTypeDetails = "UserMailbox",
            ExchangeGuid = StableId(user.Mail),
            HiddenFromAddressListsEnabled = false,
            LitigationHoldEnabled = false,
            DeliverToMailboxAndForward = false,
            ForwardingSmtpAddress = string.Empty,
            Source = "ExchangeOnline"
        };
    }

    private static DistributionGroupSummary CreateDistributionGroup(string name)
    {
        return new DistributionGroupSummary
        {
            Id = StableId(name),
            DisplayName = name,
            Mail = $"{name.ToLowerInvariant()}@atlas-tech.com",
            Source = "DirectorySimulator.ExchangeOnline"
        };
    }

    private static IReadOnlyList<string> GetMethods(string samAccountName)
    {
        return samAccountName.ToLowerInvariant() switch
        {
            "amorgan" => new[] { "password", "microsoftAuthenticatorPush", "softwareOath" },
            "jlee" => new[] { "password", "sms" },
            "treed" => new[] { "password", "fido2", "microsoftAuthenticatorPush" },
            _ => new[] { "password" }
        };
    }

    private static IEnumerable<LicenseAssignmentSummary> GetLicenses(SimulatorUserSummary user)
    {
        yield return new LicenseAssignmentSummary
        {
            SkuId = StableId($"{user.SamAccountName}:m365e3"),
            SkuPartNumber = "ENTERPRISEPACK",
            FriendlyName = "Microsoft 365 E3",
            AssignmentState = "Active",
            Source = "DirectorySimulator.MicrosoftGraph"
        };

        if (string.Equals(user.Department, "Information Technology", StringComparison.OrdinalIgnoreCase))
        {
            yield return new LicenseAssignmentSummary
            {
                SkuId = StableId($"{user.SamAccountName}:visio"),
                SkuPartNumber = "VISIOCLIENT",
                FriendlyName = "Visio Plan 2",
                AssignmentState = "Active",
                Source = "DirectorySimulator.MicrosoftGraph"
            };
        }
    }

    private static IEnumerable<string> GetPimRoles(SimulatorUserSummary user)
    {
        if (user.SamAccountName is "rwilliams" or "treed")
        {
            yield return "Privileged Role Administrator";
        }

        if (user.Groups.Any(group => group.Contains("Administrators", StringComparison.OrdinalIgnoreCase)))
        {
            yield return "User Administrator";
        }
    }

    private static DateTimeOffset StableDate(string seed, int dayRange, int hour)
    {
        return new DateTimeOffset(2026, 1, 15, hour, 0, 0, TimeSpan.Zero).AddDays(-1 * ((StableNumber(seed) % dayRange) + 1));
    }

    private static int StableNumber(string value)
    {
        return Math.Abs(value.Trim().ToLowerInvariant().Aggregate(17, (current, character) => current * 31 + character));
    }

    private static string StableId(string value)
    {
        var bytes = SHA256.HashData(Encoding.UTF8.GetBytes(value.ToLowerInvariant()));
        return new Guid(bytes.Take(16).ToArray()).ToString();
    }

    private static bool IsPartialQuery(string query)
    {
        return NormalizeQuery(query).Equals("partial user", StringComparison.OrdinalIgnoreCase);
    }

    private static string NormalizeQuery(string query)
    {
        var clean = query.Trim().ToLowerInvariant();
        if (clean.Contains('@', StringComparison.Ordinal))
        {
            clean = clean.Split('@')[0];
        }

        clean = string.Concat(clean.Select(character => char.IsLetterOrDigit(character) ? character : ' '));
        return string.Join(' ', clean.Split(' ', StringSplitOptions.RemoveEmptyEntries));
    }

    private static string ToTitle(string value)
    {
        if (string.IsNullOrWhiteSpace(value))
        {
            return "User";
        }

        var lower = value.ToLowerInvariant();
        return char.ToUpperInvariant(lower[0]) + lower[1..];
    }

    private static OperationResult<T> Cancelled<T>(CorrelationId correlationId)
    {
        return OperationResult<T>.Failure(
            correlationId,
            new[] { OperationError.Create("Simulator.OperationCancelled", "Directory Simulator operation was cancelled.") },
            status: "Cancelled");
    }
}
