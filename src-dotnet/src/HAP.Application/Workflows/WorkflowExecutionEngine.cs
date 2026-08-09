using HAP.Contracts;

namespace HAP.Application.Workflows;

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

    public WorkflowExecutionEngine(IWorkflowActionExecutor executor)
    {
        _executor = executor;
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

        return execution.Succeeded
            ? OperationResult<WorkflowExecutionResult>.Success(execution, correlationId, status: "Completed")
            : OperationResult<WorkflowExecutionResult>.Failure(
                correlationId,
                new[] { OperationError.Create("Workflow.ExecutionFailed", "Workflow execution failed. See action results.") },
                status: "Failed");
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
