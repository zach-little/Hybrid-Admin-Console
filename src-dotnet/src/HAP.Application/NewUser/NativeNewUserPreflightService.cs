using HAP.Contracts;
using HAP.Providers.Abstractions;

namespace HAP.Application.NewUser;

public sealed class NativeNewUserPreflightService
{
    private readonly IUserLookupCapability _directoryLookup;

    public NativeNewUserPreflightService(IUserLookupCapability directoryLookup)
    {
        _directoryLookup = directoryLookup;
    }

    public async Task<OperationResult<NewUserExecutionPlan>> BuildPlanAsync(
        NewUserPreflightRequest request,
        CorrelationId correlationId,
        CancellationToken cancellationToken = default)
    {
        var steps = new List<NewUserPlanStep>
        {
            Step(NewUserPlanStepIds.ValidateRuntime, "Application", "ValidateRuntime", false, "Runtime profile supports native New User Wizard preflight.")
        };

        var missing = MissingRequiredFields(request).ToArray();
        if (missing.Length > 0)
        {
            steps.Add(Step(NewUserPlanStepIds.CheckUniqueness, "ActiveDirectory", "CheckUniqueness", true, $"Missing required fields: {string.Join(", ", missing)}."));
            return OperationResult<NewUserExecutionPlan>.Success(CreatePlan(request, steps), correlationId, status: "Blocked");
        }

        var existing = await _directoryLookup.SearchUsersAsync(request.SamAccountName, correlationId, cancellationToken).ConfigureAwait(false);
        if (!existing.Succeeded)
        {
            steps.Add(Step(NewUserPlanStepIds.CheckUniqueness, "ActiveDirectory", "CheckUniqueness", true, "Unable to confirm account uniqueness."));
            return OperationResult<NewUserExecutionPlan>.Success(CreatePlan(request, steps), correlationId, existing.Warnings, "Blocked");
        }

        if ((existing.Value?.Count ?? 0) > 0)
        {
            steps.Add(Step(NewUserPlanStepIds.CheckUniqueness, "ActiveDirectory", "CheckUniqueness", true, "A matching user already exists."));
            return OperationResult<NewUserExecutionPlan>.Success(CreatePlan(request, steps), correlationId, status: "Blocked");
        }

        steps.Add(Step(NewUserPlanStepIds.CheckUniqueness, "ActiveDirectory", "CheckUniqueness", false, "No existing user matched the requested SAM account name."));
        steps.Add(Step(NewUserPlanStepIds.CreateDirectoryUser, "ActiveDirectory", "CreateUser", false, "Create the directory user."));
        if (!string.IsNullOrWhiteSpace(request.ManagerSamAccountName))
        {
            steps.Add(Step(NewUserPlanStepIds.SetManager, "ActiveDirectory", "SetManager", false, "Set the requested manager."));
        }

        return OperationResult<NewUserExecutionPlan>.Success(CreatePlan(request, steps), correlationId, status: "Ready");
    }

    private static NewUserExecutionPlan CreatePlan(NewUserPreflightRequest request, IReadOnlyList<NewUserPlanStep> steps)
    {
        return new NewUserExecutionPlan
        {
            PlanId = $"new-user:{request.SamAccountName.Trim().ToLowerInvariant()}",
            Request = request,
            Steps = steps
        };
    }

    private static NewUserPlanStep Step(string stepId, string providerId, string operation, bool blocking, string message)
    {
        return new NewUserPlanStep
        {
            StepId = stepId,
            ProviderId = providerId,
            Operation = operation,
            IsBlocking = blocking,
            Message = message
        };
    }

    private static IEnumerable<string> MissingRequiredFields(NewUserPreflightRequest request)
    {
        if (string.IsNullOrWhiteSpace(request.GivenName)) yield return nameof(request.GivenName);
        if (string.IsNullOrWhiteSpace(request.Surname)) yield return nameof(request.Surname);
        if (string.IsNullOrWhiteSpace(request.SamAccountName)) yield return nameof(request.SamAccountName);
        if (string.IsNullOrWhiteSpace(request.Department)) yield return nameof(request.Department);
    }
}
