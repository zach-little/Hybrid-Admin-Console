namespace HILOP.Application.Workflows;

public sealed record WorkflowExecutionRequest
{
    public WorkflowDefinition Definition { get; init; } = new();

    public IReadOnlyDictionary<string, string> Variables { get; init; } = new Dictionary<string, string>();
}

public sealed record WorkflowExecutionResult
{
    public string WorkflowId { get; init; } = string.Empty;

    public string WorkflowName { get; init; } = string.Empty;

    public IReadOnlyList<WorkflowActionResult> Actions { get; init; } = Array.Empty<WorkflowActionResult>();

    public bool Succeeded => Actions.All(action => action.Succeeded || action.Skipped);
}

public sealed record WorkflowActionResult
{
    public string ActionId { get; init; } = string.Empty;

    public string ActionName { get; init; } = string.Empty;

    public string ActionType { get; init; } = string.Empty;

    public string ProviderId { get; init; } = string.Empty;

    public bool Succeeded { get; init; }

    public bool Skipped { get; init; }

    public bool Changed { get; init; }

    public string Status { get; init; } = string.Empty;

    public string Message { get; init; } = string.Empty;

    public IReadOnlyDictionary<string, string> Outputs { get; init; } = new Dictionary<string, string>();
}
