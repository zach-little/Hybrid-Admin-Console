namespace HAP.Providers.Abstractions;

public sealed record ProviderChangeResult
{
    public string Operation { get; init; } = string.Empty;

    public string TargetId { get; init; } = string.Empty;

    public bool Changed { get; init; }

    public string Message { get; init; } = string.Empty;

    public string Source { get; init; } = string.Empty;
}

public sealed record UserCreateRequest
{
    public string GivenName { get; init; } = string.Empty;

    public string Surname { get; init; } = string.Empty;

    public string SamAccountName { get; init; } = string.Empty;

    public string Department { get; init; } = string.Empty;

    public string Title { get; init; } = string.Empty;

    public string ManagerSamAccountName { get; init; } = string.Empty;

    public string Office { get; init; } = string.Empty;

    public string DisplayName { get; init; } = string.Empty;

    public string UserPrincipalName { get; init; } = string.Empty;

    public string TargetOu { get; init; } = string.Empty;

    public string Company { get; init; } = string.Empty;

    public string EmployeeId { get; init; } = string.Empty;

    public string BadgeId { get; init; } = string.Empty;

    public string OfficePhone { get; init; } = string.Empty;

    public string MobilePhone { get; init; } = string.Empty;

    public string City { get; init; } = string.Empty;

    public string StreetAddress { get; init; } = string.Empty;

    public string State { get; init; } = string.Empty;

    public string PostalCode { get; init; } = string.Empty;

    public string TemporaryPassword { get; init; } = string.Empty;

    public IReadOnlyDictionary<string, string> OtherAttributes { get; init; } = new Dictionary<string, string>();
}

public sealed record UserUpdateRequest
{
    public string Identity { get; init; } = string.Empty;

    public IReadOnlyDictionary<string, string> Attributes { get; init; } = new Dictionary<string, string>();
}

public sealed record MembershipChangeRequest
{
    public string Identity { get; init; } = string.Empty;

    public string Group { get; init; } = string.Empty;
}

public sealed record ManagerChangeRequest
{
    public string Identity { get; init; } = string.Empty;

    public string ManagerIdentity { get; init; } = string.Empty;
}

public sealed record MailboxForwardingRequest
{
    public string Identity { get; init; } = string.Empty;

    public string ForwardingSmtpAddress { get; init; } = string.Empty;

    public bool DeliverToMailboxAndForward { get; init; }
}

public sealed record GalVisibilityRequest
{
    public string Identity { get; init; } = string.Empty;

    public bool HiddenFromAddressListsEnabled { get; init; }
}

public sealed record MailboxDelegationChangeRequest
{
    public string Identity { get; init; } = string.Empty;

    public string Trustee { get; init; } = string.Empty;

    public string AccessRights { get; init; } = "FullAccess";
}

public sealed record MailboxProvisioningRequest
{
    public string Identity { get; init; } = string.Empty;

    public string RemoteRoutingAddress { get; init; } = string.Empty;

    public string PrimarySmtpAddress { get; init; } = string.Empty;
}
