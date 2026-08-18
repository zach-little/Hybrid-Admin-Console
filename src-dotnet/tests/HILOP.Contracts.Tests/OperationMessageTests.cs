using HILOP.Contracts;
using Xunit;

namespace HILOP.Contracts.Tests;

public sealed class OperationMessageTests
{
    [Fact]
    public void ErrorCreate_RejectsEmptyCode()
    {
        Assert.Throws<ArgumentException>(() => OperationError.Create("", "message"));
    }

    [Fact]
    public void WarningCreate_RejectsEmptyMessage()
    {
        Assert.Throws<ArgumentException>(() => OperationWarning.Create("Warning", ""));
    }

    [Theory]
    [InlineData(-1)]
    [InlineData(101)]
    public void ProgressCreate_RejectsOutOfRangePercent(int percent)
    {
        Assert.Throws<ArgumentOutOfRangeException>(() =>
            OperationProgress.Create(CorrelationId.From("progress"), "Stage", "Message", percent));
    }

    [Fact]
    public void ProgressCreate_AcceptsNullPercent()
    {
        var progress = OperationProgress.Create(CorrelationId.From("progress"), "Launch", "Starting");

        Assert.Null(progress.PercentComplete);
        Assert.Equal("Launch", progress.Stage);
    }
}
