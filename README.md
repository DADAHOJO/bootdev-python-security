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
- **Status:** ✅ Completed through **Chapter 12 (Errors)**
- **Active Days Synced:** May: 4 - 23 (2026)

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
│   ├── 09-lists/
│   ├── 10-dictionaries/
│   ├── 11-sets/
│   └── 12-errors/
├── exercises/
├── scripts/
└── notes/
    ├── chapter-lesson-summary.md
    ├── python-security-notes.md
    └── debugging-notes.md
```

## Chapter Track (1–12)

1. **Introduction** – Python basics, syntax, execution model
2. **Variables** – data types, assignment, string formatting
3. **Functions** – parameters, returns, call flow
4. **Scope** – local/global visibility and variable lifetime
5. **Testing and Debugging** – unit testing mindset, tracebacks, debugging workflow
6. **Computing** – numeric behavior, binary/bitwise foundations
7. **Comparisons** – conditionals, Boolean logic, decision flow
8. **Loops** – iteration patterns, loop control, while/for usage
9. **Lists** – indexing, mutation, operations, tuples, slicing
10. **Dictionaries** – Dictionaries, Duplicate Keys, Accessing Dictionary Values, Setting Dictionary Values, Updating Dictionary Values, Deleting Dictionary Values, ...
11. **Sets** – Sets, Sets Quiz, Vowels, Set Subtraction
12. **Errors** – Errors and Exceptions in Python, Try/Except Review, Raising Exceptions Review, Different Types of Exceptions, Raising Your Own Exceptions, Purchase

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

From your main `CascadeProjects` or `Boot.Dev` workspace root:

```powershell
.\sync-bootdev.cmd -EntryDate "YYYY-MM-DD"
```

This will:
- Discover screenshots in `Boot.Dev-screenshots/`
- Prompt you to use screenshots from `[T]oday or [P]revious date`
- OCR the screenshots to extract Chapter, Title, and Concepts
- Append progress entries to `progress-log.md`
- Update `README.md` activity sections
- Sync chapter/security mappings to `roadmap.md`
- Commit, pull, and push all three repos

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

### 2) Manual run via PowerShell (No Screenshots)

If you don't want to use screenshots, you can run the PowerShell script directly and pass the lesson data as text:

```powershell
powershell -ExecutionPolicy Bypass -File .\bootdev-python-security\scripts\run-daily-sync.ps1 `
  -Chapter 11 `
  -ChapterTitle "Sets" `
  -Concept "hash maps, set operations, deduplication" `
  -EntryDate "2026-05-18"
```

This bypasses OCR and immediately uses the text to update all markdown files and push the repos.

## Commit Quality Rules

- Skip empty commits
- Keep commits meaningful and small
- Never include secrets (`.env`, keys, tokens, cookies)
- Prefer explicit messages tied to chapter concepts and security mapping

## Related Repositories

- `https://github.com/DADAHOJO/bootdev-security-journey`
- `https://github.com/DADAHOJO/bootdev-secure-projects`

