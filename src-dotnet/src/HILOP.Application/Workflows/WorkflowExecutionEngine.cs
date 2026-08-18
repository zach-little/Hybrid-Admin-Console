using HILOP.Contracts;
using HILOP.Application.Auditing;

namespace HILOP.Application.Workflows;

public interface IWorkflowActionExecutor
{
    Task<WorkflowActionResult> ExecuteAsync(
        WorkflowActionDefinition action,
        WorkflowExecutionRequest request,
        CorrelationId correlationId,
        CancellationToken cancellationToken = default);
}

public sealed class WorkflowExecutionEngine
{
    private readonly IWorkflowActionExecutor _executor;
    private readonly IAuditLog? _audit;

    public WorkflowExecutionEngine(IWorkflowActionExecutor executor, IAuditLog? audit = null)
    {
        _executor = executor;
        _audit = audit;
    }

    public async Task<OperationResult<WorkflowExecutionResult>> ExecuteAsync(
        WorkflowExecutionRequest request,
        CorrelationId correlationId,
        CancellationToken cancellationToken = default)
    {
        if (string.IsNullOrWhiteSpace(request.Definition.Name))
        {
            return OperationResult<WorkflowExecutionResult>.Failure(
                correlationId,
                new[] { OperationError.Create("Workflow.NameRequired", "Workflow name is required.") });
        }

        var started = DateTimeOffset.UtcNow;
        if (_audit is not null)
        {
            await _audit.WriteAsync(new AuditEventRequest
            {
                CorrelationId = correlationId.Value,
                Category = "Workflow",
                EventType = "WorkflowRunStarted",
                Action = "Run",
                Outcome = "Started",
                TargetType = "Workflow",
                TargetId = request.Definition.Id,
                TargetDisplayName = request.Definition.Name,
                NewValues = new { Definition = request.Definition, Variables = request.Variables },
                Message = $"Workflow '{request.Definition.Name}' started."
            }, cancellationToken).ConfigureAwait(false);
        }

        var results = new List<WorkflowActionResult>();
        var variables = new Dictionary<string, string>(request.Variables, StringComparer.OrdinalIgnoreCase);
        foreach (var action in request.Definition.Actions)
        {
            cancellationToken.ThrowIfCancellationRequested();
            if (!action.Enabled)
            {
                results.Add(Result(action, skipped: true, status: "Skipped", message: "Action is disabled."));
                continue;
            }

            if (!ShouldRun(action.RunWhen, variables))
            {
                results.Add(Result(action, skipped: true, status: "Skipped", message: "Run condition was not met."));
                continue;
            }

            var result = await _executor.ExecuteAsync(action, request with { Variables = variables }, correlationId, cancellationToken).ConfigureAwait(false);
            results.Add(result);
            if (_audit is not null)
            {
                await _audit.WriteAsync(new AuditEventRequest
                {
                    CorrelationId = correlationId.Value,
                    Category = "Workflow Action",
                    EventType = "WorkflowActionExecuted",
                    Action = action.Type,
                    Outcome = result.Status,
                    Severity = result.Succeeded || result.Skipped ? "Information" : "Error",
                    ProviderId = action.ProviderId,
                    TargetType = "WorkflowAction",
                    TargetId = action.Id,
                    TargetDisplayName = action.Name,
                    NewValues = new { Inputs = action.Inputs, result.Outputs, result.Changed },
                    Metadata = new { WorkflowId = request.Definition.Id, WorkflowName = request.Definition.Name, action.RunWhen, action.ContinueOnError },
                    Message = result.Message
                }, cancellationToken).ConfigureAwait(false);
            }
            foreach (var output in result.Outputs)
            {
                variables[output.Key] = output.Value;
            }

            if (!result.Succeeded && !result.Skipped && !action.ContinueOnError)
            {
                break;
            }
        }

        var execution = new WorkflowExecutionResult
        {
            WorkflowId = request.Definition.Id,
            WorkflowName = request.Definition.Name,
            Actions = results
        };

        var operationResult = execution.Succeeded
            ? OperationResult<WorkflowExecutionResult>.Success(execution, correlationId, status: "Completed")
            : OperationResult<WorkflowExecutionResult>.Failure(
                correlationId,
                new[] { OperationError.Create("Workflow.ExecutionFailed", "Workflow execution failed. See action results.") },
                status: "Failed");
        if (_audit is not null)
        {
            await _audit.WriteAsync(new AuditEventRequest
            {
                CorrelationId = correlationId.Value,
                Category = "Workflow",
                EventType = execution.Succeeded ? "WorkflowRunCompleted" : "WorkflowRunFailed",
                Action = "Run",
                Outcome = operationResult.Status ?? (execution.Succeeded ? "Completed" : "Failed"),
                Severity = execution.Succeeded ? "Information" : "Error",
                TargetType = "Workflow",
                TargetId = request.Definition.Id,
                TargetDisplayName = request.Definition.Name,
                StartedAtUtc = started,
                CompletedAtUtc = DateTimeOffset.UtcNow,
                NewValues = execution,
                Errors = operationResult.Errors.Cast<object>(),
                Warnings = operationResult.Warnings.Cast<object>(),
                Message = execution.Succeeded ? $"Workflow '{request.Definition.Name}' completed." : $"Workflow '{request.Definition.Name}' failed."
            }, cancellationToken).ConfigureAwait(false);
        }
        return operationResult;
    }

    private static WorkflowActionResult Result(WorkflowActionDefinition action, bool skipped, string status, string message)
    {
        return new WorkflowActionResult
        {
            ActionId = action.Id,
            ActionName = action.Name,
            ActionType = action.Type,
            ProviderId = action.ProviderId,
            Succeeded = !skipped,
            Skipped = skipped,
            Status = status,
            Message = message
        };
    }

    private static bool ShouldRun(string condition, IReadOnlyDictionary<string, string> variables)
    {
        if (string.IsNullOrWhiteSpace(condition))
        {
            return true;
        }

        var andParts = condition.Split("&&", StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries);
        if (andParts.Length > 1)
        {
            return andParts.All(part => ShouldRun(part, variables));
        }

        foreach (var op in new[] { "==", "!=" })
        {
            var index = condition.IndexOf(op, StringComparison.Ordinal);
            if (index < 0)
            {
                continue;
            }

            var left = Clean(Expand(condition[..index], variables));
            var right = Clean(Expand(condition[(index + op.Length)..], variables));
            var equal = string.Equals(left, right, StringComparison.OrdinalIgnoreCase);
            return op == "==" ? equal : !equal;
        }

        var expanded = Clean(Expand(condition, variables));
        return bool.TryParse(expanded, out var parsed) ? parsed : !string.IsNullOrWhiteSpace(expanded);
    }

    private static string Expand(string value, IReadOnlyDictionary<string, string> variables)
    {
        var expanded = value;
        foreach (var variable in variables)
        {
            expanded = expanded.Replace($"{{{{{variable.Key}}}}}", variable.Value, StringComparison.OrdinalIgnoreCase);
        }

        return expanded;
    }

    private static string Clean(string value)
    {
        return value.Trim().Trim('"').Trim('\'');
    }
}
