using HAP.Contracts;
using HAP.Providers.Abstractions;
using System.DirectoryServices;
using System.Runtime.Versioning;

namespace HAP.Providers.ActiveDirectory;

[SupportedOSPlatform("windows")]
public sealed class ActiveDirectoryProvider :
    IProviderHealthCapability,
    IUserLookupCapability,
    IDirectoryReadCapability,
    IDirectoryAttributeReadCapability,
    IDirectoryGroupLookupCapability,
    ISimulatorWriteCapability
{
    private readonly ActiveDirectoryProviderOptions _options;
    private readonly List<SimulatorUserSummary> _users;
    private static readonly HashSet<string> WritableUserAttributeNames = new(StringComparer.OrdinalIgnoreCase)
    {
        "adminDescription", "assistant", "c", "co", "company", "countryCode",
        "department", "departmentNumber", "description", "displayName", "division",
        "employeeID", "employeeNumber", "EmployeeNumber", "BadgeID",
        "facsimileTelephoneNumber", "givenName", "homeDirectory", "homeDrive",
        "homePhone", "initials", "info", "ipPhone", "l", "mail", "mailNickname",
        "manager", "middleName", "mobile", "otherMailbox", "otherTelephone",
        "pager", "physicalDeliveryOfficeName", "postalAddress", "postalCode",
        "postOfficeBox", "proxyAddresses", "sAMAccountName", "scriptPath", "sn",
        "st", "streetAddress", "telephoneNumber", "title", "url",
        "userAccountControl", "userPrincipalName", "wWWHomePage",
        "extensionAttribute1", "extensionAttribute2", "extensionAttribute3",
        "extensionAttribute4", "extensionAttribute5", "extensionAttribute6",
        "extensionAttribute7", "extensionAttribute8", "extensionAttribute9",
        "extensionAttribute10", "extensionAttribute11", "extensionAttribute12",
        "extensionAttribute13", "extensionAttribute14", "extensionAttribute15",
        "targetAddress", "legacyExchangeDN", "msExchHideFromAddressLists",
        "altRecipient", "deliverAndRedirect"
    };

    public ActiveDirectoryProvider(ActiveDirectoryProviderOptions? options = null, IReadOnlyList<SimulatorUserSummary>? users = null)
    {
        _options = options ?? new ActiveDirectoryProviderOptions();
        _users = users?.ToList() ?? new List<SimulatorUserSummary>
        {
            new() { DisplayName = "Alex Morgan", SamAccountName = "amorgan", UserPrincipalName = "amorgan@littleinnovation.tech", Mail = "amorgan@littleinnovation.tech", Department = "Information Technology", Title = "Systems Administrator", ManagerSamAccountName = "treed", Groups = new[] { "Domain Users", "GG-IT-Administrators" }, Source = "ActiveDirectory", Enabled = true },
            new() { DisplayName = "Taylor Reed", SamAccountName = "treed", UserPrincipalName = "treed@littleinnovation.tech", Mail = "treed@littleinnovation.tech", Department = "Information Technology", Title = "IT Manager", DirectReportSamAccountNames = new[] { "amorgan" }, Groups = new[] { "Domain Users", "GG-IT-Managers" }, Source = "ActiveDirectory", Enabled = true }
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
        if (_options.UseLiveDirectory)
        {
            return Task.FromResult(SearchLiveUsers(query, correlationId));
        }

        IReadOnlyList<SimulatorUserSummary> matches = _users.Where(user => user.SamAccountName.Contains(query, StringComparison.OrdinalIgnoreCase) || user.DisplayName.Contains(query, StringComparison.OrdinalIgnoreCase) || user.UserPrincipalName.Contains(query, StringComparison.OrdinalIgnoreCase)).OrderBy(user => user.SamAccountName, StringComparer.OrdinalIgnoreCase).ToArray();
        return Task.FromResult(OperationResult<IReadOnlyList<SimulatorUserSummary>>.Success(matches, correlationId));
    }

    public async Task<OperationResult<SimulatorUserSummary?>> GetUserAsync(string identity, CorrelationId correlationId, CancellationToken cancellationToken = default)
    {
        var error = Validate();
        if (error is not null)
        {
            return OperationResult<SimulatorUserSummary?>.Failure(correlationId, new[] { error }, status: "Failed");
        }

        if (_options.UseLiveDirectory)
        {
            try
            {
                var result = FindLiveUser(identity);
                return OperationResult<SimulatorUserSummary?>.Success(result is null ? null : MapUser(result), correlationId, status: result is null ? "NoMatches" : "Loaded");
            }
            catch (Exception ex)
            {
                return OperationResult<SimulatorUserSummary?>.Failure(
                    correlationId,
                    new[] { OperationError.Create("AD.UserRead.LiveQueryFailed", $"Active Directory user read failed: {ex.Message}") },
                    status: "Failed");
            }
        }

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
        IReadOnlyList<DirectoryGroupSummary> groups = user.Value?.Groups.Select(group => new DirectoryGroupSummary { Id = group, DisplayName = ExtractCn(group), Source = _options.UseLiveDirectory ? "ActiveDirectory.LiveLdap" : "ActiveDirectory" }).OrderBy(group => group.DisplayName, StringComparer.OrdinalIgnoreCase).ToArray() ?? Array.Empty<DirectoryGroupSummary>();
        return OperationResult<IReadOnlyList<DirectoryGroupSummary>>.Success(groups, correlationId);
    }

    public Task<OperationResult<IReadOnlyList<SimulatorUserSummary>>> GetDirectReportsAsync(string identity, CorrelationId correlationId, CancellationToken cancellationToken = default)
    {
        if (_options.UseLiveDirectory)
        {
            return Task.FromResult(GetLiveDirectReports(identity, correlationId));
        }

        IReadOnlyList<SimulatorUserSummary> reports = _users.Where(user => string.Equals(user.ManagerSamAccountName, identity, StringComparison.OrdinalIgnoreCase)).OrderBy(user => user.SamAccountName, StringComparer.OrdinalIgnoreCase).ToArray();
        return Task.FromResult(OperationResult<IReadOnlyList<SimulatorUserSummary>>.Success(reports, correlationId));
    }

    public async Task<OperationResult<DirectoryObjectAttributeSet>> GetDirectoryAttributesAsync(string identity, CorrelationId correlationId, CancellationToken cancellationToken = default)
    {
        var error = Validate();
        if (error is not null)
        {
            return OperationResult<DirectoryObjectAttributeSet>.Failure(correlationId, new[] { error }, status: "Failed");
        }

        var user = await GetUserAsync(identity, correlationId, cancellationToken).ConfigureAwait(false);
        if (!user.Succeeded)
        {
            return OperationResult<DirectoryObjectAttributeSet>.Failure(correlationId, user.Errors, user.Warnings, user.Status);
        }

        if (user.Value is null)
        {
            return OperationResult<DirectoryObjectAttributeSet>.Failure(
                correlationId,
                new[] { OperationError.Create("AD.DirectoryAttributes.NotFound", "User was not found.") },
                status: "NotFound");
        }

        if (_options.UseLiveDirectory)
        {
            return GetLiveDirectoryAttributes(user.Value, correlationId);
        }

        var warnings = _options.UseLiveDirectory
            ? Array.Empty<OperationWarning>()
            : new[] { OperationWarning.Create("AD.DirectoryAttributes.FixtureBacked", "Live LDAP schema reads are not enabled; returning AD-shaped provider fixture attributes.") };

        var status = _options.UseLiveDirectory ? "Loaded" : "FixtureBacked";
        return OperationResult<DirectoryObjectAttributeSet>.Success(
            new DirectoryObjectAttributeSet
            {
                Identity = user.Value.SamAccountName,
                DistinguishedName = user.Value.DistinguishedName,
                ObjectClass = "user",
                SchemaSource = _options.UseLiveDirectory ? "ActiveDirectory.Schema" : "ActiveDirectory.LatestAdExchangeBaseline",
                Attributes = BuildDirectoryAttributes(user.Value)
            },
            correlationId,
            warnings,
            status);
    }

    public Task<OperationResult<ProviderChangeResult>> CreateUserAsync(UserCreateRequest request, CorrelationId correlationId, CancellationToken cancellationToken = default)
    {
        if (!_options.UseLiveDirectory) return Unsupported(correlationId, "AD.UserCreate.RequiresLiveDirectory", "AD user creation requires live directory mode.");
        if (!_options.AllowWrites) return Unsupported(correlationId, "AD.UserCreate.WritesDisabled", "AD writes are disabled for this runtime profile.");
        try
        {
            if (string.IsNullOrWhiteSpace(request.GivenName) || string.IsNullOrWhiteSpace(request.Surname) || string.IsNullOrWhiteSpace(request.SamAccountName))
            {
                return Task.FromResult(OperationResult<ProviderChangeResult>.Failure(correlationId, new[] { OperationError.Create("AD.UserCreate.RequiredFieldsMissing", "Given name, surname, and SAM account name are required.") }));
            }

            using var container = CreateUserContainer();
            var displayName = $"{request.GivenName.Trim()} {request.Surname.Trim()}";
            using var user = container.Children.Add($"CN={EscapeRdn(displayName)}", "user");
            SetProperty(user, "givenName", request.GivenName);
            SetProperty(user, "sn", request.Surname);
            SetProperty(user, "displayName", displayName);
            SetProperty(user, "sAMAccountName", request.SamAccountName);
            SetProperty(user, "userPrincipalName", BuildUserPrincipalName(request.SamAccountName));
            SetProperty(user, "department", request.Department);
            SetProperty(user, "title", request.Title);
            SetProperty(user, "physicalDeliveryOfficeName", request.Office);
            user.Properties["userAccountControl"].Value = 514;
            user.CommitChanges();

            if (!string.IsNullOrWhiteSpace(request.ManagerSamAccountName))
            {
                using var manager = FindLiveEntry(request.ManagerSamAccountName);
                if (manager is not null)
                {
                    SetProperty(user, "manager", manager.Properties["distinguishedName"].Value?.ToString() ?? string.Empty);
                    user.CommitChanges();
                }
            }

            return Task.FromResult(OperationResult<ProviderChangeResult>.Success(Change("CreateUser", request.SamAccountName, true, "AD user created disabled in the default user container."), correlationId, status: "Created"));
        }
        catch (Exception ex)
        {
            return Task.FromResult(OperationResult<ProviderChangeResult>.Failure(correlationId, new[] { OperationError.Create("AD.UserCreate.Failed", $"AD user creation failed: {ex.Message}") }, status: "Failed"));
        }
    }

    public Task<OperationResult<ProviderChangeResult>> UpdateUserAttributesAsync(UserUpdateRequest request, CorrelationId correlationId, CancellationToken cancellationToken = default)
    {
        if (!_options.UseLiveDirectory) return Unsupported(correlationId, "AD.UserUpdate.RequiresLiveDirectory", "AD user updates require live directory mode.");
        if (!_options.AllowWrites) return Unsupported(correlationId, "AD.UserUpdate.WritesDisabled", "AD writes are disabled for this runtime profile.");
        try
        {
            using var user = FindLiveEntry(request.Identity);
            if (user is null)
            {
                return Task.FromResult(OperationResult<ProviderChangeResult>.Failure(correlationId, new[] { OperationError.Create("AD.UserUpdate.NotFound", "User was not found.") }, status: "NotFound"));
            }

            var changed = false;
            foreach (var pair in request.Attributes)
            {
                changed |= ApplyUserAttribute(user, pair.Key, pair.Value);
            }

            if (changed)
            {
                user.CommitChanges();
            }

            return Task.FromResult(OperationResult<ProviderChangeResult>.Success(Change("UpdateUserAttributes", request.Identity, changed, changed ? "AD user attributes updated." : "No writable AD attributes changed."), correlationId, status: changed ? "Updated" : "NoChange"));
        }
        catch (Exception ex)
        {
            return Task.FromResult(OperationResult<ProviderChangeResult>.Failure(correlationId, new[] { OperationError.Create("AD.UserUpdate.Failed", $"AD user update failed: {ex.Message}") }, status: "Failed"));
        }
    }

    public Task<OperationResult<ProviderChangeResult>> SetManagerAsync(ManagerChangeRequest request, CorrelationId correlationId, CancellationToken cancellationToken = default)
    {
        if (!_options.UseLiveDirectory) return Unsupported(correlationId, "AD.ManagerChange.RequiresLiveDirectory", "AD manager changes require live directory mode.");
        if (!_options.AllowWrites) return Unsupported(correlationId, "AD.ManagerChange.WritesDisabled", "AD writes are disabled for this runtime profile.");
        try
        {
            using var user = FindLiveEntry(request.Identity);
            using var manager = FindLiveEntry(request.ManagerIdentity);
            if (user is null || manager is null)
            {
                return Task.FromResult(OperationResult<ProviderChangeResult>.Failure(correlationId, new[] { OperationError.Create("AD.ManagerChange.NotFound", "User or manager was not found.") }, status: "NotFound"));
            }

            var managerDn = manager.Properties["distinguishedName"].Value?.ToString() ?? string.Empty;
            SetProperty(user, "manager", managerDn);
            user.CommitChanges();
            return Task.FromResult(OperationResult<ProviderChangeResult>.Success(Change("SetManager", request.Identity, true, "AD manager updated."), correlationId, status: "Updated"));
        }
        catch (Exception ex)
        {
            return Task.FromResult(OperationResult<ProviderChangeResult>.Failure(correlationId, new[] { OperationError.Create("AD.ManagerChange.Failed", $"AD manager update failed: {ex.Message}") }, status: "Failed"));
        }
    }

    public Task<OperationResult<ProviderChangeResult>> AddGroupMembershipAsync(MembershipChangeRequest request, CorrelationId correlationId, CancellationToken cancellationToken = default)
    {
        return ChangeGroupMembershipAsync(request, add: true, correlationId);
    }

    public Task<OperationResult<ProviderChangeResult>> RemoveGroupMembershipAsync(MembershipChangeRequest request, CorrelationId correlationId, CancellationToken cancellationToken = default)
    {
        return ChangeGroupMembershipAsync(request, add: false, correlationId);
    }
    public Task<OperationResult<ProviderChangeResult>> SetMailboxForwardingAsync(MailboxForwardingRequest request, CorrelationId correlationId, CancellationToken cancellationToken = default) => Unsupported(correlationId, "AD.ExchangeOwnedAttribute.Unsupported", "Mailbox forwarding remains Exchange-owned and is not changed through the AD provider.");
    public Task<OperationResult<ProviderChangeResult>> SetGalVisibilityAsync(GalVisibilityRequest request, CorrelationId correlationId, CancellationToken cancellationToken = default)
    {
        if (!_options.UseLiveDirectory) return Unsupported(correlationId, "AD.GalVisibility.RequiresLiveDirectory", "GAL visibility changes require live directory mode.");
        if (!_options.AllowWrites) return Unsupported(correlationId, "AD.GalVisibility.WritesDisabled", "AD writes are disabled for this runtime profile.");
        try
        {
            using var user = FindLiveEntry(request.Identity);
            if (user is null)
            {
                return Task.FromResult(OperationResult<ProviderChangeResult>.Failure(correlationId, new[] { OperationError.Create("AD.GalVisibility.NotFound", "User was not found.") }, status: "NotFound"));
            }

            var changed = SetBooleanProperty(user, "msExchHideFromAddressLists", request.HiddenFromAddressListsEnabled);
            if (changed)
            {
                user.CommitChanges();
            }

            return Task.FromResult(OperationResult<ProviderChangeResult>.Success(Change("SetGalVisibility", request.Identity, changed, changed ? "AD Exchange GAL visibility flag updated." : "GAL visibility already matched the requested state."), correlationId, status: changed ? "Updated" : "NoChange"));
        }
        catch (Exception ex)
        {
            return Task.FromResult(OperationResult<ProviderChangeResult>.Failure(correlationId, new[] { OperationError.Create("AD.GalVisibility.Failed", $"AD GAL visibility update failed: {ex.Message}") }, status: "Failed"));
        }
    }
    public Task<OperationResult<ProviderChangeResult>> AddMailboxDelegationAsync(MailboxDelegationChangeRequest request, CorrelationId correlationId, CancellationToken cancellationToken = default) => Unsupported(correlationId, "AD.ExchangeOwnedAttribute.Unsupported", "Exchange mailbox delegation is not changed through AD.");
    public Task<OperationResult<ProviderChangeResult>> ResetStateAsync(CorrelationId correlationId, CancellationToken cancellationToken = default) => Task.FromResult(OperationResult<ProviderChangeResult>.Success(new ProviderChangeResult { Operation = "ResetState", TargetId = "ActiveDirectory", Changed = false, Message = "Native AD provider has no local mutable state.", Source = "ActiveDirectory" }, correlationId));

    public Task<OperationResult<IReadOnlyList<DirectoryGroupSummary>>> SearchGroupsAsync(string query, CorrelationId correlationId, CancellationToken cancellationToken = default)
    {
        var error = Validate();
        if (error is not null) return Task.FromResult(OperationResult<IReadOnlyList<DirectoryGroupSummary>>.Failure(correlationId, new[] { error }, status: "Failed"));
        if (string.IsNullOrWhiteSpace(query))
        {
            return Task.FromResult(OperationResult<IReadOnlyList<DirectoryGroupSummary>>.Failure(correlationId, new[] { OperationError.Create("AD.GroupLookup.QueryRequired", "Group lookup query is required.") }));
        }

        if (!_options.UseLiveDirectory)
        {
            var groups = _users
                .SelectMany(user => user.Groups)
                .Distinct(StringComparer.OrdinalIgnoreCase)
                .Where(group => group.Contains(query, StringComparison.OrdinalIgnoreCase))
                .OrderBy(group => group, StringComparer.OrdinalIgnoreCase)
                .Select(group => new DirectoryGroupSummary { Id = group, DisplayName = group, Source = "ActiveDirectory" })
                .ToArray();
            return Task.FromResult(OperationResult<IReadOnlyList<DirectoryGroupSummary>>.Success(groups, correlationId, status: groups.Length == 0 ? "NoMatches" : "Loaded"));
        }

        try
        {
            using var root = CreateDirectoryRoot();
            using var searcher = new DirectorySearcher(root)
            {
                Filter = $"(&(objectCategory=group)(|(cn=*{EscapeFilter(query)}*)(sAMAccountName=*{EscapeFilter(query)}*)(mail=*{EscapeFilter(query)}*)))",
                PageSize = 50,
                SizeLimit = 50
            };
            AddGroupProperties(searcher);
            var groups = searcher.FindAll().Cast<SearchResult>().Select(MapGroup).OrderBy(group => group.DisplayName, StringComparer.OrdinalIgnoreCase).ToArray();
            return Task.FromResult(OperationResult<IReadOnlyList<DirectoryGroupSummary>>.Success(groups, correlationId, status: groups.Length == 0 ? "NoMatches" : "Loaded"));
        }
        catch (Exception ex)
        {
            return Task.FromResult(OperationResult<IReadOnlyList<DirectoryGroupSummary>>.Failure(correlationId, new[] { OperationError.Create("AD.GroupLookup.LiveQueryFailed", $"AD group lookup failed: {ex.Message}") }, status: "Failed"));
        }
    }

    private OperationError? Validate()
    {
        if (!_options.ConnectionAvailable) return OperationError.Create("AD.ConnectionFailed", "Active Directory connection failed.");
        if (!_options.AuthenticationSucceeded) return OperationError.Create("AD.AuthenticationFailed", "Active Directory authentication failed.");
        return null;
    }

    private static Task<OperationResult<ProviderChangeResult>> Unsupported(CorrelationId correlationId, string code, string message) =>
        Task.FromResult(OperationResult<ProviderChangeResult>.Failure(correlationId, new[] { OperationError.Create(code, message) }, status: "Unsupported"));

    private Task<OperationResult<ProviderChangeResult>> ChangeGroupMembershipAsync(MembershipChangeRequest request, bool add, CorrelationId correlationId)
    {
        if (!_options.UseLiveDirectory) return Unsupported(correlationId, "AD.GroupMembership.RequiresLiveDirectory", "AD group membership changes require live directory mode.");
        if (!_options.AllowWrites) return Unsupported(correlationId, "AD.GroupMembership.WritesDisabled", "AD writes are disabled for this runtime profile.");
        try
        {
            using var user = FindLiveEntry(request.Identity);
            using var group = FindLiveGroupEntry(request.Group);
            if (user is null || group is null)
            {
                return Task.FromResult(OperationResult<ProviderChangeResult>.Failure(correlationId, new[] { OperationError.Create("AD.GroupMembership.NotFound", "User or group was not found.") }, status: "NotFound"));
            }

            var userDn = user.Properties["distinguishedName"].Value?.ToString() ?? string.Empty;
            var members = group.Properties["member"];
            var exists = members.Cast<object>().Select(ConvertAttributeValue).Any(value => string.Equals(value, userDn, StringComparison.OrdinalIgnoreCase));
            if (add && !exists)
            {
                members.Add(userDn);
                group.CommitChanges();
            }
            else if (!add && exists)
            {
                members.Remove(userDn);
                group.CommitChanges();
            }

            var operation = add ? "AddGroupMembership" : "RemoveGroupMembership";
            var changed = add ? !exists : exists;
            return Task.FromResult(OperationResult<ProviderChangeResult>.Success(Change(operation, request.Identity, changed, changed ? "AD group membership updated." : "AD group membership already matched the requested state."), correlationId, status: changed ? "Updated" : "NoChange"));
        }
        catch (Exception ex)
        {
            return Task.FromResult(OperationResult<ProviderChangeResult>.Failure(correlationId, new[] { OperationError.Create("AD.GroupMembership.Failed", $"AD group membership update failed: {ex.Message}") }, status: "Failed"));
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
            Source = "ActiveDirectory"
        };
    }

    private OperationResult<IReadOnlyList<SimulatorUserSummary>> SearchLiveUsers(string query, CorrelationId correlationId)
    {
        if (string.IsNullOrWhiteSpace(query))
        {
            return OperationResult<IReadOnlyList<SimulatorUserSummary>>.Failure(
                correlationId,
                new[] { OperationError.Create("AD.UserLookup.QueryRequired", "Active Directory user lookup query is required.") });
        }

        try
        {
            using var root = CreateDirectoryRoot();
            using var searcher = new DirectorySearcher(root)
            {
                Filter = $"(&(objectCategory=person)(objectClass=user)(|(sAMAccountName=*{EscapeFilter(query)}*)(displayName=*{EscapeFilter(query)}*)(userPrincipalName=*{EscapeFilter(query)}*)(mail=*{EscapeFilter(query)}*)))",
                PageSize = 50,
                SizeLimit = 50
            };
            AddUserProperties(searcher);
            var results = searcher.FindAll();
            var users = results
                .Cast<SearchResult>()
                .Select(MapUser)
                .OrderBy(user => user.SamAccountName, StringComparer.OrdinalIgnoreCase)
                .ToArray();

            return OperationResult<IReadOnlyList<SimulatorUserSummary>>.Success(users, correlationId, status: users.Length == 0 ? "NoMatches" : "Loaded");
        }
        catch (Exception ex)
        {
            return OperationResult<IReadOnlyList<SimulatorUserSummary>>.Failure(
                correlationId,
                new[] { OperationError.Create("AD.LiveQueryFailed", $"Active Directory live query failed: {ex.Message}") },
                status: "Failed");
        }
    }

    private bool ApplyUserAttribute(DirectoryEntry user, string requestedName, string value)
    {
        var name = NormalizeWritableAttributeName(requestedName);
        if (string.IsNullOrWhiteSpace(name) || IsReadOnlyAttribute(name) || !IsWritableAttribute(name))
        {
            return false;
        }

        if (requestedName.Equals("Enabled", StringComparison.OrdinalIgnoreCase))
        {
            return SetEnabled(user, value);
        }

        if (requestedName.Equals("LockedOut", StringComparison.OrdinalIgnoreCase))
        {
            if (bool.TryParse(value, out var lockedOut) && !lockedOut)
            {
                return SetProperty(user, "lockoutTime", "0");
            }

            return false;
        }

        if (name.Equals("manager", StringComparison.OrdinalIgnoreCase))
        {
            if (string.IsNullOrWhiteSpace(value))
            {
                return ClearProperty(user, "manager");
            }

            using var manager = FindLiveEntry(value);
            if (manager is null)
            {
                return false;
            }

            return SetProperty(user, "manager", manager.Properties["distinguishedName"].Value?.ToString() ?? string.Empty);
        }

        if (IsMultiValuedAttribute(name))
        {
            return SetMultiValueProperty(user, name, SplitValues(value));
        }

        if (IsBooleanAttribute(name))
        {
            return bool.TryParse(value, out var parsed) && SetBooleanProperty(user, name, parsed);
        }

        return string.IsNullOrWhiteSpace(value)
            ? ClearProperty(user, name)
            : SetProperty(user, name, value);
    }

    private static string NormalizeWritableAttributeName(string requestedName)
    {
        return requestedName switch
        {
            "DisplayName" => "displayName",
            "GivenName" => "givenName",
            "Surname" => "sn",
            "SamAccountName" => "sAMAccountName",
            "UserPrincipalName" => "userPrincipalName",
            "Mail" => "mail",
            "Department" => "department",
            "Title" => "title",
            "Company" => "company",
            "Office" => "physicalDeliveryOfficeName",
            "Phone" => "telephoneNumber",
            "TelephoneNumber" => "telephoneNumber",
            "Mobile" => "mobile",
            "State" => "st",
            "City" => "l",
            "StreetAddress" => "streetAddress",
            "PostalCode" => "postalCode",
            "EmployeeId" => "employeeID",
            "EmployeeID" => "employeeID",
            "EmployeeNumber" => "employeeNumber",
            "BadgeID" => "BadgeID",
            "BadgeId" => "BadgeID",
            "MailNickname" => "mailNickname",
            "PrimarySmtpAddress" => "mail",
            "HiddenFromAddressListsEnabled" => "msExchHideFromAddressLists",
            "ManagerSamAccountName" => "manager",
            "Groups" => string.Empty,
            "DirectReportSamAccountNames" => string.Empty,
            _ => requestedName
        };
    }

    private static bool IsMultiValuedAttribute(string name)
    {
        return name.Equals("proxyAddresses", StringComparison.OrdinalIgnoreCase)
            || name.Equals("otherTelephone", StringComparison.OrdinalIgnoreCase)
            || name.Equals("otherMailbox", StringComparison.OrdinalIgnoreCase)
            || name.Equals("url", StringComparison.OrdinalIgnoreCase)
            || name.Equals("servicePrincipalName", StringComparison.OrdinalIgnoreCase)
            || name.Equals("showInAddressBook", StringComparison.OrdinalIgnoreCase)
            || name.Equals("publicDelegates", StringComparison.OrdinalIgnoreCase)
            || name.Equals("altSecurityIdentities", StringComparison.OrdinalIgnoreCase);
    }

    private static bool IsBooleanAttribute(string name)
    {
        return name.Equals("msExchHideFromAddressLists", StringComparison.OrdinalIgnoreCase);
    }

    private static bool IsWritableAttribute(string name)
    {
        return WritableUserAttributeNames.Contains(name);
    }

    private static bool SetProperty(DirectoryEntry entry, string name, string value)
    {
        var current = entry.Properties[name].Value?.ToString() ?? string.Empty;
        if (string.Equals(current, value ?? string.Empty, StringComparison.Ordinal))
        {
            return false;
        }

        entry.Properties[name].Value = value ?? string.Empty;
        return true;
    }

    private static bool SetBooleanProperty(DirectoryEntry entry, string name, bool value)
    {
        var currentValue = entry.Properties[name].Value;
        if (currentValue is bool currentBool && currentBool == value)
        {
            return false;
        }

        if (currentValue is string currentString && bool.TryParse(currentString, out var parsed) && parsed == value)
        {
            return false;
        }

        entry.Properties[name].Value = value;
        return true;
    }

    private static bool ClearProperty(DirectoryEntry entry, string name)
    {
        if (entry.Properties[name].Count == 0)
        {
            return false;
        }

        entry.Properties[name].Clear();
        return true;
    }

    private static bool SetMultiValueProperty(DirectoryEntry entry, string name, IReadOnlyList<string> values)
    {
        var property = entry.Properties[name];
        var current = property.Cast<object>().Select(ConvertAttributeValue).OrderBy(value => value, StringComparer.OrdinalIgnoreCase).ToArray();
        var next = values.Where(value => !string.IsNullOrWhiteSpace(value)).Distinct(StringComparer.OrdinalIgnoreCase).OrderBy(value => value, StringComparer.OrdinalIgnoreCase).ToArray();
        if (current.SequenceEqual(next, StringComparer.OrdinalIgnoreCase))
        {
            return false;
        }

        property.Clear();
        foreach (var value in next)
        {
            property.Add(value);
        }

        return true;
    }

    private static bool SetEnabled(DirectoryEntry user, string value)
    {
        if (!bool.TryParse(value, out var enabled))
        {
            return false;
        }

        var currentValue = user.Properties["userAccountControl"].Value?.ToString();
        var flags = int.TryParse(currentValue, out var parsed) ? parsed : 512;
        var next = enabled ? flags & ~0x2 : flags | 0x2;
        if (flags == next)
        {
            return false;
        }

        user.Properties["userAccountControl"].Value = next;
        return true;
    }

    private static IReadOnlyList<string> SplitValues(string value)
    {
        return (value ?? string.Empty)
            .Split(new[] { ';', '\r', '\n' }, StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries);
    }

    private OperationResult<IReadOnlyList<SimulatorUserSummary>> GetLiveDirectReports(string identity, CorrelationId correlationId)
    {
        try
        {
            var user = FindLiveUser(identity);
            if (user is null)
            {
                return OperationResult<IReadOnlyList<SimulatorUserSummary>>.Success(Array.Empty<SimulatorUserSummary>(), correlationId, status: "NoMatches");
            }

            var managerDn = GetFirst(user.Properties, "distinguishedName");
            using var root = CreateDirectoryRoot();
            using var searcher = new DirectorySearcher(root)
            {
                Filter = $"(&(objectCategory=person)(objectClass=user)(manager={EscapeFilter(managerDn)}))",
                PageSize = 50,
                SizeLimit = 200
            };
            AddUserProperties(searcher);
            var reports = searcher.FindAll().Cast<SearchResult>().Select(MapUser).OrderBy(item => item.SamAccountName, StringComparer.OrdinalIgnoreCase).ToArray();
            return OperationResult<IReadOnlyList<SimulatorUserSummary>>.Success(reports, correlationId);
        }
        catch (Exception ex)
        {
            return OperationResult<IReadOnlyList<SimulatorUserSummary>>.Failure(
                correlationId,
                new[] { OperationError.Create("AD.DirectReports.LiveQueryFailed", $"Active Directory direct report query failed: {ex.Message}") },
                status: "Failed");
        }
    }

    private OperationResult<DirectoryObjectAttributeSet> GetLiveDirectoryAttributes(SimulatorUserSummary user, CorrelationId correlationId)
    {
        try
        {
            var result = FindLiveUser(user.SamAccountName, loadDefaultProperties: false) ?? FindLiveUser(user.UserPrincipalName, loadDefaultProperties: false);
            if (result is null)
            {
                return OperationResult<DirectoryObjectAttributeSet>.Failure(
                    correlationId,
                    new[] { OperationError.Create("AD.DirectoryAttributes.NotFound", "User was not found.") },
                    status: "NotFound");
            }

            var attributes = result.Properties.PropertyNames
                .Cast<string>()
                .Concat(CommonUserAttributeNames())
                .Distinct(StringComparer.OrdinalIgnoreCase)
                .OrderBy(name => name, StringComparer.OrdinalIgnoreCase)
                .Select(name => new DirectoryAttributeValue
                {
                    Name = name,
                    DisplayName = name,
                    Values = GetValues(result.Properties, name),
                    IsSingleValued = !IsMultiValuedAttribute(name) && (!result.Properties.Contains(name) || result.Properties[name].Count <= 1),
                    IsReadOnly = IsReadOnlyAttribute(name) || !IsWritableAttribute(name),
                    Syntax = "DirectoryAttribute",
                    Source = "ActiveDirectory.LiveLdap"
                })
                .ToArray();

            return OperationResult<DirectoryObjectAttributeSet>.Success(
                new DirectoryObjectAttributeSet
                {
                    Identity = user.SamAccountName,
                    DistinguishedName = GetFirst(result.Properties, "distinguishedName"),
                    ObjectClass = "user",
                    SchemaSource = "ActiveDirectory.LiveLdap",
                    Attributes = attributes
                },
                correlationId,
                status: "Loaded");
        }
        catch (Exception ex)
        {
            return OperationResult<DirectoryObjectAttributeSet>.Failure(
                correlationId,
                new[] { OperationError.Create("AD.DirectoryAttributes.LiveQueryFailed", $"Active Directory attribute query failed: {ex.Message}") },
                status: "Failed");
        }
    }

    private SearchResult? FindLiveUser(string identity, bool loadDefaultProperties = true)
    {
        if (string.IsNullOrWhiteSpace(identity))
        {
            return null;
        }

        using var root = CreateDirectoryRoot();
        using var searcher = new DirectorySearcher(root)
        {
            Filter = $"(&(objectCategory=person)(objectClass=user)(|(sAMAccountName={EscapeFilter(identity)})(userPrincipalName={EscapeFilter(identity)})(mail={EscapeFilter(identity)})(distinguishedName={EscapeFilter(identity)})))",
            SizeLimit = 1
        };
        if (loadDefaultProperties)
        {
            AddUserProperties(searcher);
        }

        return searcher.FindOne();
    }

    private DirectoryEntry? FindLiveEntry(string identity)
    {
        return FindLiveUser(identity)?.GetDirectoryEntry();
    }

    private DirectoryEntry? FindLiveGroupEntry(string identity)
    {
        if (string.IsNullOrWhiteSpace(identity))
        {
            return null;
        }

        using var root = CreateDirectoryRoot();
        using var searcher = new DirectorySearcher(root)
        {
            Filter = $"(&(objectCategory=group)(|(cn={EscapeFilter(identity)})(sAMAccountName={EscapeFilter(identity)})(mail={EscapeFilter(identity)})(distinguishedName={EscapeFilter(identity)})))",
            SizeLimit = 1
        };
        AddGroupProperties(searcher);
        return searcher.FindOne()?.GetDirectoryEntry();
    }

    private DirectoryEntry CreateUserContainer()
    {
        if (!string.IsNullOrWhiteSpace(_options.DefaultUserContainer))
        {
            return new DirectoryEntry($"LDAP://{BuildServerPrefix()}{_options.DefaultUserContainer}", null, null, AuthenticationTypes.Secure);
        }

        var defaultNamingContext = GetDefaultNamingContext();
        if (!string.IsNullOrWhiteSpace(defaultNamingContext))
        {
            return new DirectoryEntry($"LDAP://{BuildServerPrefix()}CN=Users,{defaultNamingContext}", null, null, AuthenticationTypes.Secure);
        }

        return CreateDirectoryRoot();
    }

    private string BuildUserPrincipalName(string samAccountName)
    {
        var value = samAccountName.Trim();
        if (value.Contains('@', StringComparison.Ordinal))
        {
            return value;
        }

        var suffix = !string.IsNullOrWhiteSpace(_options.Domain)
            ? _options.Domain.Trim()
            : NamingContextToDnsName(GetDefaultNamingContext());

        return string.IsNullOrWhiteSpace(suffix) ? value : $"{value}@{suffix}";
    }

    private string GetDefaultNamingContext()
    {
        try
        {
            using var rootDse = new DirectoryEntry("LDAP://RootDSE", null, null, AuthenticationTypes.Secure);
            return rootDse.Properties["defaultNamingContext"].Value?.ToString() ?? string.Empty;
        }
        catch
        {
            return string.Empty;
        }
    }

    private string BuildServerPrefix()
    {
        return !string.IsNullOrWhiteSpace(_options.Server)
            ? $"{_options.Server.Trim()}/"
            : string.Empty;
    }

    private DirectoryEntry CreateDirectoryRoot()
    {
        var path = !string.IsNullOrWhiteSpace(_options.Server)
            ? $"LDAP://{_options.Server}"
            : !string.IsNullOrWhiteSpace(_options.Domain)
                ? $"LDAP://{_options.Domain}"
                : "LDAP://RootDSE";

        if (path.EndsWith("RootDSE", StringComparison.OrdinalIgnoreCase))
        {
            using var rootDse = new DirectoryEntry(path, null, null, AuthenticationTypes.Secure);
            var defaultNamingContext = rootDse.Properties["defaultNamingContext"].Value?.ToString();
            if (!string.IsNullOrWhiteSpace(defaultNamingContext))
            {
                path = $"LDAP://{defaultNamingContext}";
            }
        }

        return new DirectoryEntry(path, null, null, AuthenticationTypes.Secure);
    }

    private static void AddUserProperties(DirectorySearcher searcher)
    {
        foreach (var property in new[]
        {
            "displayName", "givenName", "sn", "sAMAccountName", "userPrincipalName", "mail",
            "department", "title", "company", "physicalDeliveryOfficeName", "employeeID",
            "BadgeID", "EmployeeNumber", "employeeNumber", "telephoneNumber", "mobile",
            "st", "l", "streetAddress", "postalCode", "distinguishedName", "manager",
            "directReports", "memberOf", "userAccountControl", "lockoutTime",
            "mailNickname", "proxyAddresses", "msExchHideFromAddressLists", "targetAddress"
        })
        {
            searcher.PropertiesToLoad.Add(property);
        }
    }

    private static void AddGroupProperties(DirectorySearcher searcher)
    {
        foreach (var property in new[]
        {
            "cn", "name", "displayName", "sAMAccountName", "mail",
            "distinguishedName", "objectSid", "groupType", "member"
        })
        {
            searcher.PropertiesToLoad.Add(property);
        }
    }

    private static SimulatorUserSummary MapUser(SearchResult result)
    {
        var properties = result.Properties;
        var sam = GetFirst(properties, "sAMAccountName");
        var userPrincipalName = GetFirst(properties, "userPrincipalName");
        return new SimulatorUserSummary
        {
            DisplayName = GetFirst(properties, "displayName"),
            GivenName = GetFirst(properties, "givenName"),
            Surname = GetFirst(properties, "sn"),
            SamAccountName = sam,
            UserPrincipalName = userPrincipalName,
            Mail = GetFirst(properties, "mail"),
            Department = GetFirst(properties, "department"),
            Title = GetFirst(properties, "title"),
            Company = GetFirst(properties, "company"),
            Office = GetFirst(properties, "physicalDeliveryOfficeName"),
            EmployeeId = FirstNonEmpty(GetFirst(properties, "BadgeID"), GetFirst(properties, "EmployeeNumber"), GetFirst(properties, "employeeNumber"), GetFirst(properties, "employeeID")),
            DistinguishedName = GetFirst(properties, "distinguishedName"),
            ManagerSamAccountName = GetFirst(properties, "manager"),
            DirectReportSamAccountNames = GetValues(properties, "directReports"),
            Groups = GetValues(properties, "memberOf").ToArray(),
            Enabled = !IsDisabled(GetFirst(properties, "userAccountControl")),
            LockedOut = !string.IsNullOrWhiteSpace(GetFirst(properties, "lockoutTime")) && GetFirst(properties, "lockoutTime") != "0",
            Source = "ActiveDirectory.LiveLdap"
        };
    }

    private static DirectoryGroupSummary MapGroup(SearchResult result)
    {
        var properties = result.Properties;
        var distinguishedName = GetFirst(properties, "distinguishedName");
        return new DirectoryGroupSummary
        {
            Id = FirstNonEmpty(distinguishedName, GetFirst(properties, "sAMAccountName"), GetFirst(properties, "cn")),
            DisplayName = FirstNonEmpty(GetFirst(properties, "displayName"), GetFirst(properties, "cn"), GetFirst(properties, "sAMAccountName"), ExtractCn(distinguishedName)),
            Mail = GetFirst(properties, "mail"),
            SecurityIdentifier = GetFirst(properties, "objectSid"),
            Source = "ActiveDirectory.LiveLdap"
        };
    }

    private static string EscapeFilter(string value)
    {
        return (value ?? string.Empty)
            .Replace("\\", "\\5c", StringComparison.Ordinal)
            .Replace("*", "\\2a", StringComparison.Ordinal)
            .Replace("(", "\\28", StringComparison.Ordinal)
            .Replace(")", "\\29", StringComparison.Ordinal)
            .Replace("\0", "\\00", StringComparison.Ordinal);
    }

    private static string EscapeRdn(string value)
    {
        var text = value.Trim()
            .Replace("\\", "\\\\", StringComparison.Ordinal)
            .Replace(",", "\\,", StringComparison.Ordinal)
            .Replace("+", "\\+", StringComparison.Ordinal)
            .Replace("\"", "\\\"", StringComparison.Ordinal)
            .Replace("<", "\\<", StringComparison.Ordinal)
            .Replace(">", "\\>", StringComparison.Ordinal)
            .Replace(";", "\\;", StringComparison.Ordinal)
            .Replace("=", "\\=", StringComparison.Ordinal);

        if (text.StartsWith(" ", StringComparison.Ordinal))
        {
            text = "\\" + text;
        }

        return text.EndsWith(" ", StringComparison.Ordinal)
            ? text[..^1] + "\\ "
            : text;
    }

    private static string NamingContextToDnsName(string namingContext)
    {
        if (string.IsNullOrWhiteSpace(namingContext))
        {
            return string.Empty;
        }

        return string.Join(
            ".",
            namingContext
                .Split(',', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries)
                .Where(part => part.StartsWith("DC=", StringComparison.OrdinalIgnoreCase))
                .Select(part => part[3..])
                .Where(part => !string.IsNullOrWhiteSpace(part)));
    }

    private static string GetFirst(ResultPropertyCollection properties, string name)
    {
        return properties.Contains(name) && properties[name].Count > 0
            ? ConvertAttributeValue(properties[name][0])
            : string.Empty;
    }

    private static IReadOnlyList<string> GetValues(ResultPropertyCollection properties, string name)
    {
        return properties.Contains(name)
            ? properties[name].Cast<object>().Select(ConvertAttributeValue).Where(value => !string.IsNullOrWhiteSpace(value)).ToArray()
            : Array.Empty<string>();
    }

    private static string ConvertAttributeValue(object? value)
    {
        return value switch
        {
            null => string.Empty,
            byte[] bytes => Convert.ToBase64String(bytes),
            _ => value.ToString() ?? string.Empty
        };
    }

    private static bool IsDisabled(string userAccountControl)
    {
        return int.TryParse(userAccountControl, out var value) && (value & 0x2) == 0x2;
    }

    private static bool IsReadOnlyAttribute(string name)
    {
        return name.Equals("distinguishedName", StringComparison.OrdinalIgnoreCase)
            || name.Equals("canonicalName", StringComparison.OrdinalIgnoreCase)
            || name.Equals("objectCategory", StringComparison.OrdinalIgnoreCase)
            || name.Equals("objectClass", StringComparison.OrdinalIgnoreCase)
            || name.Equals("objectGUID", StringComparison.OrdinalIgnoreCase)
            || name.Equals("objectSid", StringComparison.OrdinalIgnoreCase)
            || name.Equals("memberOf", StringComparison.OrdinalIgnoreCase)
            || name.Equals("directReports", StringComparison.OrdinalIgnoreCase)
            || name.Equals("whenCreated", StringComparison.OrdinalIgnoreCase)
            || name.Equals("whenChanged", StringComparison.OrdinalIgnoreCase)
            || name.Equals("uSNCreated", StringComparison.OrdinalIgnoreCase)
            || name.Equals("uSNChanged", StringComparison.OrdinalIgnoreCase)
            || name.StartsWith("lastLogon", StringComparison.OrdinalIgnoreCase)
            || name.Equals("badPwdCount", StringComparison.OrdinalIgnoreCase)
            || name.Equals("badPasswordTime", StringComparison.OrdinalIgnoreCase);
    }

    private static string ExtractCn(string distinguishedName)
    {
        const string prefix = "CN=";
        if (!distinguishedName.StartsWith(prefix, StringComparison.OrdinalIgnoreCase))
        {
            return distinguishedName;
        }

        var comma = distinguishedName.IndexOf(',', StringComparison.Ordinal);
        return comma > 3 ? distinguishedName.Substring(3, comma - 3) : distinguishedName[3..];
    }

    private static string FirstNonEmpty(params string[] values)
    {
        return values.FirstOrDefault(value => !string.IsNullOrWhiteSpace(value)) ?? string.Empty;
    }

    private static IReadOnlyList<string> CommonUserAttributeNames()
    {
        return new[]
        {
            "accountExpires", "adminDescription", "assistant", "c", "cn", "co", "company",
            "countryCode", "department", "departmentNumber", "description", "displayName",
            "displayNamePrintable", "division", "employeeID", "employeeNumber", "EmployeeNumber",
            "BadgeID", "facsimileTelephoneNumber", "givenName", "homeDirectory", "homeDrive",
            "homePhone", "initials", "info", "ipPhone", "l", "mail", "mailNickname", "manager",
            "middleName", "mobile", "objectCategory", "objectClass", "otherMailbox",
            "otherTelephone", "pager", "physicalDeliveryOfficeName", "postalAddress",
            "postalCode", "postOfficeBox", "proxyAddresses", "sAMAccountName", "scriptPath",
            "sn", "st", "streetAddress", "telephoneNumber", "title", "url",
            "userAccountControl", "userPrincipalName", "wWWHomePage", "extensionAttribute1",
            "extensionAttribute2", "extensionAttribute3", "extensionAttribute4", "extensionAttribute5",
            "extensionAttribute6", "extensionAttribute7", "extensionAttribute8", "extensionAttribute9",
            "extensionAttribute10", "extensionAttribute11", "extensionAttribute12", "extensionAttribute13",
            "extensionAttribute14", "extensionAttribute15", "targetAddress", "legacyExchangeDN",
            "msExchHideFromAddressLists", "msExchRecipientDisplayType", "msExchRecipientTypeDetails",
            "msExchRemoteRecipientType", "showInAddressBook", "altRecipient", "deliverAndRedirect",
            "publicDelegates", "msExchMailboxGuid", "msExchHomeServerName", "homeMDB", "homeMTA"
        };
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
            Attribute("employeeID", string.Empty),
            Attribute("BadgeID", string.Empty),
            Attribute("EmployeeNumber", string.Empty),
            Attribute("employeeNumber", string.Empty),
            Attribute("manager", user.ManagerSamAccountName),
            Attribute("directReports", user.DirectReportSamAccountNames, isSingleValued: false, isReadOnly: true),
            Attribute("memberOf", user.Groups, isSingleValued: false, isReadOnly: true),
            Attribute("distinguishedName", user.DistinguishedName, isReadOnly: true),
            Attribute("objectClass", new[] { "top", "person", "organizationalPerson", "user" }, isSingleValued: false, isReadOnly: true),
            Attribute("objectGUID", user.SamAccountName, isReadOnly: true),
            Attribute("objectSid", user.SamAccountName, isReadOnly: true),
            Attribute("userAccountControl", user.Enabled ? "512" : "514"),
            Attribute("lockoutTime", user.LockedOut ? "1" : "0"),
            Attribute("msExchHideFromAddressLists", "False"),
            Attribute("targetAddress", string.Empty),
            Attribute("legacyExchangeDN", string.Empty),
            Attribute("msExchRecipientDisplayType", string.Empty),
            Attribute("msExchRecipientTypeDetails", string.Empty),
            Attribute("msExchRemoteRecipientType", string.Empty)
        };
    }

    private static DirectoryAttributeValue Attribute(string name, string value, bool isSingleValued = true, bool isReadOnly = false, string syntax = "String")
    {
        return Attribute(name, string.IsNullOrWhiteSpace(value) ? Array.Empty<string>() : new[] { value }, isSingleValued, isReadOnly, syntax);
    }

    private static DirectoryAttributeValue Attribute(string name, IReadOnlyList<string> values, bool isSingleValued = true, bool isReadOnly = false, string syntax = "String")
    {
        return new DirectoryAttributeValue
        {
            Name = name,
            DisplayName = name,
            Values = values,
            IsSingleValued = isSingleValued,
            IsReadOnly = isReadOnly,
            Syntax = syntax,
            Source = "ActiveDirectory"
        };
    }
}
