namespace HAP.Application.Capabilities;

public enum CapabilityDisposition
{
    NativeSupported,
    NativeSupportedWithBehaviorChange,
    DeferredUnavailable,
    CustomerExtensionCandidate,
    Removed,
    Unsupported
}
