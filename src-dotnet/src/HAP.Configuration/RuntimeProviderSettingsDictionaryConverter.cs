using System.Text.Json;
using System.Text.Json.Serialization;

namespace HAP.Configuration;

internal sealed class RuntimeProviderSettingsDictionaryConverter
    : JsonConverter<IReadOnlyDictionary<string, RuntimeProviderSettings>>
{
    public override IReadOnlyDictionary<string, RuntimeProviderSettings> Read(
        ref Utf8JsonReader reader,
        Type typeToConvert,
        JsonSerializerOptions options)
    {
        var providers = JsonSerializer.Deserialize<Dictionary<string, RuntimeProviderSettings>>(ref reader, options)
            ?? new Dictionary<string, RuntimeProviderSettings>(StringComparer.OrdinalIgnoreCase);

        return providers
            .Select(pair => new KeyValuePair<string, RuntimeProviderSettings>(
                pair.Key,
                string.IsNullOrWhiteSpace(pair.Value.Name) ? pair.Value with { Name = pair.Key } : pair.Value))
            .OrderBy(pair => pair.Key, StringComparer.OrdinalIgnoreCase)
            .ToDictionary(pair => pair.Key, pair => pair.Value, StringComparer.OrdinalIgnoreCase);
    }

    public override void Write(
        Utf8JsonWriter writer,
        IReadOnlyDictionary<string, RuntimeProviderSettings> value,
        JsonSerializerOptions options)
    {
        writer.WriteStartObject();
        foreach (var pair in value.OrderBy(pair => pair.Key, StringComparer.OrdinalIgnoreCase))
        {
            writer.WritePropertyName(pair.Key);
            JsonSerializer.Serialize(writer, pair.Value, options);
        }
        writer.WriteEndObject();
    }
}
