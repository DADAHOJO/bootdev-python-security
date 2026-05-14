param(
  [string]$Message = "docs: daily Boot.dev sync"
)

$projectsRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$repos = @(
  (Join-Path $projectsRoot "bootdev-python-security"),
  (Join-Path $projectsRoot "bootdev-security-journey")
)

foreach ($repo in $repos) {
  if (-not (Test-Path $repo)) {
    Write-Host "Path not found: $repo"
    continue
  }

  if (-not (Test-Path (Join-Path $repo ".git"))) {
    Write-Host "Skipping non-git directory: $repo"
    continue
  }

  Set-Location $repo

  git add .
  $hasChanges = git diff --cached --name-only

  if (-not [string]::IsNullOrWhiteSpace($hasChanges)) {
    git commit -m $Message
    git push origin main
    Write-Host "Committed and pushed: $repo"
  } else {
    Write-Host "No staged changes: $repo"
  }
}
