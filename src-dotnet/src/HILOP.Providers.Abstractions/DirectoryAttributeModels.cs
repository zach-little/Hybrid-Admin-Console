namespace HILOP.Providers.Abstractions;

public sealed record DirectoryAttributeValue
{
    public string Name { get; init; } = string.Empty;

    public string DisplayName { get; init; } = string.Empty;

    public IReadOnlyList<string> Values { get; init; } = Array.Empty<string>();

    public bool IsSingleValued { get; init; } = true;

    public bool IsReadOnly { get; init; }

    public string Syntax { get; init; } = string.Empty;

    public string Source { get; init; } = string.Empty;
}

public sealed record DirectoryObjectAttributeSet
{
    public string Identity { get; init; } = string.Empty;

    public string DistinguishedName { get; init; } = string.Empty;

    public string ObjectClass { get; init; } = "user";

    public string SchemaSource { get; init; } = string.Empty;

    public IReadOnlyList<DirectoryAttributeValue> Attributes { get; init; } = Array.Empty<DirectoryAttributeValue>();
}
