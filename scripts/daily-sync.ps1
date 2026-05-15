param(
  [string]$Message = "docs: daily Boot.dev sync"
)

$projectsRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$repoConfigs = @(
  @{
    Path = (Join-Path $projectsRoot "bootdev-python-security")
    AddPaths = @("README.md", "progress-log.md", "security-mapping.md", "chapters", "notes")
  },
  @{
    Path = (Join-Path $projectsRoot "bootdev-security-journey")
    AddPaths = @("progress-log.md", "README.md")
  },
  @{
    Path = (Join-Path $projectsRoot "bootdev-secure-projects")
    AddPaths = @(".")
  }
)

foreach ($repoConfig in $repoConfigs) {
  $repo = $repoConfig.Path
  $addPaths = $repoConfig.AddPaths
  if (-not (Test-Path $repo)) {
    Write-Host "Path not found: $repo"
    continue
  }

  if (-not (Test-Path (Join-Path $repo ".git"))) {
    Write-Host "Skipping non-git directory: $repo"
    continue
  }

  Set-Location $repo
  Write-Host "`n=== Syncing: $repo ==="

  foreach ($addPath in $addPaths) {
    git add -- $addPath
  }
  $hasChanges = git diff --cached --name-only

  if (-not [string]::IsNullOrWhiteSpace($hasChanges)) {
    git commit -m $Message
  } else {
    Write-Host "No new local changes to commit: $repo"
  }

  git pull --rebase origin main
  if ($LASTEXITCODE -ne 0) {
    Write-Host "Rebase failed for $repo. Resolve conflicts, then run the script again."
    continue
  }

  git push origin main
  if ($LASTEXITCODE -eq 0) {
    Write-Host "Synced local + GitHub: $repo"
  } else {
    Write-Host "Push failed for $repo"
  }
}
