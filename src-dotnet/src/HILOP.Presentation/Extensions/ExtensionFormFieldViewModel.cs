namespace HILOP.Presentation.Extensions;

public sealed class ExtensionFormFieldViewModel
{
    public required string Key { get; init; }

    public required string Label { get; init; }

    public ExtensionFormFieldKind Kind { get; init; } = ExtensionFormFieldKind.Text;

    public bool IsRequired { get; init; }

    public IReadOnlyList<string> Choices { get; init; } = Array.Empty<string>();

    public object? Value { get; set; }
}
