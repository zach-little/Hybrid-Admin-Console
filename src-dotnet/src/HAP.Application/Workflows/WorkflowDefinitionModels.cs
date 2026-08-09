using System.Text.Json;

namespace HAP.Application.Workflows;

public sealed record WorkflowDefinition
{
    public string SchemaVersion { get; init; } = "1.0";

    public string Id { get; init; } = string.Empty;

    public string Name { get; init; } = string.Empty;

    public string Category { get; init; } = string.Empty;

    public WorkflowFormDefinition Form { get; init; } = new();

    public IReadOnlyList<WorkflowComputedVariableDefinition> ComputedVariables { get; init; } = Array.Empty<WorkflowComputedVariableDefinition>();

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

    public string RunWhen { get; init; } = string.Empty;

    public IReadOnlyDictionary<string, string> Inputs { get; init; } = new Dictionary<string, string>();
}

public sealed record WorkflowFormDefinition
{
    public string Title { get; init; } = string.Empty;

    public string SubmitText { get; init; } = "Run";

    public IReadOnlyList<WorkflowFormFieldDefinition> Fields { get; init; } = Array.Empty<WorkflowFormFieldDefinition>();
}

public sealed record WorkflowFormFieldDefinition
{
    public string Key { get; init; } = string.Empty;

    public string Label { get; init; } = string.Empty;

    public string Control { get; init; } = "TextBox";

    public bool Required { get; init; }

    public string DefaultValue { get; init; } = string.Empty;

    public string ValidationRegex { get; init; } = string.Empty;

    public string ValidationMessage { get; init; } = string.Empty;

    public IReadOnlyList<WorkflowFormOptionDefinition> Options { get; init; } = Array.Empty<WorkflowFormOptionDefinition>();
}

public sealed record WorkflowFormOptionDefinition
{
    public string Label { get; init; } = string.Empty;

    public string Value { get; init; } = string.Empty;
}

public sealed record WorkflowComputedVariableDefinition
{
    public string Key { get; init; } = string.Empty;

    public string Type { get; init; } = string.Empty;

    public string Value { get; init; } = string.Empty;

    public string Fallback { get; init; } = string.Empty;

    public IReadOnlyDictionary<string, string> Map { get; init; } = new Dictionary<string, string>();
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
