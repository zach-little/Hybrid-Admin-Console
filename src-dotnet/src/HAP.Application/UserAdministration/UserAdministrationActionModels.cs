using HAP.Providers.Abstractions;

namespace HAP.Application.UserAdministration;

public sealed record UserAdministrationActionRequest
{
    public string ActionId { get; init; } = string.Empty;

    public string ProviderId { get; init; } = string.Empty;

    public string Identity { get; init; } = string.Empty;

    public string Value { get; init; } = string.Empty;
}

public sealed record UserAdministrationActionResult
{
    public string ActionId { get; init; } = string.Empty;

    public string ProviderId { get; init; } = string.Empty;

    public bool Available { get; init; }

    public ProviderChangeResult? Change { get; init; }

    public string Message { get; init; } = string.Empty;
}

public static class UserAdministrationActionIds
{
    public const string ChangeManager = "ChangeManager";
    public const string AddGroupMembership = "AddGroupMembership";
    public const string RemoveGroupMembership = "RemoveGroupMembership";
    public const string SetMailboxForwarding = "SetMailboxForwarding";
}
