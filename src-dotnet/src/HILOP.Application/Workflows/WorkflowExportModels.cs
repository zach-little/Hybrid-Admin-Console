namespace HILOP.Application.Workflows;

public sealed record WorkflowExportDocument
{
    public string SchemaVersion { get; init; } = "1.0";

    public string WorkflowName { get; init; } = string.Empty;

    public IReadOnlyList<string> Columns { get; init; } = Array.Empty<string>();

    public IReadOnlyList<IReadOnlyDictionary<string, string>> Rows { get; init; } = Array.Empty<IReadOnlyDictionary<string, string>>();
}
