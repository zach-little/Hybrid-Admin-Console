using System.Text.Json;
using HAP.Contracts;

namespace HAP.Application.Workflows;

public sealed class NativeWorkflowExportService
{
    public OperationResult<string> ExportJson(
        WorkflowExportDocument document,
        CorrelationId correlationId)
    {
        if (string.IsNullOrWhiteSpace(document.WorkflowName))
        {
            return OperationResult<string>.Failure(
                correlationId,
                new[] { OperationError.Create("WorkflowExport.NameRequired", "Workflow export name is required.") });
        }

        var normalized = document with
        {
            Columns = document.Columns.OrderBy(column => column, StringComparer.OrdinalIgnoreCase).ToArray(),
            Rows = document.Rows
                .OrderBy(row => row.TryGetValue("Id", out var id) ? id : string.Empty, StringComparer.OrdinalIgnoreCase)
                .Select(row => row.ToDictionary(pair => pair.Key, pair => pair.Value))
                .ToArray()
        };

        return OperationResult<string>.Success(
            JsonSerializer.Serialize(normalized, new JsonSerializerOptions { WriteIndented = true }),
            correlationId,
            status: "Completed");
    }
}
