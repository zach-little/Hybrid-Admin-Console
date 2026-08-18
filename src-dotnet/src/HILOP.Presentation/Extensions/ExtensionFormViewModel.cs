using System.Collections.ObjectModel;
using System.Text.Json;

namespace HILOP.Presentation.Extensions;

public sealed class ExtensionFormViewModel
{
    public ExtensionFormViewModel(string title, IEnumerable<ExtensionFormFieldViewModel> fields)
    {
        Title = title;
        Fields = new ObservableCollection<ExtensionFormFieldViewModel>(fields);
    }

    public string Title { get; }

    public ObservableCollection<ExtensionFormFieldViewModel> Fields { get; }
}

public static class ExtensionFormSchemaFactory
{
    public static ExtensionFormViewModel Create(string title, JsonElement schema)
    {
        var required = ReadRequired(schema);
        var fields = new List<ExtensionFormFieldViewModel>();
        if (!schema.TryGetProperty("properties", out var properties) || properties.ValueKind != JsonValueKind.Object)
        {
            return new ExtensionFormViewModel(title, fields);
        }

        foreach (var property in properties.EnumerateObject())
        {
            var fieldSchema = property.Value;
            var kind = ReadKind(fieldSchema);
            fields.Add(new ExtensionFormFieldViewModel
            {
                Key = property.Name,
                Label = ReadString(fieldSchema, "title", Humanize(property.Name)),
                Kind = kind,
                IsRequired = required.Contains(property.Name),
                Choices = ReadChoices(fieldSchema),
                Value = kind == ExtensionFormFieldKind.Boolean ? false : string.Empty
            });
        }

        return new ExtensionFormViewModel(title, fields);
    }

    private static HashSet<string> ReadRequired(JsonElement schema)
    {
        if (!schema.TryGetProperty("required", out var required) || required.ValueKind != JsonValueKind.Array)
        {
            return new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        }

        return required.EnumerateArray()
            .Where(item => item.ValueKind == JsonValueKind.String)
            .Select(item => item.GetString()!)
            .ToHashSet(StringComparer.OrdinalIgnoreCase);
    }

    private static ExtensionFormFieldKind ReadKind(JsonElement schema)
    {
        if (schema.TryGetProperty("enum", out var enumValues) && enumValues.ValueKind == JsonValueKind.Array)
        {
            return ExtensionFormFieldKind.Choice;
        }

        return ReadString(schema, "type", "string").ToLowerInvariant() switch
        {
            "integer" or "number" => ExtensionFormFieldKind.Number,
            "boolean" => ExtensionFormFieldKind.Boolean,
            _ => ExtensionFormFieldKind.Text
        };
    }

    private static IReadOnlyList<string> ReadChoices(JsonElement schema)
    {
        if (!schema.TryGetProperty("enum", out var enumValues) || enumValues.ValueKind != JsonValueKind.Array)
        {
            return Array.Empty<string>();
        }

        return enumValues.EnumerateArray()
            .Where(item => item.ValueKind == JsonValueKind.String)
            .Select(item => item.GetString()!)
            .ToArray();
    }

    private static string ReadString(JsonElement schema, string propertyName, string defaultValue)
    {
        return schema.TryGetProperty(propertyName, out var value) && value.ValueKind == JsonValueKind.String
            ? value.GetString() ?? defaultValue
            : defaultValue;
    }

    private static string Humanize(string key)
    {
        return string.Concat(key.Select((character, index) =>
            index > 0 && char.IsUpper(character) ? " " + character : character.ToString()));
    }
}
