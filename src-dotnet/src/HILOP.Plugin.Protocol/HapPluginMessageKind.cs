namespace HILOP.Plugin.Protocol;

public enum HapPluginMessageKind
{
    HandshakeRequest = 0,
    HandshakeResponse = 1,
    MetadataRequest = 2,
    MetadataResponse = 3,
    HealthRequest = 4,
    HealthResponse = 5,
    OperationRequest = 6,
    OperationResponse = 7,
    Progress = 8,
    CancellationRequest = 9,
    CancellationResponse = 10,
    ShutdownRequest = 11,
    ShutdownResponse = 12
}
