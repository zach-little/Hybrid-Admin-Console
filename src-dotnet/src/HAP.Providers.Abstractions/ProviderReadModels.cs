namespace HAP.Providers.Abstractions;

public sealed record DirectoryGroupSummary
{
    public string Id { get; init; } = string.Empty;

    public string DisplayName { get; init; } = string.Empty;

    public string Mail { get; init; } = string.Empty;

    public string SecurityIdentifier { get; init; } = string.Empty;

    public string Source { get; init; } = string.Empty;
}

public sealed record LicenseAssignmentSummary
{
    public string SkuId { get; init; } = string.Empty;

    public string SkuPartNumber { get; init; } = string.Empty;

    public string FriendlyName { get; init; } = string.Empty;

    public string AssignmentState { get; init; } = string.Empty;

    public string Source { get; init; } = string.Empty;
}

public sealed record MailboxSummary
{
    public string DisplayName { get; init; } = string.Empty;

    public string PrimarySmtpAddress { get; init; } = string.Empty;

    public string UserPrincipalName { get; init; } = string.Empty;

    public string RecipientTypeDetails { get; init; } = string.Empty;

    public string ExchangeGuid { get; init; } = string.Empty;

    public bool HiddenFromAddressListsEnabled { get; init; }

    public bool LitigationHoldEnabled { get; init; }

    public bool DeliverToMailboxAndForward { get; init; }

    public string ForwardingSmtpAddress { get; init; } = string.Empty;

    public string Source { get; init; } = string.Empty;
}

public sealed record MailboxStatisticsSummary
{
    public string DisplayName { get; init; } = string.Empty;

    public string TotalItemSize { get; init; } = string.Empty;

    public int ItemCount { get; init; }

    public DateTimeOffset? LastLogonTime { get; init; }
}

public sealed record MailboxDelegationSummary
{
    public string Trustee { get; init; } = string.Empty;

    public string AccessRights { get; init; } = string.Empty;

    public bool Inherited { get; init; }

    public string Identity { get; init; } = string.Empty;
}

public sealed record DistributionGroupSummary
{
    public string Id { get; init; } = string.Empty;

    public string DisplayName { get; init; } = string.Empty;

    public string Mail { get; init; } = string.Empty;

    public string Source { get; init; } = string.Empty;
}

public sealed record ManagedDeviceSummary
{
    public string Id { get; init; } = string.Empty;

    public string EntraDeviceId { get; init; } = string.Empty;

    public string ActiveDirectoryIdentity { get; init; } = string.Empty;

    public string Name { get; init; } = string.Empty;

    public string OperatingSystem { get; init; } = string.Empty;

    public string ComplianceState { get; init; } = string.Empty;

    public string PrimaryUser { get; init; } = string.Empty;

    public DateTimeOffset? LastCheckInUtc { get; init; }

    public string Source { get; init; } = string.Empty;
}

public enum DeviceSecretKind
{
    BitLockerRecoveryKey,
    LapsPassword
}

public enum DeviceActionTarget
{
    Intune,
    EntraId,
    ActiveDirectory,
    All
}

public sealed record DeviceSecretRevealRequest
{
    public required ManagedDeviceSummary Device { get; init; }

    public DeviceSecretKind SecretKind { get; init; }
}

public sealed record DeviceSecretRevealResult
{
    public string DeviceId { get; init; } = string.Empty;

    public string DeviceName { get; init; } = string.Empty;

    public DeviceSecretKind SecretKind { get; init; }

    public string Secret { get; init; } = string.Empty;

    public string Metadata { get; init; } = string.Empty;

    public string Source { get; init; } = string.Empty;
}

public sealed record DeviceLifecycleRequest
{
    public required ManagedDeviceSummary Device { get; init; }

    public DeviceActionTarget Target { get; init; }
}

public sealed record DeviceLifecycleResult
{
    public string Operation { get; init; } = string.Empty;

    public string Target { get; init; } = string.Empty;

    public bool Changed { get; init; }

    public string Message { get; init; } = string.Empty;

    public string Source { get; init; } = string.Empty;
}

public sealed record GraphProfileSummary
{
    public string ObjectId { get; init; } = string.Empty;

    public string SamAccountName { get; init; } = string.Empty;

    public string DisplayName { get; init; } = string.Empty;

    public string UserPrincipalName { get; init; } = string.Empty;

    public string UserType { get; init; } = string.Empty;

    public string PreferredLanguage { get; init; } = string.Empty;

    public string UsageLocation { get; init; } = string.Empty;

    public DateTimeOffset? LastSignInDateTime { get; init; }

    public DateTimeOffset? LastNonInteractiveSignInDateTime { get; init; }

    public DateTimeOffset? PasswordLastChangedDateTime { get; init; }

    public IReadOnlyList<string> AuthenticationMethods { get; init; } = Array.Empty<string>();

    public IReadOnlyList<LicenseAssignmentSummary> Licenses { get; init; } = Array.Empty<LicenseAssignmentSummary>();

    public IReadOnlyList<string> PimRoles { get; init; } = Array.Empty<string>();

    public bool MfaRegistered { get; init; }

    public bool MfaCapable { get; init; }

    public string RiskState { get; init; } = string.Empty;

    public string Source { get; init; } = string.Empty;
}

public sealed record AuthenticationPostureSummary
{
    public string UserPrincipalName { get; init; } = string.Empty;

    public string DisplayName { get; init; } = string.Empty;

    public string DefaultMethod { get; init; } = string.Empty;

    public IReadOnlyList<string> AuthenticationMethods { get; init; } = Array.Empty<string>();

    public bool MfaRegistered { get; init; }

    public bool MfaCapable { get; init; }

    public bool PasswordlessRegistered { get; init; }

    public bool TemporaryAccessPassEligible { get; init; }

    public string AuthenticationStrength { get; init; } = string.Empty;

    public string ConditionalAccessState { get; init; } = string.Empty;

    public string SignInRiskState { get; init; } = string.Empty;

    public DateTimeOffset? LastMfaRegistrationDateTime { get; init; }

    public DateTimeOffset? LastSuccessfulSignInDateTime { get; init; }

    public DateTimeOffset? PasswordLastChangedDateTime { get; init; }

    public string Source { get; init; } = string.Empty;
}

public sealed record ConfigurationPreviewSummary
{
    public string ProviderId { get; init; } = string.Empty;

    public string Mode { get; init; } = string.Empty;

    public IReadOnlyDictionary<string, string> Values { get; init; } = new Dictionary<string, string>();
}

public sealed record ReportingSummary
{
    public string ReportId { get; init; } = string.Empty;

    public string Name { get; init; } = string.Empty;

    public int RecordCount { get; init; }

    public string Source { get; init; } = string.Empty;
}
