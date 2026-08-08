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
        foreach (var action in request.Definition.Actions)
        {
            cancellationToken.ThrowIfCancellationRequested();
            if (!action.Enabled)
            {
                results.Add(Result(action, skipped: true, status: "Skipped", message: "Action is disabled."));
                continue;
            }

            var result = await _executor.ExecuteAsync(action, request, correlationId, cancellationToken).ConfigureAwait(false);
            results.Add(result);
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
}
