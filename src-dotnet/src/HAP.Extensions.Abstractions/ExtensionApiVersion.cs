namespace HAP.Extensions.Abstractions;

public readonly record struct ExtensionApiVersion(int Major, int Minor)
{
    public static ExtensionApiVersion Current { get; } = new(1, 0);

    public static bool TryParse(string? value, out ExtensionApiVersion version)
    {
        version = default;
        if (string.IsNullOrWhiteSpace(value))
        {
            return false;
        }

        var parts = value.Split('.', StringSplitOptions.TrimEntries | StringSplitOptions.RemoveEmptyEntries);
        if (parts.Length != 2 ||
            !int.TryParse(parts[0], out var major) ||
            !int.TryParse(parts[1], out var minor) ||
            major < 0 ||
            minor < 0)
        {
            return false;
        }

        version = new ExtensionApiVersion(major, minor);
        return true;
    }

    public bool IsCompatibleWith(ExtensionApiVersion hostVersion)
    {
        return Major == hostVersion.Major && Minor <= hostVersion.Minor;
    }

    public override string ToString()
    {
        return $"{Major}.{Minor}";
    }
}
