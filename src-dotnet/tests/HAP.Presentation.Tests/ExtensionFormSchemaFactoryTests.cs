using System.Text.Json;
using HAP.Presentation.Extensions;
using Xunit;

namespace HAP.Presentation.Tests;

public sealed class ExtensionFormSchemaFactoryTests
{
    [Fact]
    public void Create_MapsJsonSchemaPropertiesToHapOwnedFieldModels()
    {
        using var document = JsonDocument.Parse("""
{
  "type": "object",
  "required": [ "tenantName" ],
  "properties": {
    "tenantName": { "type": "string", "title": "Tenant Name" },
    "enabled": { "type": "boolean", "title": "Enabled" },
    "region": { "type": "string", "title": "Region", "enum": [ "GCC", "GCCHigh" ] }
  }
}
""");

        var form = ExtensionFormSchemaFactory.Create("Sample Provider", document.RootElement);

        Assert.Equal("Sample Provider", form.Title);
        Assert.Equal(3, form.Fields.Count);
        Assert.Equal(ExtensionFormFieldKind.Text, form.Fields[0].Kind);
        Assert.True(form.Fields[0].IsRequired);
        Assert.Equal(ExtensionFormFieldKind.Boolean, form.Fields[1].Kind);
        Assert.IsType<bool>(form.Fields[1].Value);
        Assert.Equal(ExtensionFormFieldKind.Choice, form.Fields[2].Kind);
        Assert.Equal(new[] { "GCC", "GCCHigh" }, form.Fields[2].Choices);
    }
}
