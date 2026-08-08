using HAP.Providers.Abstractions;

namespace HAP.Providers.Simulator;

internal static class DirectorySimulatorSeedData
{
    public static IReadOnlyList<SimulatorUserSummary> Users { get; } = new[]
    {
        Create("Robert", "Williams", "rwilliams", "Information Technology", "Director of Infrastructure", string.Empty, new[] { "treed" }, new[] { "GG-IT-Leadership", "GG-Change-Approvers", "GG-VPN" }),
        Create("Taylor", "Reed", "treed", "Information Technology", "IT Manager", "rwilliams", new[] { "amorgan", "jlee" }, new[] { "GG-IT-Managers", "GG-RemoteDesktopUsers", "GG-LAPS", "GG-VPN" }),
        Create("Alex", "Morgan", "amorgan", "Information Technology", "Systems Administrator", "treed", Array.Empty<string>(), new[] { "Domain Users", "GG-IT-Administrators", "GG-RemoteDesktopUsers", "GG-LAPS", "GG-VPN" }),
        Create("Jordan", "Lee", "jlee", "Operations", "Operations Analyst", "treed", Array.Empty<string>(), new[] { "Domain Users", "GG-Operations", "GG-ReportReaders", "GG-VPN" })
    };

    public static SimulatorUserSummary PartialUser { get; } = new()
    {
        DisplayName = "Partial User",
        SamAccountName = "partialuser",
        UserPrincipalName = "partialuser@littleinnovation.tech",
        Mail = "partialuser@littleinnovation.tech",
        Source = "DirectorySimulator",
        Enabled = true
    };

    private static SimulatorUserSummary Create(
        string firstName,
        string lastName,
        string samAccountName,
        string department,
        string title,
        string managerSamAccountName,
        IReadOnlyList<string> directReports,
        IReadOnlyList<string> groups)
    {
        var displayName = $"{firstName} {lastName}";
        return new SimulatorUserSummary
        {
            DisplayName = displayName,
            GivenName = firstName,
            Surname = lastName,
            SamAccountName = samAccountName,
            UserPrincipalName = $"{samAccountName}@littleinnovation.tech",
            Mail = $"{samAccountName}@littleinnovation.tech",
            Department = department,
            Title = title,
            Company = "Little Innovation",
            Office = "Charleston",
            EmployeeId = $"SIM-{samAccountName.ToUpperInvariant()}",
            DistinguishedName = $"CN={displayName},OU=Users,OU={department},OU=LittleInnovation,DC=littleinnovation,DC=tech",
            ManagerSamAccountName = managerSamAccountName,
            DirectReportSamAccountNames = directReports,
            Groups = groups,
            Enabled = true,
            LockedOut = false,
            Source = "DirectorySimulator"
        };
    }
}
