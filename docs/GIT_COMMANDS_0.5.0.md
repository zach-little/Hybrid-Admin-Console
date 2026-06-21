# Git Commands – Version 0.5 Finalization

## Review Current Branch

```powershell
git status
git branch --show-current
```

Expected branch:

```text
feature/milestone5-cloud-foundation
```

## Stage Finalization Docs

```powershell
git add docs/PROJECT_STATUS.md
git add docs/ROADMAP.md
git add docs/VERSION.md
git add docs/CHANGELOG.md
git add docs/Engineering_Guide.md
git add docs/RELEASE_NOTES_0.5.0.md
```

## Commit

```powershell
git commit -m "Complete Version 0.5 cloud foundation"
```

## Merge to Main

```powershell
git checkout main
git pull
git merge --no-ff feature/milestone5-cloud-foundation
```

## Optional Tag

```powershell
git tag v0.5.0
git push origin main
git push origin v0.5.0
```

## If You Do Not Want to Tag Yet

```powershell
git push origin main
```
