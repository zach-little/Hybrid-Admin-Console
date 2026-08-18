namespace HILOP.Application.Capabilities;

public enum CapabilityDisposition
{
    NativeSupported,
    NativeSupportedWithBehaviorChange,
    DeferredUnavailable,
    CustomerExtensionCandidate,
    Removed,
    Unsupported
}
