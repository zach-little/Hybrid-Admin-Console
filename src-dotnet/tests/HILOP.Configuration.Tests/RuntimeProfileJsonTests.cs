using HILOP.Configuration;
using Xunit;

namespace HILOP.Configuration.Tests;

public sealed class RuntimeProfileJsonTests
{
    [Fact]
    public void FromJson_LoadsSimulationProfileShape()
    {
        var json = File.ReadAllText(Path.Combine(GetRepositoryRoot(), "profiles", "Simulation", "runtime.json"));

        var profile = RuntimeProfileJson.FromJson(json);

        Assert.Equal("Simulation", profile.ProfileName);
        Assert.Equal(RuntimeProfileMode.Simulation, profile.Mode);
        Assert.Equal("Commercial", profile.Cloud);
        Assert.True(profile.Providers.ContainsKey("DirectorySimulator"));
        Assert.Equal("DirectorySimulator", profile.Providers["DirectorySimulator"].Name);
        Assert.Equal(ProviderMode.Simulation, profile.Providers["DirectorySimulator"].Mode);
    }

    [Fact]
    public void Load_RecordsSourcePath()
    {
        var path = Path.Combine(GetRepositoryRoot(), "profiles", "Simulation", "runtime.json");

        var profile = RuntimeProfileJson.Load(path);

        Assert.Equal(Path.GetFullPath(path), profile.SourcePath);
    }

    private static string GetRepositoryRoot()
    {
        var directory = new DirectoryInfo(AppContext.BaseDirectory);
        while (directory is not null && !File.Exists(Path.Combine(directory.FullName, "Migration.MD")))
        {
            directory = directory.Parent;
        }

        return directory?.FullName ?? throw new InvalidOperationException("Could not find repository root.");
    }
}
