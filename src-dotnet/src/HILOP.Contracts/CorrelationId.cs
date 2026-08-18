namespace HILOP.Contracts;

public readonly record struct CorrelationId(string Value)
{
    public static CorrelationId New() => new(Guid.NewGuid().ToString("N"));

    public static CorrelationId From(string value)
    {
        if (string.IsNullOrWhiteSpace(value))
        {
            throw new ArgumentException("Correlation ID cannot be empty.", nameof(value));
        }

        return new CorrelationId(value.Trim());
    }

    public override string ToString() => Value;
}
