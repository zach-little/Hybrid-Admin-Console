using HILOP.Application.Workflows;
using Xunit;

namespace HILOP.Application.Tests;

public sealed class WorkflowStorageTests
{
    [Fact]
    public void Initialize_CreatesProgramDataDirectoriesAndCopiesPackagedContent()
    {
        var testRoot = CreateTestRoot();
        try
        {
            var programData = Path.Combine(testRoot, "ProgramData");
            var application = Path.Combine(testRoot, "Application");
            var packagedWorkflows = Path.Combine(application, "workflows");
            var packagedScripts = Path.Combine(application, "workflow-scripts");
            Directory.CreateDirectory(packagedWorkflows);
            Directory.CreateDirectory(packagedScripts);
            File.WriteAllText(Path.Combine(packagedWorkflows, "example.json"), "packaged workflow");
            File.WriteAllText(Path.Combine(packagedScripts, "example.ps1"), "packaged script");

            var storage = new WorkflowStorage(programData, application);

            storage.Initialize();

            Assert.Equal(Path.Combine(programData, "Little Innovation Tech", "HILOP", "Workflows"), storage.WorkflowDirectory);
            Assert.Equal(Path.Combine(programData, "Little Innovation Tech", "HILOP", "Workflow-Scripts"), storage.WorkflowScriptDirectory);
            Assert.Equal("packaged workflow", File.ReadAllText(Path.Combine(storage.WorkflowDirectory, "example.json")));
            Assert.Equal("packaged script", File.ReadAllText(Path.Combine(storage.WorkflowScriptDirectory, "example.ps1")));
        }
        finally
        {
            Directory.Delete(testRoot, recursive: true);
        }
    }

    [Fact]
    public void Initialize_DoesNotOverwriteExistingProgramDataContent()
    {
        var testRoot = CreateTestRoot();
        try
        {
            var programData = Path.Combine(testRoot, "ProgramData");
            var application = Path.Combine(testRoot, "Application");
            var packagedWorkflows = Path.Combine(application, "workflows");
            Directory.CreateDirectory(packagedWorkflows);
            File.WriteAllText(Path.Combine(packagedWorkflows, "custom.json"), "new packaged workflow");

            var storage = new WorkflowStorage(programData, application);
            Directory.CreateDirectory(storage.WorkflowDirectory);
            File.WriteAllText(Path.Combine(storage.WorkflowDirectory, "custom.json"), "user customization");

            storage.Initialize();

            Assert.Equal("user customization", File.ReadAllText(Path.Combine(storage.WorkflowDirectory, "custom.json")));
        }
        finally
        {
            Directory.Delete(testRoot, recursive: true);
        }
    }

    [Fact]
    public void Initialize_MigratesContentFromFormerTopLevelHilopFolder()
    {
        var testRoot = CreateTestRoot();
        try
        {
            var programData = Path.Combine(testRoot, "ProgramData");
            var application = Path.Combine(testRoot, "Application");
            var legacyWorkflows = Path.Combine(programData, "HILOP", "Workflows");
            var legacyScripts = Path.Combine(programData, "HILOP", "Workflow-Scripts");
            Directory.CreateDirectory(legacyWorkflows);
            Directory.CreateDirectory(legacyScripts);
            File.WriteAllText(Path.Combine(legacyWorkflows, "custom.json"), "legacy workflow");
            File.WriteAllText(Path.Combine(legacyScripts, "custom.ps1"), "legacy script");

            var storage = new WorkflowStorage(programData, application);

            storage.Initialize();

            Assert.Equal("legacy workflow", File.ReadAllText(Path.Combine(storage.WorkflowDirectory, "custom.json")));
            Assert.Equal("legacy script", File.ReadAllText(Path.Combine(storage.WorkflowScriptDirectory, "custom.ps1")));
        }
        finally
        {
            Directory.Delete(testRoot, recursive: true);
        }
    }

    private static string CreateTestRoot()
    {
        var path = Path.Combine(Path.GetTempPath(), "hilop-workflow-storage-tests", Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(path);
        return path;
    }
}
