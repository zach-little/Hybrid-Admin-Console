# Milestone 2 Hotfix 1

Fixes model type stamping so domain models explicitly insert their canonical PSTypeName into `PSObject.TypeNames`.

This addresses the failing assertion:

`Search returns Hybrid.User models`

Replace:

`src/Core/Domain/Hybrid.Models.psm1`? No — actual path:

`src/Domain/Hybrid.Models.psm1`
