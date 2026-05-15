# Boot.dev Python Security

Learning Python through a security lens, with concept-based chapter summaries and OWASP Top 10 mapping.

## About

This repository tracks my Boot.dev **Learn to Code in Python** progress with:
- chapter-by-chapter Python concept coverage,
- concise lesson summaries,
- security mapping for each chapter,
- portfolio-oriented notes for backend/AppSec growth.

Lesson names are normalized into meaningful Python concepts (instead of duplicate quiz/practice labels) for cleaner portfolio readability.

## Current Progress

- **Course:** Learn to Code in Python
- **Status:** ✅ Completed through **Chapter 9 (Lists)**
- **Active Days Synced:** May 4, 5, 6, 7, 8, 9, 10, 12, 13, 14, 15 (2026)

See `progress-log.md` for the streak-aligned timeline.

## Repository Structure

```text
bootdev-python-security/
├── README.md
├── progress-log.md
├── security-mapping.md
├── chapters/
│   ├── 01-introduction/
│   ├── 02-variables/
│   ├── 03-functions/
│   ├── 04-scope/
│   ├── 05-testing-and-debugging/
│   ├── 06-computing/
│   ├── 07-comparisons/
│   ├── 08-loops/
│   └── 09-lists/
├── exercises/
├── scripts/
└── notes/
    ├── chapter-lesson-summary.md
    ├── python-security-notes.md
    └── debugging-notes.md
```

## Chapter Track (1–9)

1. **Introduction** – Python basics, syntax, execution model
2. **Variables** – data types, assignment, string formatting
3. **Functions** – parameters, returns, call flow
4. **Scope** – local/global visibility and variable lifetime
5. **Testing and Debugging** – unit testing mindset, tracebacks, debugging workflow
6. **Computing** – numeric behavior, binary/bitwise foundations
7. **Comparisons** – conditionals, Boolean logic, decision flow
8. **Loops** – iteration patterns, loop control, while/for usage
9. **Lists** – indexing, mutation, operations, tuples, slicing

## Security Mapping Focus

Every chapter includes:
- **Boot.dev concept → OWASP Top 10 category → portfolio application**.

Quick examples:
- Functions → `A03: Injection` (input validation helpers)
- Scope & error handling → `A05: Security Misconfiguration` (safe state + safe failures)
- Comparisons/loops/lists → `A09: Security Logging and Monitoring Failures` (event filtering, parsing, trend analysis)

See `security-mapping.md` for full chapter-by-chapter mappings.

## Daily GitHub Automation (Safe)

Use this for both repos:
- `https://github.com/DADAHOJO/bootdev-python-security`
- `https://github.com/DADAHOJO/bootdev-security-journey`

### 1) Create script: `scripts/daily-sync.ps1`

```powershell
param(
  [string]$Message = "docs: daily Boot.dev sync"
)

$repos = @(
  "C:\Users\H_Abbas\CascadeProjects\bootdev-python-security",
  "C:\Users\H_Abbas\CascadeProjects\bootdev-security-journey"
)

foreach ($repo in $repos) {
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
```

### 2) Manual daily run

```powershell
powershell -ExecutionPolicy Bypass -File .\bootdev-python-security\scripts\daily-sync.ps1 -Message "Day X: Boot.dev Python progress + security mapping"
```

Optional commit message generator:

```powershell
$msg = powershell -ExecutionPolicy Bypass -File .\bootdev-python-security\scripts\generate-commit-message.ps1 -Chapter 8 -Concept "loops-practice" -Security "A09-monitoring"
powershell -ExecutionPolicy Bypass -File .\bootdev-python-security\scripts\daily-sync.ps1 -Message $msg
```

### 3) Optional scheduled run

Use **Task Scheduler**:
- Trigger: Daily at your preferred time
- Action: `powershell.exe`
- Arguments: `-ExecutionPolicy Bypass -File "C:\Users\H_Abbas\CascadeProjects\bootdev-python-security\scripts\daily-sync.ps1"`

## Commit Quality Rules

- Skip empty commits
- Keep commits meaningful and small
- Never include secrets (`.env`, keys, tokens, cookies)
- Prefer explicit messages tied to chapter concepts and security mapping

## Related Repositories

- `https://github.com/DADAHOJO/bootdev-security-journey`
- `https://github.com/DADAHOJO/bootdev-secure-projects`

---

## Additional Track Context

### Boot.dev Python Security Track

This repository tracks my Python learning progress from Boot.dev, with additional security-focused notes and mappings.

## Purpose

I am using Boot.dev to build software engineering fundamentals while transitioning from hardware security toward software security, application security, secure backend engineering, and DevSecOps.

Boot.dev provides the coding foundation. I add the security layer using OWASP Top 10, OWASP ASVS, and NIST SSDF.

## Focus Areas

- Python fundamentals
- Functions and return values
- Debugging
- Error handling
- Secure input handling
- Automation basics
- Security scripting foundations
- Clean and maintainable code

## Boot.dev Timeline

- Joined Boot.dev: April 20
- Active learning started: May 4
- GitHub sync started: May 7

## Security Mapping Approach

Each topic is documented using this format:

```text
Boot.dev concept → Security connection → Portfolio application
```

