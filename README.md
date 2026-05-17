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
- **Status:** âœ… Completed through **Chapter 10 (Dictionaries)**
- **Active Days Synced:** May 4, 5, 6, 7, 8, 9, 10, 12, 13, 14, 15, 16, 17 (2026)

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

## Chapter Track (1–10)

1. **Introduction** – Python basics, syntax, execution model
2. **Variables** – data types, assignment, string formatting
3. **Functions** – parameters, returns, call flow
4. **Scope** – local/global visibility and variable lifetime
5. **Testing and Debugging** – unit testing mindset, tracebacks, debugging workflow
6. **Computing** – numeric behavior, binary/bitwise foundations
7. **Comparisons** – conditionals, Boolean logic, decision flow
8. **Loops** – iteration patterns, loop control, while/for usage
9. **Lists** – indexing, mutation, operations, tuples, slicing
10. **Dictionaries** – topic coverage

## Security Mapping Focus

Every chapter includes:
- **Boot.dev concept → OWASP Top 10 category → portfolio application**.

Quick examples:
- Functions → A03: Injection (input validation helpers)
- Scope & error handling → A05: Security Misconfiguration (safe state + safe failures)
- Comparisons/loops/lists → A09: Security Logging and Monitoring Failures (event filtering, parsing, trend analysis)

See `security-mapping.md` for full chapter-by-chapter mappings.

## Daily GitHub Automation (Safe)

Use this for all three repos:
- `https://github.com/DADAHOJO/bootdev-python-security`
- `https://github.com/DADAHOJO/bootdev-security-journey`
- `https://github.com/DADAHOJO/bootdev-secure-projects`

### 1) Daily root launcher (recommended)

From the `scripts/` folder:

```powershell
.\sync-bootdev.cmd
```

This will:
- OCR today’s screenshots from `Boot.Dev-screenshots/`
- Auto-map OWASP security category format
- Append progress entries and update README activity sections
- Commit, rebase, and push all repos

#### OCR setup (one-time)

The root launcher uses `py -3.11` with `EasyOCR` for screenshot extraction.

```powershell
py -3.11 -m pip install --upgrade pip
py -3.11 -m pip install easyocr
```

Verify Python 3.11 is available:

```powershell
py -3.11 --version
```

### 2) Manual daily run

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\daily-sync.ps1 -Message "Day X: Boot.dev Python progress + security mapping"
```

### 2b) Recommended root launcher (auto progress entry + sync)

Use the root launcher to append this exact format to `progress-log.md` in related repos before syncing:

```text
May 15, 2026
Streak Activity: 1 Boot.dev/GitHub activity
Chapter Focus: Chapter 9 – Lists
Lesson Concepts Covered: slicing, concatenate/contains operations, deletion patterns, tuples, first element/reverse/filter practice
Security Connection: OWASP A09 – list-based event filtering and result triage pipelines
```

Example daily run from `scripts/`:

```powershell
powershell -ExecutionPolicy Bypass -File .\run-daily-sync.ps1 `
  -Chapter 9 `
  -ChapterTitle "Lists" `
  -Concept "slicing, concatenate/contains operations, deletion patterns, tuples, first element/reverse/filter practice" `
  -Security "OWASP A09 – list-based event filtering and result triage pipelines" `
  -StreakActivity 1
```

Optional explicit fields:
- `-ChapterSummary`
- `-ChapterFolder`
- `-ChapterFocus`
- `-LessonConceptsCovered`
- `-SecurityConnection`
- `-EntryDate`

After you finish learning for the day:
1. Save your changes in each repo.
2. Run the root launcher once from `bootdev-python-security/scripts`.
3. If a rebase conflict appears, resolve it in that repo and rerun the same command.

Optional commit message generator:

```powershell
$msg = powershell -ExecutionPolicy Bypass -File .\scripts\generate-commit-message.ps1 -Chapter 8 -Concept "loops-practice" -Security "A09-monitoring"
powershell -ExecutionPolicy Bypass -File .\scripts\daily-sync.ps1 -Message $msg
```

### 3) Optional scheduled run

Use **Task Scheduler**:
- Trigger: Daily at your preferred time
- Action: `powershell.exe`
- Arguments: `-ExecutionPolicy Bypass -File ".\scripts\daily-sync.ps1"`
- Start in: your `bootdev-python-security` repo root

## Commit Quality Rules

- Skip empty commits
- Keep commits meaningful and small
- Never include secrets (`.env`, keys, tokens, cookies)
- Prefer explicit messages tied to chapter concepts and security mapping

## Related Repositories

- `https://github.com/DADAHOJO/bootdev-security-journey`
- `https://github.com/DADAHOJO/bootdev-secure-projects`

