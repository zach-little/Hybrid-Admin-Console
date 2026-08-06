using HAP.Contracts;
using Xunit;

namespace HAP.Contracts.Tests;

public sealed class CorrelationIdTests
{
    [Fact]
    public void From_TrimsValue()
    {
        var correlationId = CorrelationId.From("  launch-1  ");

        Assert.Equal("launch-1", correlationId.Value);
        Assert.Equal("launch-1", correlationId.ToString());
    }

    [Fact]
    public void From_RejectsEmptyValue()
    {
        Assert.Throws<ArgumentException>(() => CorrelationId.From(" "));
    }

    [Fact]
    public void New_CreatesNonEmptyValue()
    {
        var correlationId = CorrelationId.New();

        Assert.False(string.IsNullOrWhiteSpace(correlationId.Value));
    }
}
