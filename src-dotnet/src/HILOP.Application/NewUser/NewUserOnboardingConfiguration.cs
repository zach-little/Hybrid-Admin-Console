using System.Text.Json;
using System.Text.Json.Serialization;

namespace HILOP.Application.NewUser;

public sealed record NewUserOnboardingConfiguration
{
    private static readonly JsonSerializerOptions JsonOptions = new()
    {
        PropertyNameCaseInsensitive = true,
        ReadCommentHandling = JsonCommentHandling.Skip,
        AllowTrailingCommas = true
    };

    public NewUserOnboardingDefaults Defaults { get; init; } = new();

    public IReadOnlyList<NewUserDepartmentOption> Departments { get; init; } = Array.Empty<NewUserDepartmentOption>();

    public IReadOnlyList<NewUserLocationOption> Locations { get; init; } = Array.Empty<NewUserLocationOption>();

    public IReadOnlyList<NewUserHomeOrganizationOption> HomeOrganizations { get; init; } = Array.Empty<NewUserHomeOrganizationOption>();

    public NewUserGroupConfiguration Groups { get; init; } = new();

    public IReadOnlyList<NewUserAttributeMapping> AttributeMappings { get; init; } = Array.Empty<NewUserAttributeMapping>();

    public NewUserMailboxConfiguration Mailbox { get; init; } = new();

    public IReadOnlyList<NewUserCustomPowerShellStep> CustomPowerShellSteps { get; init; } = Array.Empty<NewUserCustomPowerShellStep>();

    public static NewUserOnboardingConfiguration FromProfileJson(string? json, string? departmentList = null, string? locationList = null)
    {
        var configuration = TryDeserialize(json) ?? new NewUserOnboardingConfiguration();
        if (!string.IsNullOrWhiteSpace(departmentList) && configuration.Departments.Count == 0)
        {
            configuration = configuration with { Departments = SplitList(departmentList).Select(value => new NewUserDepartmentOption { Key = value, Display = value }).ToArray() };
        }

        if (!string.IsNullOrWhiteSpace(locationList) && configuration.Locations.Count == 0)
        {
            configuration = configuration with { Locations = SplitList(locationList).Select(value => new NewUserLocationOption { Key = value, Display = value }).ToArray() };
        }

        return configuration.Normalize();
    }

    public NewUserResolvedOnboarding Resolve(NewUserPreflightRequest request)
    {
        var department = FindDepartment(request.Department);
        var location = FindLocation(request.Office);
        var homeOrganization = FindHomeOrganization(request.HomeOrganization);
        var sam = request.SamAccountName.Trim();
        var displayName = FirstNonEmpty($"{request.GivenName.Trim()} {request.Surname.Trim()}".Trim(), sam);
        var upnSuffix = Defaults.UpnSuffix.TrimStart('@');
        var userPrincipalName = !string.IsNullOrWhiteSpace(upnSuffix) && !sam.Contains('@', StringComparison.Ordinal)
            ? $"{sam}@{upnSuffix}"
            : sam;
        var targetOu = ResolveTargetOu(department, location);
        var remoteRoutingDomain = FirstNonEmpty(Mailbox.RemoteRoutingDomain, Defaults.RemoteRoutingDomain).TrimStart('@');

        return new NewUserResolvedOnboarding
        {
            DisplayName = displayName,
            UserPrincipalName = userPrincipalName,
            TargetOu = targetOu,
            Company = Defaults.Company,
            City = location?.City ?? string.Empty,
            StreetAddress = location?.StreetAddress ?? string.Empty,
            State = location?.State ?? location?.StateField ?? string.Empty,
            PostalCode = location?.PostalCode ?? string.Empty,
            RemoteRoutingAddress = string.IsNullOrWhiteSpace(remoteRoutingDomain) ? string.Empty : $"{sam}@{remoteRoutingDomain}",
            Groups = ResolveGroups(request, department, location, homeOrganization),
            AdditionalAttributes = ResolveAttributes(request, department, location),
            CustomPowerShellSteps = CustomPowerShellSteps.Where(step => step.Enabled).ToArray()
        };
    }

