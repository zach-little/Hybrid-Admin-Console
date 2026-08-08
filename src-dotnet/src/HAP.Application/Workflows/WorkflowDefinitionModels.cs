using System.Text.Json;

namespace HAP.Application.Workflows;

public sealed record WorkflowDefinition
{
    public string SchemaVersion { get; init; } = "1.0";

    public string Id { get; init; } = string.Empty;

    public string Name { get; init; } = string.Empty;

    public string Category { get; init; } = string.Empty;

    public IReadOnlyList<WorkflowActionDefinition> Actions { get; init; } = Array.Empty<WorkflowActionDefinition>();

    public static WorkflowDefinition FromJson(string json)
    {
        var definition = JsonSerializer.Deserialize<WorkflowDefinition>(
            json,
            new JsonSerializerOptions
            {
                PropertyNameCaseInsensitive = true,
                ReadCommentHandling = JsonCommentHandling.Skip,
                AllowTrailingCommas = true
            });

        return definition ?? new WorkflowDefinition();
    }
}

public sealed record WorkflowActionDefinition
{
    public string Id { get; init; } = string.Empty;

    public string Name { get; init; } = string.Empty;

    public string Type { get; init; } = string.Empty;

    public string ProviderId { get; init; } = string.Empty;

    public bool Enabled { get; init; } = true;

    public bool ContinueOnError { get; init; }

    public IReadOnlyDictionary<string, string> Inputs { get; init; } = new Dictionary<string, string>();
}

public static class WorkflowActionTypes
{
    public const string CreateAdUser = "CreateAdUser";
    public const string UpdateAdAttributes = "UpdateAdAttributes";
    public const string SetManager = "SetManager";
    public const string AddGroup = "AddGroup";
    public const string RemoveGroup = "RemoveGroup";
    public const string EnableRemoteMailbox = "EnableRemoteMailbox";
    public const string SetMailboxForwarding = "SetMailboxForwarding";
    public const string SetGalVisibility = "SetGalVisibility";
    public const string AddMailboxDelegation = "AddMailboxDelegation";
    public const string ExecutePowerShell = "ExecutePowerShell";
    public const string InvokeRestApi = "InvokeRestApi";
    public const string Delay = "Delay";
    public const string Approval = "Approval";
    public const string ConditionalBranch = "ConditionalBranch";
}
