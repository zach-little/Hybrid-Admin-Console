using HILOP.Application.Auditing;
using HILOP.Application.Workflows;
using HILOP.Contracts;
using Xunit;

namespace HILOP.Application.Tests;

public sealed class AuditLogTests
{
    [Fact]
    public async Task AuditLog_IsProfileScopedRedactedAndHashChained()
    {
        var root = Path.Combine(Path.GetTempPath(), "hilop-audit-tests", Guid.NewGuid().ToString("N"));
        try
        {
            var store = new DurablePostgresAuditStore(new AuditStorageOptions { StorageDirectory = root });
            var atlas = new ProfileAuditLog("Atlas", store);
            var contoso = new ProfileAuditLog("Contoso", store);

            var first = await atlas.WriteAsync(new AuditEventRequest
            {
                CorrelationId = "audit-1", Category = "Provider Edit", EventType = "ActiveDirectoryEdit", Action = "UpdateUser",
                Outcome = "Updated", TargetType = "User", TargetId = "amorgan",
                PreviousValues = new { Department = "Operations" },
                NewValues = new { Department = "Engineering", TemporaryPassword = "NeverStoreThis" }
            });
            var second = await atlas.WriteAsync(new AuditEventRequest
            {
                CorrelationId = "audit-2", Category = "Workflow", EventType = "WorkflowRunCompleted", Action = "Run", Outcome = "Completed"
            });
            await contoso.WriteAsync(new AuditEventRequest
            {
                CorrelationId = "audit-3", Category = "Workflow", EventType = "WorkflowRunCompleted", Action = "Run", Outcome = "Completed"
            });

            var events = await atlas.QueryAsync(new AuditQuery());

            Assert.Equal(2, events.Count);
            Assert.All(events, value => Assert.Equal("Atlas", value.ProfileId));
            Assert.Equal(first.EventHash, second.PreviousHash);
            Assert.False(string.IsNullOrWhiteSpace(first.EventHash));
            Assert.Equal("[REDACTED]", first.NewValues["temporaryPassword"]?.GetValue<string>());
            Assert.DoesNotContain("NeverStoreThis", File.ReadAllText(Path.Combine(root, "audit-events.jsonl")), StringComparison.Ordinal);
        }
        finally
        {
            if (Directory.Exists(root)) Directory.Delete(root, recursive: true);
        }
    }

    [Fact]
    public async Task WorkflowEngine_AuditsRunAndEveryExecutedAction()
    {
        var root = Path.Combine(Path.GetTempPath(), "hilop-audit-tests", Guid.NewGuid().ToString("N"));
        try
        {
            var audit = new ProfileAuditLog("Atlas", new DurablePostgresAuditStore(new AuditStorageOptions { StorageDirectory = root }));
            var definition = new WorkflowDefinition
            {
                Id = "workflow-1",
                Name = "Audited workflow",
                Actions = new[] { new WorkflowActionDefinition { Id = "action-1", Name = "Tool", Type = "CustomTool", ProviderId = "Test", Enabled = true } }
            };
            var engine = new WorkflowExecutionEngine(new SuccessfulExecutor(), audit);

            var result = await engine.ExecuteAsync(new WorkflowExecutionRequest { Definition = definition }, CorrelationId.From("workflow-correlation"));
            var events = await audit.QueryAsync(new AuditQuery());

            Assert.True(result.Succeeded);
            Assert.Contains(events, value => value.EventType == "WorkflowRunStarted");
            Assert.Contains(events, value => value.EventType == "WorkflowActionExecuted" && value.TargetId == "action-1");
            Assert.Contains(events, value => value.EventType == "WorkflowRunCompleted");
        }
        finally
        {
            if (Directory.Exists(root)) Directory.Delete(root, recursive: true);
        }
    }

    private sealed class SuccessfulExecutor : IWorkflowActionExecutor
    {
        public Task<WorkflowActionResult> ExecuteAsync(WorkflowActionDefinition action, WorkflowExecutionRequest request, CorrelationId correlationId, CancellationToken cancellationToken = default) =>
            Task.FromResult(new WorkflowActionResult
            {
                ActionId = action.Id, ActionName = action.Name, ActionType = action.Type, ProviderId = action.ProviderId,
                Succeeded = true, Changed = true, Status = "Completed", Message = "Tool completed."
            });
    }
}