    private NewUserOnboardingConfiguration Normalize()
    {
        return this with
        {
            Defaults = Defaults.Normalize(),
            Departments = Departments.Select(department => department.Normalize()).Where(option => !string.IsNullOrWhiteSpace(option.Display)).ToArray(),
            Locations = Locations.Select(location => location.Normalize()).Where(option => !string.IsNullOrWhiteSpace(option.Display)).ToArray(),
            HomeOrganizations = HomeOrganizations.Select(homeOrganization => homeOrganization.Normalize()).Where(option => !string.IsNullOrWhiteSpace(option.Display)).ToArray(),
            Groups = Groups.Normalize(),
            AttributeMappings = AttributeMappings.Select(mapping => mapping.Normalize()).Where(mapping => !string.IsNullOrWhiteSpace(mapping.Name)).ToArray(),
            Mailbox = Mailbox.Normalize(),
            CustomPowerShellSteps = CustomPowerShellSteps.Select(step => step.Normalize()).Where(step => !string.IsNullOrWhiteSpace(step.Id)).ToArray()
        };
    }

    private static NewUserOnboardingConfiguration? TryDeserialize(string? json)
    {
        if (string.IsNullOrWhiteSpace(json))
        {
            return null;
        }

        try
        {
            return JsonSerializer.Deserialize<NewUserOnboardingConfiguration>(json, JsonOptions);
        }
        catch (JsonException)
        {
            return null;
        }
    }

    private NewUserDepartmentOption? FindDepartment(string value)
    {
        return Departments.FirstOrDefault(option => option.Matches(value));
    }

    private NewUserLocationOption? FindLocation(string value)
    {
        return Locations.FirstOrDefault(option => option.Matches(value));
    }

    private NewUserHomeOrganizationOption? FindHomeOrganization(string value)
    {
        return HomeOrganizations.FirstOrDefault(option => option.Matches(value));
    }

    private string ResolveTargetOu(NewUserDepartmentOption? department, NewUserLocationOption? location)
    {
        if (department is null)
        {
            return Defaults.DefaultTargetOu;
        }

        var locationKeys = new[] { location?.OuKey, location?.Key, location?.Number, location?.Display }
            .Where(value => !string.IsNullOrWhiteSpace(value))
            .Select(value => value!)
            .ToArray();

        foreach (var key in locationKeys)
        {
            if (department.TargetOuByLocation.TryGetValue(key, out var targetOu) && !string.IsNullOrWhiteSpace(targetOu))
            {
                return targetOu;
            }
        }

        return FirstNonEmpty(department.TargetOu, Defaults.DefaultTargetOu);
    }

    private IReadOnlyList<string> ResolveGroups(
        NewUserPreflightRequest request,
        NewUserDepartmentOption? department,
        NewUserLocationOption? location,
        NewUserHomeOrganizationOption? homeOrganization)
    {
        var groups = new List<string>();
        groups.AddRange(Groups.Always);
        AddIfNotBlank(groups, location?.GroupName ?? location?.LocationGroup);
        groups.AddRange(department?.DefaultGroups ?? Array.Empty<string>());
        AddIfNotBlank(groups, homeOrganization?.GroupName ?? homeOrganization?.DisplayGroupName);
        if (request.RequiresCac)
        {
            AddIfNotBlank(groups, Groups.CacGroup);
        }

        return groups
            .Where(value => !string.IsNullOrWhiteSpace(value))
            .Select(value => value.Trim())
            .Distinct(StringComparer.OrdinalIgnoreCase)
            .ToArray();
    }

    private IReadOnlyDictionary<string, string> ResolveAttributes(
        NewUserPreflightRequest request,
        NewUserDepartmentOption? department,
        NewUserLocationOption? location)
    {
        var attributes = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
        AddAttribute(attributes, "employeeID", request.EmployeeId);
        AddAttribute(attributes, "badgeID", request.BadgeId);
        AddAttribute(attributes, "telephoneNumber", request.OfficePhone);
        AddAttribute(attributes, "mobile", request.MobilePhone);

        foreach (var mapping in AttributeMappings)
        {
            AddAttribute(attributes, mapping.Name, ExpandTemplate(mapping.Value, request, department, location));
        }

        return attributes;
    }

