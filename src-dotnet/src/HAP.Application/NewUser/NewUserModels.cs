using HAP.Providers.Abstractions;

namespace HAP.Application.NewUser;

public sealed record NewUserPreflightRequest
{
    public string GivenName { get; init; } = string.Empty;

    public string Surname { get; init; } = string.Empty;

    public string SamAccountName { get; init; } = string.Empty;

    public string Department { get; init; } = string.Empty;

    public string Title { get; init; } = string.Empty;

    public string ManagerSamAccountName { get; init; } = string.Empty;

    public string Office { get; init; } = string.Empty;
}

public sealed record NewUserExecutionPlan
{
    public string PlanId { get; init; } = string.Empty;

    public NewUserPreflightRequest Request { get; init; } = new();

    public IReadOnlyList<NewUserPlanStep> Steps { get; init; } = Array.Empty<NewUserPlanStep>();

    public bool CanExecute => Steps.All(step => !step.IsBlocking);
}

public sealed record NewUserPlanStep
{
    public string StepId { get; init; } = string.Empty;

    public string ProviderId { get; init; } = string.Empty;

    public string Operation { get; init; } = string.Empty;

    public bool IsBlocking { get; init; }

    public string Message { get; init; } = string.Empty;
}

public sealed record NewUserExecutionResult
{
    public string PlanId { get; init; } = string.Empty;

    public IReadOnlyList<NewUserExecutionStepResult> Steps { get; init; } = Array.Empty<NewUserExecutionStepResult>();

    public bool Succeeded => Steps.All(step => step.Succeeded);
}

public sealed record NewUserExecutionStepResult
{
    public string StepId { get; init; } = string.Empty;

    public string ProviderId { get; init; } = string.Empty;

    public string Operation { get; init; } = string.Empty;

    public bool Succeeded { get; init; }

    public bool Changed { get; init; }

    public string Status { get; init; } = string.Empty;

    public string Message { get; init; } = string.Empty;
}

public static class NewUserPlanStepIds
{
    public const string ValidateRuntime = "validate-runtime";
    public const string CheckUniqueness = "check-uniqueness";
    public const string CreateDirectoryUser = "create-directory-user";
    public const string SetManager = "set-manager";
}
