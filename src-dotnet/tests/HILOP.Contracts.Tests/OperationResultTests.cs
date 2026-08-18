using HILOP.Contracts;
using Xunit;

namespace HILOP.Contracts.Tests;

public sealed class OperationResultTests
{
    [Fact]
    public void Success_CarriesValueCorrelationIdAndWarnings()
    {
        var correlationId = CorrelationId.From("abc-123");
        var warning = OperationWarning.Create("PartialData", "Some optional data was unavailable.");

        var result = OperationResult<string>.Success(
            "ready",
            correlationId,
            new[] { warning },
            "Completed");

        Assert.True(result.Succeeded);
        Assert.Equal("ready", result.Value);
        Assert.Equal(correlationId, result.CorrelationId);
        Assert.Single(result.Warnings);
        Assert.Empty(result.Errors);
        Assert.Equal("Completed", result.Status);
    }

    [Fact]
    public void Failure_RequiresAtLeastOneError()
    {
        var correlationId = CorrelationId.From("failed-operation");

        Assert.Throws<ArgumentException>(() =>
            OperationResult<string>.Failure(correlationId, Array.Empty<OperationError>()));
    }

    [Fact]
    public void Failure_CarriesErrorsAndNoValue()
    {
        var correlationId = CorrelationId.From("failed-operation");
        var error = OperationError.Create("ProviderUnavailable", "Provider is unavailable.", "Graph");

        var result = OperationResult<string>.Failure(correlationId, new[] { error }, status: "Failed");

        Assert.False(result.Succeeded);
        Assert.Null(result.Value);
        Assert.Equal(correlationId, result.CorrelationId);
        Assert.Single(result.Errors);
        Assert.Equal("ProviderUnavailable", result.Errors[0].Code);
        Assert.Equal("Failed", result.Status);
    }
}