    private static string ExpandTemplate(
        string template,
        NewUserPreflightRequest request,
        NewUserDepartmentOption? department,
        NewUserLocationOption? location)
    {
        return template
            .Replace("{{GivenName}}", request.GivenName, StringComparison.OrdinalIgnoreCase)
            .Replace("{{Surname}}", request.Surname, StringComparison.OrdinalIgnoreCase)
            .Replace("{{SamAccountName}}", request.SamAccountName, StringComparison.OrdinalIgnoreCase)
            .Replace("{{Department}}", request.Department, StringComparison.OrdinalIgnoreCase)
            .Replace("{{DepartmentKey}}", department?.Key ?? string.Empty, StringComparison.OrdinalIgnoreCase)
            .Replace("{{Title}}", request.Title, StringComparison.OrdinalIgnoreCase)
            .Replace("{{Office}}", request.Office, StringComparison.OrdinalIgnoreCase)
            .Replace("{{LocationKey}}", location?.Key ?? string.Empty, StringComparison.OrdinalIgnoreCase)
            .Replace("{{EmployeeId}}", request.EmployeeId, StringComparison.OrdinalIgnoreCase)
            .Replace("{{BadgeId}}", request.BadgeId, StringComparison.OrdinalIgnoreCase);
    }

    private static IReadOnlyList<string> SplitList(string value)
    {
        return value
            .Split(new[] { ',', ';', '\r', '\n' }, StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries)
            .Where(item => !string.IsNullOrWhiteSpace(item))
            .ToArray();
    }

    private static void AddAttribute(IDictionary<string, string> attributes, string name, string? value)
    {
        if (!string.IsNullOrWhiteSpace(name) && !string.IsNullOrWhiteSpace(value))
        {
            attributes[name.Trim()] = value.Trim();
        }
    }

    private static void AddIfNotBlank(ICollection<string> values, string? value)
    {
        if (!string.IsNullOrWhiteSpace(value))
        {
            values.Add(value);
        }
    }

    private static string FirstNonEmpty(params string?[] values)
    {
        return values.FirstOrDefault(value => !string.IsNullOrWhiteSpace(value))?.Trim() ?? string.Empty;
    }
}

public sealed record NewUserOnboardingDefaults
{
    public string UpnSuffix { get; init; } = string.Empty;

    public string Company { get; init; } = string.Empty;

    public string DefaultTargetOu { get; init; } = string.Empty;

    public string RemoteRoutingDomain { get; init; } = string.Empty;

    public NewUserOnboardingDefaults Normalize() => this with
    {
        UpnSuffix = UpnSuffix.Trim(),
        Company = Company.Trim(),
        DefaultTargetOu = DefaultTargetOu.Trim(),
        RemoteRoutingDomain = RemoteRoutingDomain.Trim()
    };
}

public sealed record NewUserDepartmentOption
{
    public string Key { get; init; } = string.Empty;

    public string Number { get; init; } = string.Empty;

    public string Name { get; init; } = string.Empty;

    public string Display { get; init; } = string.Empty;

    public string TargetOu { get; init; } = string.Empty;

    public IReadOnlyDictionary<string, string> TargetOuByLocation { get; init; } = new Dictionary<string, string>();

    public bool IsServiceAccount { get; init; }

    public IReadOnlyList<string> DefaultGroups { get; init; } = Array.Empty<string>();

    public NewUserDepartmentOption Normalize() => this with
    {
        Key = FirstNonEmpty(Key, Name, Display, Number),
        Display = FirstNonEmpty(Display, Name, Key, Number),
        TargetOuByLocation = TargetOuByLocation.ToDictionary(pair => pair.Key.Trim(), pair => pair.Value.Trim(), StringComparer.OrdinalIgnoreCase),
        DefaultGroups = DefaultGroups.Where(value => !string.IsNullOrWhiteSpace(value)).Select(value => value.Trim()).ToArray()
    };

    public bool Matches(string value) => NewUserOptionMatching.MatchesAny(value, Key, Number, Name, Display);

    private static string FirstNonEmpty(params string?[] values) => values.FirstOrDefault(value => !string.IsNullOrWhiteSpace(value))?.Trim() ?? string.Empty;
}

public sealed record NewUserLocationOption
{
    public string Key { get; init; } = string.Empty;

    public string Number { get; init; } = string.Empty;

    public string Name { get; init; } = string.Empty;

    public string Display { get; init; } = string.Empty;

    public string OuKey { get; init; } = string.Empty;

    public string GroupName { get; init; } = string.Empty;

    public string LocationGroup { get; init; } = string.Empty;

    public string City { get; init; } = string.Empty;

    public string StreetAddress { get; init; } = string.Empty;

    public string State { get; init; } = string.Empty;

