using System.Text.Json;
using System.Text.Json.Serialization;

namespace HILOP.Configuration;

public static class RuntimeProfileJson
{
    public static readonly JsonSerializerOptions Options = CreateOptions();

    public static RuntimeProfile Load(string path)
    {
        if (string.IsNullOrWhiteSpace(path))
        {
            throw new ArgumentException("Runtime profile path cannot be empty.", nameof(path));
        }

        var profile = JsonSerializer.Deserialize<RuntimeProfile>(File.ReadAllText(path), Options)
            ?? throw new InvalidOperationException("Runtime profile JSON did not produce a profile.");

        return profile with { SourcePath = Path.GetFullPath(path) };
    }

    public static RuntimeProfile FromJson(string json)
    {
        if (string.IsNullOrWhiteSpace(json))
        {
            throw new ArgumentException("Runtime profile JSON cannot be empty.", nameof(json));
        }

        return JsonSerializer.Deserialize<RuntimeProfile>(json, Options)
            ?? throw new InvalidOperationException("Runtime profile JSON did not produce a profile.");
    }

    private static JsonSerializerOptions CreateOptions()
    {
        var options = new JsonSerializerOptions
        {
            PropertyNameCaseInsensitive = true,
            ReadCommentHandling = JsonCommentHandling.Skip,
            AllowTrailingCommas = true,
            WriteIndented = true
        };
        options.Converters.Add(new JsonStringEnumConverter());
        options.Converters.Add(new RuntimeProviderSettingsDictionaryConverter());
        return options;
    }
}
