namespace HAP.LegacyWorker.Protocol;

public enum LegacyWorkerStreamKind
{
    Output = 0,
    Error = 1,
    Warning = 2,
    Verbose = 3,
    Debug = 4,
    Information = 5,
    Progress = 6
}