    [JsonPropertyName("StateField")]
    public string StateField { get; init; } = string.Empty;

    public string PostalCode { get; init; } = string.Empty;

    public NewUserLocationOption Normalize() => this with
    {
        Key = FirstNonEmpty(Key, Name, Display, Number),
        Display = FirstNonEmpty(Display, Name, Key, Number),
        OuKey = FirstNonEmpty(OuKey, Key, Number, Display)
    };

    public bool Matches(string value) => NewUserOptionMatching.MatchesAny(value, Key, Number, Name, Display);

    private static string FirstNonEmpty(params string?[] values) => values.FirstOrDefault(value => !string.IsNullOrWhiteSpace(value))?.Trim() ?? string.Empty;
}

public sealed record NewUserHomeOrganizationOption
{
    public string Key { get; init; } = string.Empty;

    public string Name { get; init; } = string.Empty;

    public string Display { get; init; } = string.Empty;

    public string GroupName { get; init; } = string.Empty;

    public string DisplayGroupName { get; init; } = string.Empty;

    public NewUserHomeOrganizationOption Normalize() => this with
    {
        Key = FirstNonEmpty(Key, Name, Display),
        Display = FirstNonEmpty(Display, Name, Key)
    };

    public bool Matches(string value) => NewUserOptionMatching.MatchesAny(value, Key, Name, Display);

    private static string FirstNonEmpty(params string?[] values) => values.FirstOrDefault(value => !string.IsNullOrWhiteSpace(value))?.Trim() ?? string.Empty;
}

public sealed record NewUserGroupConfiguration
{
    public IReadOnlyList<string> Always { get; init; } = Array.Empty<string>();

    public string CacGroup { get; init; } = string.Empty;

    public string CgUsersSc { get; init; } = string.Empty;

    public string CgUsersSd { get; init; } = string.Empty;

    public string CgUsersVa { get; init; } = string.Empty;

    public NewUserGroupConfiguration Normalize()
    {
        var always = Always.Where(value => !string.IsNullOrWhiteSpace(value)).Select(value => value.Trim()).ToList();
        foreach (var legacyGroup in new[] { CgUsersSc, CgUsersSd, CgUsersVa })
        {
            if (!string.IsNullOrWhiteSpace(legacyGroup))
            {
                always.Add(legacyGroup.Trim());
            }
        }

        return this with
        {
            Always = always.Distinct(StringComparer.OrdinalIgnoreCase).ToArray(),
            CacGroup = CacGroup.Trim()
        };
    }
}

public sealed record NewUserAttributeMapping
{
    public string Name { get; init; } = string.Empty;

    public string Value { get; init; } = string.Empty;

    public NewUserAttributeMapping Normalize() => this with { Name = Name.Trim(), Value = Value.Trim() };
}

public sealed record NewUserMailboxConfiguration
{
    public bool CreateRemoteMailboxWhenRequested { get; init; } = true;

    public string RemoteRoutingDomain { get; init; } = string.Empty;

    public NewUserMailboxConfiguration Normalize() => this with { RemoteRoutingDomain = RemoteRoutingDomain.Trim() };
}

public sealed record NewUserCustomPowerShellStep
{
    public string Id { get; init; } = string.Empty;

    public string DisplayName { get; init; } = string.Empty;

    public string Phase { get; init; } = "AfterDirectory";

    public bool Enabled { get; init; }

    public string Command { get; init; } = string.Empty;

    public int TimeoutSeconds { get; init; } = 300;

    public NewUserCustomPowerShellStep Normalize() => this with
    {
        Id = Id.Trim(),
        DisplayName = string.IsNullOrWhiteSpace(DisplayName) ? Id.Trim() : DisplayName.Trim(),
        Phase = string.IsNullOrWhiteSpace(Phase) ? "AfterDirectory" : Phase.Trim(),
        Command = Command.Trim(),
        TimeoutSeconds = TimeoutSeconds <= 0 ? 300 : TimeoutSeconds
    };
}

internal static class NewUserOptionMatching
{
    public static bool MatchesAny(string value, params string?[] candidates)
    {
        if (string.IsNullOrWhiteSpace(value))
        {
            return false;
        }

        var trimmed = value.Trim();
        return candidates.Any(candidate => string.Equals(candidate?.Trim(), trimmed, StringComparison.OrdinalIgnoreCase));
    }
}
