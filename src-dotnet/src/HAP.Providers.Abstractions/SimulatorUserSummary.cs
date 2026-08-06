namespace HAP.Providers.Abstractions;

public sealed record SimulatorUserSummary
{
    public string DisplayName { get; init; } = string.Empty;

    public string GivenName { get; init; } = string.Empty;

    public string Surname { get; init; } = string.Empty;

    public string SamAccountName { get; init; } = string.Empty;

    public string UserPrincipalName { get; init; } = string.Empty;

    public string Mail { get; init; } = string.Empty;

    public string Department { get; init; } = string.Empty;

    public string Title { get; init; } = string.Empty;

    public string Company { get; init; } = string.Empty;

    public string Office { get; init; } = string.Empty;

    public string EmployeeId { get; init; } = string.Empty;

    public string DistinguishedName { get; init; } = string.Empty;

    public string ManagerSamAccountName { get; init; } = string.Empty;

    public IReadOnlyList<string> DirectReportSamAccountNames { get; init; } = Array.Empty<string>();

    public IReadOnlyList<string> Groups { get; init; } = Array.Empty<string>();

    public bool Enabled { get; init; }

    public bool LockedOut { get; init; }

    public string Source { get; init; } = string.Empty;
}
