namespace HILOP.Application.Workflows;

public sealed class WorkflowStorage
{
    private readonly string _applicationDirectory;
    private readonly string _legacyProgramDataRoot;

    public WorkflowStorage(string programDataDirectory, string applicationDirectory)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(programDataDirectory);
        ArgumentException.ThrowIfNullOrWhiteSpace(applicationDirectory);

        RootDirectory = Path.Combine(programDataDirectory, "Little Innovation Tech", "HILOP");
        WorkflowDirectory = Path.Combine(RootDirectory, "Workflows");
        WorkflowScriptDirectory = Path.Combine(RootDirectory, "Workflow-Scripts");
        _applicationDirectory = applicationDirectory;
        _legacyProgramDataRoot = Path.Combine(programDataDirectory, "HILOP");
    }

    public string RootDirectory { get; }

    public string WorkflowDirectory { get; }

    public string WorkflowScriptDirectory { get; }

    public static WorkflowStorage CreateDefault(string applicationDirectory) =>
        new(
            Environment.GetFolderPath(Environment.SpecialFolder.CommonApplicationData),
            applicationDirectory);

    public void Initialize()
    {
        Directory.CreateDirectory(WorkflowDirectory);
        Directory.CreateDirectory(WorkflowScriptDirectory);

        CopyMissingFiles(Path.Combine(_legacyProgramDataRoot, "Workflows"), WorkflowDirectory, "*.json");
        CopyMissingFiles(Path.Combine(_legacyProgramDataRoot, "Workflow-Scripts"), WorkflowScriptDirectory, "*.ps1");
        CopyMissingFiles(Path.Combine(_applicationDirectory, "workflows"), WorkflowDirectory, "*.json");
        CopyMissingFiles(Path.Combine(_applicationDirectory, "workflow-scripts"), WorkflowScriptDirectory, "*.ps1");
    }

    private static void CopyMissingFiles(string sourceDirectory, string destinationDirectory, string searchPattern)
    {
        if (!Directory.Exists(sourceDirectory))
        {
            return;
        }

        foreach (var sourcePath in Directory.EnumerateFiles(sourceDirectory, searchPattern, SearchOption.TopDirectoryOnly))
        {
            var destinationPath = Path.Combine(destinationDirectory, Path.GetFileName(sourcePath));
            if (!File.Exists(destinationPath))
            {
                File.Copy(sourcePath, destinationPath);
            }
        }
    }
}
