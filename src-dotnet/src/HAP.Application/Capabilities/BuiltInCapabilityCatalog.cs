namespace HAP.Application.Capabilities;

public sealed class BuiltInCapabilityCatalog
{
    private readonly IReadOnlyList<CapabilityAvailability> _capabilities;

    public BuiltInCapabilityCatalog()
    {
        _capabilities = new[]
        {
            Available("DirectorySimulator", "Simulator.AllReads", CapabilityDisposition.NativeSupported),
            Available("DirectorySimulator", "Simulator.AllWrites", CapabilityDisposition.NativeSupported),
            Available("MicrosoftGraph", "Graph.UserRead", CapabilityDisposition.NativeSupported),
            Available("MicrosoftGraph", "Graph.AuthenticationPostureRead", CapabilityDisposition.NativeSupportedWithBehaviorChange),
            Available("MicrosoftGraph", "Graph.DeviceRead", CapabilityDisposition.NativeSupportedWithBehaviorChange),
            Available("ActiveDirectory", "AD.UserRead", CapabilityDisposition.NativeSupported),
            Deferred("ActiveDirectory", "AD.Write", "AD writes require explicit lab validation before production enablement."),
            Available("ExchangeOnline", "ExchangeOnline.MailboxIdentityRead", CapabilityDisposition.NativeSupportedWithBehaviorChange),
            Deferred("ExchangeOnline", "ExchangeOnline.MailboxStatistics", "No approved native public API is selected for mailbox statistics."),
            Extension("ExchangeOnline", "ExchangeOnline.MailboxDelegation", "Mailbox delegation may be supplied by an approved customer PowerShell extension."),
            Extension("ExchangeOnline", "ExchangeOnline.DistributionGroups", "Exchange distribution group administration may be supplied by an approved customer PowerShell extension."),
            Deferred("ExchangeOnline", "ExchangeOnline.MailboxForwarding", "Mailbox forwarding is deferred until a supported public API or extension decision is made."),
            Deferred("ExchangeOnline", "ExchangeOnline.GalVisibility", "GAL visibility is deferred until a supported public API or extension decision is made."),
            Deferred("ExchangeOnPremises", "ExchangeOnPremises.MailboxRead", "No approved non-PowerShell on-premises Exchange management API is configured."),
            Extension("ExchangeOnPremises", "ExchangeOnPremises.MailboxDelegation", "On-premises Exchange administration may be supplied by an approved customer extension."),
            Extension("ExchangeOnPremises", "ExchangeOnPremises.DistributionGroups", "On-premises distribution group administration may be supplied by an approved customer extension."),
            Deferred("ExchangeOnPremises", "ExchangeOnPremises.MailboxForwarding", "On-premises mailbox forwarding is deferred without an approved non-PowerShell management path.")
        };
    }

    public IReadOnlyList<CapabilityAvailability> GetAll() => _capabilities;

    public CapabilityAvailability Get(string providerId, string capabilityId)
    {
        return _capabilities.FirstOrDefault(capability =>
            string.Equals(capability.ProviderId, providerId, StringComparison.OrdinalIgnoreCase) &&
            string.Equals(capability.CapabilityId, capabilityId, StringComparison.OrdinalIgnoreCase))
            ?? new CapabilityAvailability
            {
                ProviderId = providerId,
                CapabilityId = capabilityId,
                Disposition = CapabilityDisposition.Unsupported,
                IsInvokableBuiltIn = false,
                Reason = "Capability is not registered for the native built-in provider catalog."
            };
    }

    private static CapabilityAvailability Available(
        string providerId,
        string capabilityId,
        CapabilityDisposition disposition)
    {
        return new CapabilityAvailability
        {
            ProviderId = providerId,
            CapabilityId = capabilityId,
            Disposition = disposition,
            IsInvokableBuiltIn = true,
            Reason = "Capability is supported by a native built-in provider."
        };
    }

    private static CapabilityAvailability Deferred(string providerId, string capabilityId, string reason)
    {
        return new CapabilityAvailability
        {
            ProviderId = providerId,
            CapabilityId = capabilityId,
            Disposition = CapabilityDisposition.DeferredUnavailable,
            IsInvokableBuiltIn = false,
            Reason = reason
        };
    }

    private static CapabilityAvailability Extension(string providerId, string capabilityId, string reason)
    {
        return new CapabilityAvailability
        {
            ProviderId = providerId,
            CapabilityId = capabilityId,
            Disposition = CapabilityDisposition.CustomerExtensionCandidate,
            IsInvokableBuiltIn = false,
            Reason = reason
        };
    }
}
