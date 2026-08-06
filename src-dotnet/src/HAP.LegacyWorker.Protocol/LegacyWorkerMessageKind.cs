namespace HAP.LegacyWorker.Protocol;

public enum LegacyWorkerMessageKind
{
    HandshakeRequest = 0,
    HandshakeResponse = 1,
    OperationRequest = 2,
    OperationResponse = 3,
    Progress = 4,
    CancellationRequest = 5,
    ShutdownRequest = 6,
    ShutdownResponse = 7
}
