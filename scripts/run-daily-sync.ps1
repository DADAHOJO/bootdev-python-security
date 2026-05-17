param(
  [string]$Message,
  [string]$Chapter,
  [string]$ChapterTitle,
  [string]$ChapterSummary,
  [string]$ChapterFolder,
  [string]$Concept,
  [string[]]$ScreenshotPaths,
  [string]$ScreenshotDir,
  [string]$TesseractPath = "tesseract",
  [string]$Security = "OWASP mapping update",
  [string]$ChapterFocus,
  [string]$LessonConceptsCovered,
  [string]$SecurityConnection,
  [int]$StreakActivity = 1,
  [datetime]$EntryDate = (Get-Date)
)

$projectsRoot = $null
$probe = $PSScriptRoot
for ($i = 0; $i -lt 6; $i++) {
  $hasPythonRepo = Test-Path (Join-Path $probe "bootdev-python-security")
  $hasJourneyRepo = Test-Path (Join-Path $probe "bootdev-security-journey")
  if ($hasPythonRepo -and $hasJourneyRepo) {
    $projectsRoot = $probe
    break
  }

  $parent = Split-Path -Parent $probe
  if ([string]::IsNullOrWhiteSpace($parent) -or $parent -eq $probe) {
    break
  }
  $probe = $parent
}

if ([string]::IsNullOrWhiteSpace($projectsRoot)) {
  Write-Error "Could not locate Boot.dev repositories under expected roots."
  exit 1
}

$syncScript = Join-Path $projectsRoot "bootdev-python-security\scripts\daily-sync.ps1"
$messageScript = Join-Path $projectsRoot "bootdev-python-security\scripts\generate-commit-message.ps1"
$pythonOcrScript = Join-Path $projectsRoot "bootdev-python-security\scripts\ocr-extract.py"

if (-not (Test-Path $syncScript)) {
  Write-Error "Sync script not found: $syncScript"
  exit 1
}

$defaultOwasp = "A09: Security Logging and Monitoring Failures"
$chapterSecurityDefaults = @{
  1 = "OWASP A04: Insecure Design"
  2 = "OWASP A05: Security Misconfiguration"
  3 = "OWASP A03: Injection"
  4 = "OWASP A05: Security Misconfiguration"
  5 = "OWASP A05: Security Misconfiguration"
  6 = "OWASP A04/A08: Insecure Design and Software and Data Integrity Failures"
  7 = "OWASP A01/A09: Broken Access Control and Security Logging and Monitoring Failures"
  8 = "OWASP A09: Security Logging and Monitoring Failures"
  9 = "OWASP A09: Security Logging and Monitoring Failures"
  10 = "OWASP A09: Security Logging and Monitoring Failures"
}
$chapterBreakdownSecurityDefaults = @{
  1 = "OWASP A04 (secure design fundamentals)"
  2 = "OWASP A05 (type and state safety)"
  3 = "OWASP A03 (input validation abstractions)"
  4 = "OWASP A05 (safe state boundaries)"
  5 = "OWASP A05 (safe failures, trace discipline)"
  6 = "OWASP A04/A08 (integrity-aware computation)"
  7 = "OWASP A01/A09 (decision and policy logic)"
  8 = "OWASP A09 (monitoring and iteration reliability)"
  9 = "OWASP A09 (event set processing and triage)"
  10 = "OWASP A09 (dictionary-based event context and monitoring state)"
}
$defaultScreenshotDir = Join-Path $projectsRoot "Boot.Dev-screenshots"
if ([string]::IsNullOrWhiteSpace($ScreenshotDir)) {
  $ScreenshotDir = $defaultScreenshotDir
}

if ([string]::IsNullOrWhiteSpace($TesseractPath)) {
  $TesseractPath = "tesseract"
}

$candidateTesseractPaths = @($TesseractPath)
if ($TesseractPath -eq "tesseract") {
  $tesseractFromPath = Get-Command tesseract -ErrorAction SilentlyContinue
  if ($tesseractFromPath -and -not [string]::IsNullOrWhiteSpace($tesseractFromPath.Source)) {
    $candidateTesseractPaths += $tesseractFromPath.Source
  }

  if (-not [string]::IsNullOrWhiteSpace($env:ProgramFiles)) {
    $candidateTesseractPaths += (Join-Path $env:ProgramFiles "Tesseract-OCR\tesseract.exe")
  }

  $programFilesX86 = ${env:ProgramFiles(x86)}
  if (-not [string]::IsNullOrWhiteSpace($programFilesX86)) {
    $candidateTesseractPaths += (Join-Path $programFilesX86 "Tesseract-OCR\tesseract.exe")
  }

  $candidateTesseractPaths += (Join-Path $projectsRoot "tesseract\tesseract.exe")
  $candidateTesseractPaths += (Join-Path $projectsRoot "Tesseract\tesseract.exe")
  $candidateTesseractPaths += (Join-Path $env:USERPROFILE "OneDrive - Dell Technologies\Study Material & Cert\Server Support Program\tesseract\Tesseract.exe")
}

$validTesseractPaths = @(
  $candidateTesseractPaths |
    Where-Object { -not [string]::IsNullOrWhiteSpace($_) -and (Test-Path $_) } |
    Select-Object -Unique
)
if ($validTesseractPaths.Count -gt 0) {
  $TesseractPath = $validTesseractPaths |
    Sort-Object {
      $rawVersion = (Get-Item $_).VersionInfo.ProductVersion
      $cleanVersion = if ($rawVersion -match '^\d+(\.\d+){1,3}') { $matches[0] } else { "0.0.0.0" }
      [version]$cleanVersion
    } -Descending |
    Select-Object -First 1
}

if (([string]::IsNullOrWhiteSpace($Chapter) -or [string]::IsNullOrWhiteSpace($ChapterTitle) -or [string]::IsNullOrWhiteSpace($Concept)) -and (-not $ScreenshotPaths -or $ScreenshotPaths.Count -eq 0)) {
  if (Test-Path $ScreenshotDir) {
    $imageFiles = Get-ChildItem -Path $ScreenshotDir -File |
      Where-Object { $_.Extension -match '^\.(png|jpg|jpeg|bmp|gif)$' } |
      Sort-Object LastWriteTime
    if ($imageFiles.Count -gt 0) {
      $todayDate = $EntryDate.Date
      $todayFiles = $imageFiles | Where-Object { $_.LastWriteTime.Date -eq $todayDate }
      $previousFiles = $imageFiles | Where-Object { $_.LastWriteTime.Date -ne $todayDate }
      $usePrevious = $false
      $choice = Read-Host "Use screenshots from [T]oday or [P]revious date? (default T)"
      if ($choice -match '^(?i)p') {
        $usePrevious = $true
      }

      if ($usePrevious) {
        $previousDates = $previousFiles |
          Group-Object { $_.LastWriteTime.Date.ToString("yyyy-MM-dd") } |
          Where-Object { -not [string]::IsNullOrWhiteSpace($_.Name) } |
          Sort-Object Name
        if (-not $previousDates -or $previousDates.Count -eq 0) {
          Write-Host "No previous screenshots found. Using today's screenshots if available."
          $usePrevious = $false
        } else {
          Write-Host "Available previous dates:"
          for ($i = 0; $i -lt $previousDates.Count; $i++) {
            Write-Host ("{0}. {1}" -f ($i + 1), $previousDates[$i].Name)
          }

          $dateChoice = Read-Host "Select a date number (or type a date yyyy-MM-dd)"
          $selectedDateKey = $null
          if ($dateChoice -match '^\d+$' -and [int]$dateChoice -ge 1 -and [int]$dateChoice -le $previousDates.Count) {
            $selectedDateKey = $previousDates[[int]$dateChoice - 1].Name
          } elseif (-not [string]::IsNullOrWhiteSpace($dateChoice) -and ($previousDates.Name -contains $dateChoice)) {
            $selectedDateKey = $dateChoice
          }

          if (-not $selectedDateKey) {
            $selectedDateKey = $previousDates[$previousDates.Count - 1].Name
          }

          $ScreenshotPaths = $previousFiles |
            Where-Object { $_.LastWriteTime.Date.ToString("yyyy-MM-dd") -eq $selectedDateKey } |
            Sort-Object LastWriteTime |
            Select-Object -ExpandProperty FullName
        }
      }

      if (-not $usePrevious) {
        $ScreenshotPaths = $todayFiles |
          Sort-Object LastWriteTime |
          Select-Object -ExpandProperty FullName
      }
    }
  }
}

if ($ScreenshotPaths -and $ScreenshotPaths.Count -gt 0) {
  $needsOcr = [string]::IsNullOrWhiteSpace($Chapter) -or [string]::IsNullOrWhiteSpace($ChapterTitle) -or [string]::IsNullOrWhiteSpace($Concept)
  $pythonInstallHint = "Install EasyOCR for Python 3.11: py -3.11 -m pip install --upgrade pip ; py -3.11 -m pip install easyocr"

  if ($needsOcr -and (Test-Path $pythonOcrScript)) {
    $pythonLauncher = $null
    $pythonPrefixArgs = @()

    $pyCommand = Get-Command py -ErrorAction SilentlyContinue
    if ($pyCommand) {
      & $pyCommand.Source -3.11 --version *> $null
      if ($LASTEXITCODE -eq 0) {
        $pythonLauncher = $pyCommand.Source
        $pythonPrefixArgs = @("-3.11")
      }
    }

    if ($pythonLauncher) {
      $pythonArgs = @()
      $pythonArgs += $pythonPrefixArgs
      $pythonArgs += @($pythonOcrScript)
      foreach ($path in $ScreenshotPaths) {
        $pythonArgs += @("--screenshot", $path)
      }

      $pythonOutput = & $pythonLauncher @pythonArgs 2>$null
      $pythonJson = ($pythonOutput | Out-String).Trim()
      if (-not [string]::IsNullOrWhiteSpace($pythonJson)) {
        try {
          $pythonResult = $pythonJson | ConvertFrom-Json
          if ([string]::IsNullOrWhiteSpace($Chapter) -and -not [string]::IsNullOrWhiteSpace($pythonResult.chapter)) {
            $Chapter = $pythonResult.chapter
          }

          if ([string]::IsNullOrWhiteSpace($ChapterTitle) -and -not [string]::IsNullOrWhiteSpace($pythonResult.chapterTitle)) {
            $ChapterTitle = $pythonResult.chapterTitle
          }

          if ([string]::IsNullOrWhiteSpace($Concept) -and -not [string]::IsNullOrWhiteSpace($pythonResult.concept)) {
            $Concept = $pythonResult.concept
          }

          if ((-not [string]::IsNullOrWhiteSpace($Chapter) -or -not [string]::IsNullOrWhiteSpace($ChapterTitle) -or -not [string]::IsNullOrWhiteSpace($Concept))) {
            Write-Host "Extracted screenshot text using Python OCR helper."
          } elseif ($pythonResult.error -eq "easyocr_not_installed") {
            Write-Host "EasyOCR not installed. Falling back to Tesseract/manual input."
            Write-Host $pythonInstallHint
          }
        } catch {
          Write-Host "Python OCR output could not be parsed. Falling back to Tesseract/manual input."
        }
      }
    } else {
      Write-Host "Python 3.11 not found via py launcher. Falling back to Tesseract/manual input."
      Write-Host $pythonInstallHint
    }
  }

  $needsOcr = [string]::IsNullOrWhiteSpace($Chapter) -or [string]::IsNullOrWhiteSpace($ChapterTitle) -or [string]::IsNullOrWhiteSpace($Concept)
  if ($needsOcr) {
    $tesseractExecutable = $null
    if (Test-Path $TesseractPath -PathType Leaf) {
      $tesseractExecutable = $TesseractPath
    } else {
      $tesseractCommand = Get-Command $TesseractPath -ErrorAction SilentlyContinue
      if ($tesseractCommand) {
        $tesseractExecutable = $tesseractCommand.Source
      }
    }

    if ($tesseractExecutable) {
      $ocrText = ""
      foreach ($path in $ScreenshotPaths) {
        if (-not (Test-Path $path)) {
          Write-Host "Screenshot not found: $path"
          continue
        }

        $ocrText += (& $tesseractExecutable $path stdout 2>$null)
        $ocrText += "`n"
      }

      $ocrLines = $ocrText -split "`r?`n" | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne "" }
      foreach ($line in $ocrLines) {
        if ([string]::IsNullOrWhiteSpace($Chapter) -and $line -match '(?i)\bCH\s*(\d{1,2})\s*[:\-]\s*(.+)$') {
          $Chapter = $matches[1]
          $ChapterTitle = $matches[2].Trim()
          continue
        }
      }

      $lessonItems = @()
      foreach ($line in $ocrLines) {
        if ($line -match '^\s*\d+\s*[:\-]\s*(.+)$') {
          $lesson = $matches[1].Trim()
          if (-not [string]::IsNullOrWhiteSpace($lesson)) {
            $lessonItems += $lesson
          }
        }
      }

      if ($lessonItems.Count -gt 0 -and [string]::IsNullOrWhiteSpace($Concept)) {
        $Concept = ($lessonItems | Select-Object -Unique) -join ", "
      }
    } else {
      Write-Host "Tesseract not found. Falling back to manual input."
    }
  }
}

if ([string]::IsNullOrWhiteSpace($Chapter)) {
  $Chapter = Read-Host "Enter chapter number"
}

if ([string]::IsNullOrWhiteSpace($ChapterTitle)) {
  $ChapterTitle = Read-Host "Enter chapter title"
}

if ([string]::IsNullOrWhiteSpace($Concept)) {
  $Concept = Read-Host "Enter lesson concepts covered (comma-separated)"
}

if ([string]::IsNullOrWhiteSpace($ChapterFolder) -and -not [string]::IsNullOrWhiteSpace($Chapter) -and -not [string]::IsNullOrWhiteSpace($ChapterTitle)) {
  $slug = $ChapterTitle.ToLowerInvariant() -replace '[^a-z0-9]+', '-'
  $slug = $slug.Trim('-')
  if (-not [string]::IsNullOrWhiteSpace($slug)) {
    $chapterFolderPrefix = if ($Chapter -match '^\d+$') { "{0:D2}" -f [int]$Chapter } else { $Chapter }
    $ChapterFolder = "$chapterFolderPrefix-$slug"
  }
}

$chapterNumberFromInput = if (-not [string]::IsNullOrWhiteSpace($Chapter) -and $Chapter -match '^\d+$') { [int]$Chapter } else { $null }
if ([string]::IsNullOrWhiteSpace($Security) -or $Security -eq "OWASP mapping update") {
  if ($chapterNumberFromInput -and $chapterSecurityDefaults.ContainsKey($chapterNumberFromInput)) {
    $Security = $chapterSecurityDefaults[$chapterNumberFromInput]
  } else {
    $Security = $defaultOwasp
  }
}

if ([string]::IsNullOrWhiteSpace($Message) -and -not [string]::IsNullOrWhiteSpace($Chapter) -and -not [string]::IsNullOrWhiteSpace($Concept)) {
  if (-not (Test-Path $messageScript)) {
    Write-Error "Commit message generator not found: $messageScript"
    exit 1
  }

  $Message = powershell -ExecutionPolicy Bypass -File $messageScript -Chapter $Chapter -Concept $Concept -Security $Security
}

if ([string]::IsNullOrWhiteSpace($Message)) {
  $Message = "docs: daily Boot.dev learning sync"
}

if ([string]::IsNullOrWhiteSpace($ChapterFocus)) {
  if (-not [string]::IsNullOrWhiteSpace($Chapter) -and -not [string]::IsNullOrWhiteSpace($ChapterTitle)) {
    $ChapterFocus = "Chapter $Chapter - $ChapterTitle"
  } elseif (-not [string]::IsNullOrWhiteSpace($Chapter)) {
    $ChapterFocus = "Chapter $Chapter"
  } else {
    $ChapterFocus = "General learning update"
  }
}

if ([string]::IsNullOrWhiteSpace($LessonConceptsCovered)) {
  if (-not [string]::IsNullOrWhiteSpace($Concept)) {
    $LessonConceptsCovered = $Concept
  } else {
    $LessonConceptsCovered = "progress updates"
  }
}

if ([string]::IsNullOrWhiteSpace($SecurityConnection)) {
  $SecurityConnection = $Security
}

$chapterRootPath = Join-Path $projectsRoot "bootdev-python-security\chapters"
$chapterSummaryNotesPath = Join-Path $projectsRoot "bootdev-python-security\notes\chapter-lesson-summary.md"
$entryDateText = $EntryDate.ToString("MMMM d, yyyy")

$lessonItems = @()
if (-not [string]::IsNullOrWhiteSpace($LessonConceptsCovered)) {
  $lessonItems = @(
    $LessonConceptsCovered -split ',' |
      ForEach-Object { $_.Trim() } |
      Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
      Select-Object -Unique
  )
}

if ($lessonItems.Count -eq 0 -and -not [string]::IsNullOrWhiteSpace($Concept)) {
  $lessonItems = @(
    $Concept -split ',' |
      ForEach-Object { $_.Trim() } |
      Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
      Select-Object -Unique
  )
}

if ($lessonItems.Count -eq 0) {
  $lessonItems = @("progress updates")
}

$hasSpecificLearningPayload = $chapterNumberFromInput -and -not [string]::IsNullOrWhiteSpace($ChapterTitle) -and -not [string]::IsNullOrWhiteSpace($Concept) -and $Concept.Trim().ToLowerInvariant() -ne "progress updates"

if (-not [string]::IsNullOrWhiteSpace($ChapterFolder)) {
  $chapterDirPath = Join-Path $chapterRootPath $ChapterFolder
  if (-not (Test-Path $chapterDirPath)) {
    New-Item -ItemType Directory -Path $chapterDirPath -Force | Out-Null
  }

  $chapterReadmePath = Join-Path $chapterDirPath "README.md"
  $chapterGoalText = if (-not [string]::IsNullOrWhiteSpace($ChapterSummary)) {
    $ChapterSummary
  } else {
    "Consolidate this chapter's Python concepts and apply them to secure coding practices."
  }

  $chapterLines = [System.Collections.Generic.List[string]]::new()
  [void]$chapterLines.Add("# Chapter ${Chapter}: $ChapterTitle")
  [void]$chapterLines.Add("")
  [void]$chapterLines.Add("Boot.dev `"Learn to Code in Python`" - Chapter $Chapter")
  [void]$chapterLines.Add("")
  [void]$chapterLines.Add("## Chapter Goal")
  [void]$chapterLines.Add($chapterGoalText)
  [void]$chapterLines.Add("")
  [void]$chapterLines.Add("## Lesson Concepts Covered")
  foreach ($lesson in $lessonItems) {
    [void]$chapterLines.Add("- $lesson")
  }
  [void]$chapterLines.Add("")
  [void]$chapterLines.Add("## Security Mapping")
  [void]$chapterLines.Add("- **$SecurityConnection**")
  [void]$chapterLines.Add("- Learning outcomes aligned with secure coding and monitoring practices.")
  [void]$chapterLines.Add("")
  [void]$chapterLines.Add("## Portfolio Application")
  [void]$chapterLines.Add("- Translate these concepts into secure coding exercises and repo examples.")
  [void]$chapterLines.Add("- Keep chapter artifacts synced with progress logs and README updates.")
  [void]$chapterLines.Add("")
  [void]$chapterLines.Add("## Completion Notes")
  [void]$chapterLines.Add("- Latest activity: $entryDateText")
  [void]$chapterLines.Add("- Streak activity recorded: $StreakActivity")
  [void]$chapterLines.Add("")

  Set-Content -Path $chapterReadmePath -Value $chapterLines -Encoding UTF8
  Write-Host "Updated chapter artifact: $chapterReadmePath"
}

if ((Test-Path $chapterSummaryNotesPath) -and -not [string]::IsNullOrWhiteSpace($Chapter) -and -not [string]::IsNullOrWhiteSpace($ChapterTitle)) {
  $summaryLines = [System.Collections.Generic.List[string]](Get-Content -Path $chapterSummaryNotesPath -Encoding UTF8)
  $summaryHeader = "## CH${Chapter}: $ChapterTitle"

  $sectionStart = -1
  for ($i = 0; $i -lt $summaryLines.Count; $i++) {
    if ($summaryLines[$i].Trim() -eq $summaryHeader) {
      $sectionStart = $i
      break
    }
  }

  if ($sectionStart -ge 0) {
    $sectionEnd = $summaryLines.Count
    for ($i = $sectionStart + 1; $i -lt $summaryLines.Count; $i++) {
      if ($summaryLines[$i] -match '^##\s+CH') {
        $sectionEnd = $i
        break
      }
    }
    $summaryLines.RemoveRange($sectionStart, $sectionEnd - $sectionStart)
  } else {
    if ($summaryLines.Count -gt 0 -and -not [string]::IsNullOrWhiteSpace($summaryLines[$summaryLines.Count - 1])) {
      [void]$summaryLines.Add("")
    }
    $sectionStart = $summaryLines.Count
  }

  $sectionLines = [System.Collections.Generic.List[string]]::new()
  [void]$sectionLines.Add($summaryHeader)
  foreach ($lesson in $lessonItems) {
    [void]$sectionLines.Add("- $lesson")
  }
  [void]$sectionLines.Add("")

  $summaryLines.InsertRange($sectionStart, $sectionLines)
  Set-Content -Path $chapterSummaryNotesPath -Value $summaryLines -Encoding UTF8
  Write-Host "Updated chapter summary notes: $chapterSummaryNotesPath"
}

$activityWord = if ($StreakActivity -eq 1) { "activity" } else { "activities" }
$entryMonthHeader = "## $($EntryDate.ToString("MMMM yyyy"))"
$entryHeaderLine = "### $entryDateText"

function Format-ActiveDaysList {
  param([datetime[]]$Dates)

  $sortedDates = @($Dates | Sort-Object -Unique)
  if ($sortedDates.Count -eq 0) {
    return ""
  }

  $groups = $sortedDates | Group-Object { "{0}-{1}" -f $_.Year, $_.Month }
  $segments = @()
  foreach ($group in ($groups | Sort-Object Name)) {
    $groupDates = @($group.Group | Sort-Object)
    if ($groupDates.Count -eq 0) {
      continue
    }

    $monthName = $groupDates[0].ToString("MMMM")
    $yearValue = $groupDates[0].Year
    $startDay = $groupDates[0].Day
    $endDay = $groupDates[$groupDates.Count - 1].Day
    if ($startDay -eq $endDay) {
      $segments += "${monthName}: $startDay ($yearValue)"
    } else {
      $segments += "${monthName}: $startDay - $endDay ($yearValue)"
    }
  }

  return ($segments -join "; ")
}

function Get-ProgressSnapshot {
  param([string]$ProgressLogPath)

  $snapshot = [ordered]@{
    ActiveDates = @()
    ChapterRecords = @()
    MaxChapter = $null
    MaxChapterTitle = ""
  }

  if (-not (Test-Path $ProgressLogPath)) {
    return [pscustomobject]$snapshot
  }

  $lines = Get-Content -Path $ProgressLogPath -Encoding UTF8
  $currentDate = $null
  foreach ($line in $lines) {
    $trimmed = $line.Trim()

    if ($trimmed -match '^###\s+([A-Za-z]+\s+\d{1,2},\s+\d{4})$') {
      try {
        $currentDate = (Get-Date $matches[1]).Date
        $snapshot.ActiveDates += $currentDate
      } catch {
        $currentDate = $null
      }
      continue
    }

    if (-not $currentDate) {
      continue
    }

    $focusText = $null
    if ($trimmed -match '^\-\s+\*\*Chapter Focus:\*\*\s*(.+)$' -or $trimmed -match '^\-\s+\*\*Progress Sync:\*\*\s*(.+)$' -or $trimmed -match '^Chapter Focus:\s*(.+)$' -or $trimmed -match '^Progress Sync:\s*(.+)$') {
      $focusText = $matches[1].Trim()
    }

    if ([string]::IsNullOrWhiteSpace($focusText)) {
      continue
    }

    $chapterNumber = $null
    $chapterTitle = ""
    if ($focusText -match 'Chapter\s+(\d+)\s*\-\s*([^\|]+)$') {
      $chapterNumber = [int]$matches[1]
      $chapterTitle = $matches[2].Trim()
    } elseif ($focusText -match 'Chapter\s+(\d+)\s*\(([^\)]+)\)') {
      $chapterNumber = [int]$matches[1]
      $chapterTitle = $matches[2].Trim()
    } elseif ($focusText -match 'Chapter\s+(\d+)') {
      $chapterNumber = [int]$matches[1]
    }

    if ($chapterNumber) {
      $snapshot.ChapterRecords += [pscustomobject]@{
        Chapter = $chapterNumber
        Title = $chapterTitle
        Date = $currentDate
      }
    }
  }

  $snapshot.ActiveDates = @($snapshot.ActiveDates | Sort-Object -Unique)

  if ($snapshot.ChapterRecords.Count -gt 0) {
    $maxChapter = ($snapshot.ChapterRecords | Measure-Object -Property Chapter -Maximum).Maximum
    $snapshot.MaxChapter = [int]$maxChapter

    $maxRecords = @($snapshot.ChapterRecords | Where-Object { $_.Chapter -eq $maxChapter } | Sort-Object Date)
    if ($maxRecords.Count -gt 0) {
      $preferredTitle = ($maxRecords | Where-Object { -not [string]::IsNullOrWhiteSpace($_.Title) } | Select-Object -Last 1)
      if ($preferredTitle) {
        $snapshot.MaxChapterTitle = $preferredTitle.Title
      }
    }
  }

  return [pscustomobject]$snapshot
}

function Find-LineIndex {
  param(
    [System.Collections.Generic.List[string]]$Lines,
    [scriptblock]$Predicate,
    [int]$StartIndex = 0
  )

  if (-not $Lines -or -not $Predicate) {
    return -1
  }

  $start = [Math]::Max(0, $StartIndex)
  for ($index = $start; $index -lt $Lines.Count; $index++) {
    if (& $Predicate $Lines[$index]) {
      return $index
    }
  }

  return -1
}

function Get-CompletionWindowText {
  param([datetime[]]$Dates)

  $sortedDates = @($Dates | Sort-Object -Unique)
  if ($sortedDates.Count -eq 0) {
    return "In Progress"
  }

  $startDate = $sortedDates[0]
  $endDate = $sortedDates[$sortedDates.Count - 1]
  if ($startDate.Date -eq $endDate.Date) {
    return $startDate.ToString("MMMM d")
  }

  if ($startDate.Year -eq $endDate.Year -and $startDate.Month -eq $endDate.Month) {
    return "{0} {1}-{2}" -f $startDate.ToString("MMMM"), $startDate.Day, $endDate.Day
  }

  if ($startDate.Year -eq $endDate.Year) {
    return "{0} {1}-{2} {3}" -f $startDate.ToString("MMM"), $startDate.Day, $endDate.ToString("MMM"), $endDate.Day
  }

  return "{0} - {1}" -f $startDate.ToString("MMM d, yyyy"), $endDate.ToString("MMM d, yyyy")
}

function Get-OwaspCodesFromText {
  param([string]$Text)

  if ([string]::IsNullOrWhiteSpace($Text)) {
    return @()
  }

  $codeMatches = [regex]::Matches($Text, 'A\d{2}', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
  $codes = @()
  foreach ($match in $codeMatches) {
    $code = $match.Value.ToUpperInvariant()
    if ($codes -notcontains $code) {
      $codes += $code
    }
  }

  return $codes
}

function Get-ChapterTrackDetail {
  param(
    [string]$Summary,
    [string[]]$ConceptItems,
    [string]$FallbackConcept
  )

  if (-not [string]::IsNullOrWhiteSpace($Summary)) {
    return $Summary.Trim()
  }

  $items = @($ConceptItems | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -Unique)
  if ($items.Count -eq 0 -and -not [string]::IsNullOrWhiteSpace($FallbackConcept)) {
    $items = @(
      $FallbackConcept -split ',' |
        ForEach-Object { $_.Trim() } |
        Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
        Select-Object -Unique
    )
  }

  if ($items.Count -eq 0) {
    return "topic coverage"
  }

  $selectedItems = @($items | Select-Object -First 6)
  $detail = ($selectedItems -join ", ")
  if ($items.Count -gt $selectedItems.Count) {
    $detail = "$detail, ..."
  }

  return $detail
}

function Get-NormalizedTokens {
  param([string]$Text)

  if ([string]::IsNullOrWhiteSpace($Text)) {
    return @()
  }

  $stopWords = @("learn", "to", "in", "and", "or", "the", "a", "an", "of", "for", "with", "boot", "dev", "course", "current", "build", "start")
  $rawTokens = ($Text.ToLowerInvariant() -replace '[^a-z0-9]+', ' ') -split '\s+'
  $tokens = @()
  foreach ($token in $rawTokens) {
    if (-not [string]::IsNullOrWhiteSpace($token) -and $token.Length -ge 2 -and $stopWords -notcontains $token -and $tokens -notcontains $token) {
      $tokens += $token
    }
  }

  return $tokens
}

function Get-CourseRepoInventory {
  param([string]$ProjectsRoot)

  $inventory = @()
  if (-not (Test-Path $ProjectsRoot)) {
    return $inventory
  }

  $repoDirs = Get-ChildItem -Path $ProjectsRoot -Directory | Where-Object {
    $_.Name -like 'bootdev-*' -and
    $_.Name -ne 'bootdev-security-journey' -and
    $_.Name -ne 'bootdev-secure-projects' -and
    (Test-Path (Join-Path $_.FullName 'security-mapping.md'))
  }

  foreach ($repoDir in $repoDirs) {
    $repoStem = ($repoDir.Name -replace '^bootdev-', '') -replace '[-_]+', ' '
    $inventory += [pscustomobject]@{
      Name = $repoDir.Name
      NameLower = $repoDir.Name.ToLowerInvariant()
      Path = $repoDir.FullName
      Tokens = @(Get-NormalizedTokens -Text $repoStem)
    }
  }

  return $inventory
}

function Get-SectionRepoHint {
  param([string[]]$SectionLines)

  if (-not $SectionLines -or $SectionLines.Count -eq 0) {
    return $null
  }

  foreach ($line in $SectionLines) {
    $trimmed = $line.Trim()

    if ($trimmed -match '^<!--\s*Sync\s+Hint:\s*\[repo:\s*([^\]]+)\s*\]\s*-->$') {
      return $matches[1].Trim()
    }

    if ($trimmed -match '^<!--\s*repo:\s*([^\-].*?)\s*-->$') {
      return $matches[1].Trim()
    }

    if ($trimmed -match '^>\s*Sync\s+Hint:\s*\[repo:\s*([^\]]+)\s*\]\s*$') {
      return $matches[1].Trim()
    }

    if ($trimmed -match '^\[repo:\s*([^\]]+)\s*\]$') {
      return $matches[1].Trim()
    }
  }

  return $null
}

function Resolve-CourseRepoPath {
  param(
    [string]$CourseHeading,
    [string]$ProjectsRoot,
    [object[]]$RepoInventory,
    [string[]]$SectionLines = @()
  )

  if ([string]::IsNullOrWhiteSpace($CourseHeading)) {
    return $null
  }

  $courseTitle = $CourseHeading.Trim()
  $repoHint = $null

  if ($courseTitle -match '^(.*?)\s+\[repo:\s*([^\]]+)\s*\]\s*$') {
    $courseTitle = $matches[1].Trim()
    $repoHint = $matches[2].Trim()
  } elseif ($courseTitle -match '^(.*?)\s+\(repo:\s*([^\)]+)\)\s*$') {
    $courseTitle = $matches[1].Trim()
    $repoHint = $matches[2].Trim()
  }

  if ([string]::IsNullOrWhiteSpace($repoHint)) {
    $repoHint = Get-SectionRepoHint -SectionLines $SectionLines
  }

  if (-not [string]::IsNullOrWhiteSpace($repoHint)) {
    $candidateNames = @($repoHint)
    if ($repoHint -notmatch '^bootdev-') {
      $candidateNames += "bootdev-$repoHint"
    }

    foreach ($candidateName in @($candidateNames | Select-Object -Unique)) {
      $candidatePath = Join-Path $ProjectsRoot $candidateName
      if ((Test-Path $candidatePath) -and (Test-Path (Join-Path $candidatePath 'security-mapping.md'))) {
        return $candidatePath
      }
    }
  }

  if (-not $RepoInventory -or $RepoInventory.Count -eq 0) {
    return $null
  }

  $courseTokens = @(Get-NormalizedTokens -Text $courseTitle)
  if ($courseTokens.Count -eq 0) {
    return $null
  }

  $scoredMatches = @()
  foreach ($repo in $RepoInventory) {
    $score = 0
    $matchedTokens = 0
    foreach ($token in $courseTokens) {
      if ($repo.Tokens -contains $token) {
        $score += 3
        $matchedTokens += 1
      } elseif ($repo.NameLower -like "*$token*") {
        $score += 1
      }
    }

    if ($score -gt 0) {
      $scoredMatches += [pscustomobject]@{
        Path = $repo.Path
        Score = $score
        Matched = $matchedTokens
      }
    }
  }

  if ($scoredMatches.Count -eq 0) {
    return $null
  }

  $orderedMatches = @($scoredMatches | Sort-Object @{ Expression = 'Score'; Descending = $true }, @{ Expression = 'Matched'; Descending = $true })
  if ($orderedMatches.Count -gt 1 -and $orderedMatches[0].Score -eq $orderedMatches[1].Score -and $orderedMatches[0].Matched -eq $orderedMatches[1].Matched) {
    return $null
  }

  return $orderedMatches[0].Path
}

function Get-SecurityFrameworkLabel {
  param([string]$Text)

  if ([string]::IsNullOrWhiteSpace($Text)) {
    return ""
  }

  $normalized = $Text.ToLowerInvariant()
  if ($normalized -match 'owasp\s+asvs') {
    return "OWASP ASVS"
  }
  if ($normalized -match 'nist\s+ssdf') {
    return "NIST SSDF"
  }
  if ($normalized -match 'owasp') {
    return "OWASP Top 10"
  }

  return ""
}

function Get-AutoFrameworksForChapter {
  param(
    [string]$ChapterTitle,
    [string]$ConnectionText
  )

  $normalized = "$ChapterTitle $ConnectionText".ToLowerInvariant()
  $asvsTriggered = $normalized -match '(backend|api|http|endpoint|authentication|authorization|auth\b|server|sql|database)'
  $ssdfTriggered = $normalized -match '(ci/cd|cicd|pipeline|devsecops|github actions|deployment|release|supply chain|container|docker|kubernetes)'

  return [pscustomobject]@{
    Asvs = $asvsTriggered
    Ssdf = $ssdfTriggered
  }
}

function Get-CourseSecurityMappingSnapshot {
  param([string]$MappingPath)

  $snapshot = [ordered]@{
    Chapters = @()
    SecurityConnections = @()
    MappingSummary = ""
  }

  if (-not (Test-Path $MappingPath)) {
    return [pscustomobject]$snapshot
  }

  $mappingLines = Get-Content -Path $MappingPath -Encoding UTF8
  $chapters = @()
  $frameworksDetected = @()
  $currentChapter = $null
  $activeFramework = ""

  foreach ($line in $mappingLines) {
    $trimmed = $line.Trim()

    if ($trimmed -match '^###\s+(?:Chapter|Lesson|Module|Unit|Topic)\s*(\d+)\s*[:\-]\s*(.+)$' -or $trimmed -match '^###\s*(?:CH|Ch)\s*(\d+)\s*[:\-]\s*(.+)$' -or $trimmed -match '^###\s*(\d+)\s*[\.:\-]\s*(.+)$') {
      if ($currentChapter) {
        $chapters += [pscustomobject]$currentChapter
      }
      $currentChapter = [ordered]@{
        Number = [int]$matches[1]
        Title = $matches[2].Trim()
        Owasp = ""
        Connection = ""
        FrameworkDetails = @{}
        ConnectionNotes = @()
      }
      $activeFramework = ""
      continue
    }

    if (-not $currentChapter) {
      continue
    }

    if ($trimmed -match '^\*\*(.+?)\*\*$') {
      $activeFramework = Get-SecurityFrameworkLabel -Text $matches[1].Trim()
      if (-not [string]::IsNullOrWhiteSpace($activeFramework) -and $frameworksDetected -notcontains $activeFramework) {
        $frameworksDetected += $activeFramework
      }
      continue
    }

    if ($trimmed -match '^\-\s*\*\*(.+)\*\*$') {
      $emphasisValue = $matches[1].Trim().TrimEnd('.')
      if ($activeFramework -eq "OWASP Top 10" -and [string]::IsNullOrWhiteSpace($currentChapter.Owasp)) {
        $currentChapter.Owasp = $emphasisValue
      }
      if (-not [string]::IsNullOrWhiteSpace($activeFramework) -and -not $currentChapter.FrameworkDetails.ContainsKey($activeFramework)) {
        $currentChapter.FrameworkDetails[$activeFramework] = $emphasisValue
      }
      continue
    }

    if ($trimmed -match '^\-\s*(?:\*\*)?(OWASP(?:\s+Top\s*10|\s+ASVS)?|NIST\s+SSDF)(?:\*\*)?\s*[:\-]\s*(.+)$') {
      $framework = Get-SecurityFrameworkLabel -Text $matches[1]
      $detail = $matches[2].Trim().TrimEnd('.')
      if (-not [string]::IsNullOrWhiteSpace($framework)) {
        if ($frameworksDetected -notcontains $framework) {
          $frameworksDetected += $framework
        }
        $currentChapter.FrameworkDetails[$framework] = $detail
      }
      continue
    }

    if ($trimmed -match '^\-\s*(?:Connection|Security\s+connection|Security\s+use|Security\s+focus):\s*(.+)$') {
      $connectionValue = $matches[1].Trim().TrimEnd('.')
      if (-not [string]::IsNullOrWhiteSpace($activeFramework)) {
        if ($activeFramework -eq "OWASP Top 10" -and -not [string]::IsNullOrWhiteSpace($currentChapter.Owasp) -and $connectionValue -notmatch '(?i)owasp|A\d{2}') {
          $connectionValue = "$connectionValue ($($currentChapter.Owasp))"
        }

        if ($currentChapter.FrameworkDetails.ContainsKey($activeFramework) -and -not [string]::IsNullOrWhiteSpace($currentChapter.FrameworkDetails[$activeFramework]) -and $currentChapter.FrameworkDetails[$activeFramework] -ne $connectionValue) {
          $currentChapter.FrameworkDetails[$activeFramework] = "$($currentChapter.FrameworkDetails[$activeFramework]); $connectionValue"
        } else {
          $currentChapter.FrameworkDetails[$activeFramework] = $connectionValue
        }
      } else {
        $currentChapter.ConnectionNotes += $connectionValue
        if ([string]::IsNullOrWhiteSpace($currentChapter.Connection)) {
          $currentChapter.Connection = $connectionValue
        }
      }
      continue
    }

    if (-not [string]::IsNullOrWhiteSpace($activeFramework) -and $trimmed -match '^\-\s+(.+)$') {
      $fallbackDetail = $matches[1].Trim().TrimEnd('.')
      if (-not $currentChapter.FrameworkDetails.ContainsKey($activeFramework)) {
        $currentChapter.FrameworkDetails[$activeFramework] = $fallbackDetail
      }
      continue
    }

    if ($trimmed -match '^\*\*.+\*\*:?$' -or $trimmed -match '^###\s+' -or $trimmed -match '^##\s+') {
      $activeFramework = ""
    }
  }

  if ($currentChapter) {
    $chapters += [pscustomobject]$currentChapter
  }

  $chapters = @($chapters | Sort-Object Number)
  $snapshot.Chapters = $chapters

  $connections = @()
  $rightArrowLocal = [char]0x2192
  $frameworkPriority = @("OWASP Top 10", "OWASP ASVS", "NIST SSDF")
  foreach ($chapter in $chapters) {
    $chapterContextText = "$($chapter.Connection) $(@($chapter.ConnectionNotes) -join ' ')"
    $autoFrameworks = Get-AutoFrameworksForChapter -ChapterTitle $chapter.Title -ConnectionText $chapterContextText
    if ($autoFrameworks.Asvs -and -not $chapter.FrameworkDetails.ContainsKey("OWASP ASVS")) {
      $chapter.FrameworkDetails["OWASP ASVS"] = "checklist mapping in progress"
      if ($frameworksDetected -notcontains "OWASP ASVS") {
        $frameworksDetected += "OWASP ASVS"
      }
    }
    if ($autoFrameworks.Ssdf -and -not $chapter.FrameworkDetails.ContainsKey("NIST SSDF")) {
      $chapter.FrameworkDetails["NIST SSDF"] = "workflow mapping in progress"
      if ($frameworksDetected -notcontains "NIST SSDF") {
        $frameworksDetected += "NIST SSDF"
      }
    }

    $connectionText = ""

    if ($chapter.FrameworkDetails -and $chapter.FrameworkDetails.Count -gt 0) {
      $orderedFrameworks = @(
        ($frameworkPriority | Where-Object { $chapter.FrameworkDetails.ContainsKey($_) }) +
        (@($chapter.FrameworkDetails.Keys | Where-Object { $frameworkPriority -notcontains $_ } | Sort-Object))
      )

      $frameworkParts = @()
      foreach ($framework in $orderedFrameworks) {
        $detail = "$($chapter.FrameworkDetails[$framework])".Trim().TrimEnd('.')
        if ([string]::IsNullOrWhiteSpace($detail)) {
          $detail = "mapped controls documented"
        }

        if ($framework -eq "OWASP Top 10" -and -not [string]::IsNullOrWhiteSpace($chapter.Owasp) -and $detail -notmatch '(?i)owasp|A\d{2}') {
          $detail = "$detail ($($chapter.Owasp))"
        }

        $frameworkParts += "${framework}: $detail"
      }

      if ($frameworkParts.Count -gt 0) {
        $connectionText = $frameworkParts -join '; '
      }
    }

    if ([string]::IsNullOrWhiteSpace($connectionText)) {
      if ($chapter.ConnectionNotes -and $chapter.ConnectionNotes.Count -gt 0) {
        $connectionText = (@($chapter.ConnectionNotes | Select-Object -Unique) -join '; ').Trim()
      } elseif (-not [string]::IsNullOrWhiteSpace($chapter.Connection)) {
        $connectionText = $chapter.Connection.Trim().TrimEnd('.')
      } else {
        $connectionText = "chapter security mapping in progress"
      }

      if (-not [string]::IsNullOrWhiteSpace($chapter.Owasp) -and $connectionText -notmatch '(?i)owasp|A\d{2}') {
        $connectionText = "$connectionText ($($chapter.Owasp))"
      }
    }

    $connections += "- $($chapter.Title) $rightArrowLocal $connectionText"
  }

  $orderedDetected = @(
    ($frameworkPriority | Where-Object { $frameworksDetected -contains $_ }) +
    (@($frameworksDetected | Where-Object { $frameworkPriority -notcontains $_ } | Sort-Object))
  )
  if ($orderedDetected.Count -gt 0) {
    $snapshot.MappingSummary = $orderedDetected -join ', '
  }

  $snapshot.SecurityConnections = $connections
  return [pscustomobject]$snapshot
}

function Set-CourseSectionBlock {
  param(
    [System.Collections.Generic.List[string]]$SectionLines,
    [string[]]$HeaderCandidates,
    [string]$HeaderText,
    [string[]]$BulletLines
  )

  if (-not $SectionLines -or -not $BulletLines -or $BulletLines.Count -eq 0) {
    return
  }

  $headerIndex = -1
  for ($i = 0; $i -lt $SectionLines.Count; $i++) {
    if ($HeaderCandidates -contains $SectionLines[$i].Trim()) {
      $headerIndex = $i
      break
    }
  }

  if ($headerIndex -lt 0) {
    if ($SectionLines.Count -gt 0 -and -not [string]::IsNullOrWhiteSpace($SectionLines[$SectionLines.Count - 1])) {
      [void]$SectionLines.Add("")
    }
    [void]$SectionLines.Add($HeaderText)
    $headerIndex = $SectionLines.Count - 1
  } else {
    $SectionLines[$headerIndex] = $HeaderText
  }

  $blockStart = $headerIndex + 1
  $blockEnd = $SectionLines.Count
  for ($i = $blockStart; $i -lt $SectionLines.Count; $i++) {
    $trimmed = $SectionLines[$i].Trim()
    if ($trimmed -match '^\*\*.+\*\*:?$' -or $trimmed -match '^###\s+' -or $trimmed -match '^##\s+') {
      $blockEnd = $i
      break
    }
  }

  if ($blockEnd -gt $blockStart) {
    $SectionLines.RemoveRange($blockStart, $blockEnd - $blockStart)
  }

  $renderedBullets = [System.Collections.Generic.List[string]]::new()
  foreach ($line in $BulletLines) {
    if (-not [string]::IsNullOrWhiteSpace($line)) {
      [void]$renderedBullets.Add($line)
    }
  }
  [void]$renderedBullets.Add("")

  if ($renderedBullets.Count -gt 0) {
    $SectionLines.InsertRange($blockStart, $renderedBullets)
  }
}

function Remove-SectionBlock {
  param(
    [System.Collections.Generic.List[string]]$SectionLines,
    [string[]]$HeaderCandidates
  )

  if (-not $SectionLines -or -not $HeaderCandidates -or $HeaderCandidates.Count -eq 0) {
    return
  }

  $headerIndex = -1
  for ($i = 0; $i -lt $SectionLines.Count; $i++) {
    if ($HeaderCandidates -contains $SectionLines[$i].Trim()) {
      $headerIndex = $i
      break
    }
  }

  if ($headerIndex -lt 0) {
    return
  }

  $blockEnd = $SectionLines.Count
  for ($i = $headerIndex + 1; $i -lt $SectionLines.Count; $i++) {
    $trimmed = $SectionLines[$i].Trim()
    if ($trimmed -match '^\*\*.+\*\*:?$' -or $trimmed -match '^###\s+' -or $trimmed -match '^##\s+') {
      $blockEnd = $i
      break
    }
  }

  if ($blockEnd -gt $headerIndex) {
    $SectionLines.RemoveRange($headerIndex, $blockEnd - $headerIndex)
  }
}

function Update-RoadmapCourseSection {
  param(
    [System.Collections.Generic.List[string]]$SectionLines,
    [string]$EntryDateText,
    [pscustomobject]$MappingSnapshot
  )

  if (-not $SectionLines) {
    return [System.Collections.Generic.List[string]]::new()
  }

  $hasStatusLine = $false
  for ($i = 0; $i -lt $SectionLines.Count; $i++) {
    if ($SectionLines[$i] -match '^\*\*Status:\*\*') {
      $hasStatusLine = $true
    }

    if ($SectionLines[$i] -match '^(\*\*Status:\*\*.*In Progress\s*\([A-Za-z]+\s+\d{1,2},\s+\d{4}\s*\-\s*)(\?|[A-Za-z]+\s+\d{1,2},\s+\d{4})(\).*)$') {
      $SectionLines[$i] = "$($matches[1])$EntryDateText$($matches[3])"
    }
  }

  if (-not $hasStatusLine) {
    Remove-SectionBlock -SectionLines $SectionLines -HeaderCandidates @("**Chapters:**")
    Remove-SectionBlock -SectionLines $SectionLines -HeaderCandidates @("**Security Connections:**", "**Planned Security Connections:**")
    return $SectionLines
  }

  if ($MappingSnapshot -and -not [string]::IsNullOrWhiteSpace($MappingSnapshot.MappingSummary)) {
    for ($i = 0; $i -lt $SectionLines.Count; $i++) {
      if ($SectionLines[$i] -match '^\*\*Security Mapping:\*\*') {
        $SectionLines[$i] = "**Security Mapping:** $($MappingSnapshot.MappingSummary)"
        break
      }
    }
  }

  if ($MappingSnapshot -and $MappingSnapshot.Chapters -and $MappingSnapshot.Chapters.Count -gt 0) {
    $chapterLines = @()
    foreach ($chapter in @($MappingSnapshot.Chapters | Sort-Object Number)) {
      $chapterLines += "- [x] $($chapter.Title)"
    }

    Set-CourseSectionBlock -SectionLines $SectionLines -HeaderCandidates @("**Chapters:**") -HeaderText "**Chapters:**" -BulletLines $chapterLines

    if ($MappingSnapshot.SecurityConnections -and $MappingSnapshot.SecurityConnections.Count -gt 0) {
      Set-CourseSectionBlock -SectionLines $SectionLines -HeaderCandidates @("**Security Connections:**", "**Planned Security Connections:**") -HeaderText "**Security Connections:**" -BulletLines $MappingSnapshot.SecurityConnections
    }
  }

  return $SectionLines
}

$progressLogs = @(
  (Join-Path $projectsRoot "bootdev-python-security\progress-log.md"),
  (Join-Path $projectsRoot "bootdev-security-journey\progress-log.md")
)

foreach ($progressLog in $progressLogs) {
  if (-not (Test-Path $progressLog)) {
    Write-Host "Skipping missing progress log: $progressLog"
    continue
  }

  $isJourneyLog = $progressLog -like "*bootdev-security-journey*"
  if ($isJourneyLog) {
    $entryDetailLines = @(
      "- **Boot.dev/GitHub Activity:** $StreakActivity",
      "- **Progress Sync:** $ChapterFocus",
      "- **Security Focus:** $SecurityConnection"
    )
  } else {
    $entryDetailLines = @(
      "- **Streak Activity:** $StreakActivity Boot.dev/GitHub $activityWord",
      "- **Chapter Focus:** $ChapterFocus",
      "- **Lesson Concepts Covered:** $LessonConceptsCovered",
      "- **Security Connection:** $SecurityConnection"
    )
  }

  $entryMarkdownLines = @($entryHeaderLine) + $entryDetailLines + @("")
  $entryMarkdownBlock = ($entryMarkdownLines -join [Environment]::NewLine)

  $legacyEntryLines = @(
    $entryDateText,
    "Streak Activity: $StreakActivity Boot.dev/GitHub $activityWord",
    "Chapter Focus: $ChapterFocus",
    "Lesson Concepts Covered: $LessonConceptsCovered",
    "Security Connection: $SecurityConnection"
  )

  $logLines = [System.Collections.Generic.List[string]](Get-Content -Path $progressLog -Encoding UTF8)
  $existingContent = ($logLines -join [Environment]::NewLine)
  if ($existingContent -like "*$entryMarkdownBlock*") {
    Write-Host "Progress entry already exists in: $progressLog"
    continue
  }

  $legacyIndex = -1
  for ($i = 0; $i -le ($logLines.Count - $legacyEntryLines.Count); $i++) {
    $isLegacyMatch = $true
    for ($j = 0; $j -lt $legacyEntryLines.Count; $j++) {
      if ($logLines[$i + $j].Trim() -ne $legacyEntryLines[$j]) {
        $isLegacyMatch = $false
        break
      }
    }

    if ($isLegacyMatch) {
      $legacyIndex = $i
      break
    }
  }

  if ($legacyIndex -ge 0) {
    $logLines.RemoveRange($legacyIndex, $legacyEntryLines.Count)
    if ($legacyIndex -lt $logLines.Count -and [string]::IsNullOrWhiteSpace($logLines[$legacyIndex])) {
      $logLines.RemoveAt($legacyIndex)
    }
  }

  $monthIndex = Find-LineIndex -Lines $logLines -Predicate { param($line) $line.Trim() -eq $entryMonthHeader }
  if ($monthIndex -lt 0) {
    if ($logLines.Count -gt 0 -and -not [string]::IsNullOrWhiteSpace($logLines[$logLines.Count - 1])) {
      $logLines.Add("")
    }
    $logLines.Add($entryMonthHeader)
    $logLines.Add("")
    $monthIndex = $logLines.Count - 2
  }

  $monthBodyStart = $monthIndex + 1
  if ($monthBodyStart -lt $logLines.Count -and [string]::IsNullOrWhiteSpace($logLines[$monthBodyStart])) {
    $monthBodyStart++
  }

  $monthEnd = $logLines.Count
  for ($i = $monthIndex + 1; $i -lt $logLines.Count; $i++) {
    if ($logLines[$i].Trim() -match '^##\s+') {
      $monthEnd = $i
      break
    }
  }

  $existingEntryIndex = -1
  for ($i = $monthBodyStart; $i -lt $monthEnd; $i++) {
    if ($logLines[$i].Trim() -eq $entryHeaderLine) {
      $existingEntryIndex = $i
      break
    }
  }

  if ($existingEntryIndex -ge 0) {
    $removeEnd = $existingEntryIndex + 1
    while ($removeEnd -lt $monthEnd -and $logLines[$removeEnd].Trim() -notmatch '^###\s+' -and $logLines[$removeEnd].Trim() -notmatch '^##\s+') {
      $removeEnd++
    }
    $logLines.RemoveRange($existingEntryIndex, $removeEnd - $existingEntryIndex)
    $insertIndex = $existingEntryIndex
  } else {
    $insertIndex = $monthBodyStart
  }

  $entryInsertLines = [System.Collections.Generic.List[string]]::new()
  foreach ($line in $entryMarkdownLines) {
    $entryInsertLines.Add($line)
  }

  $logLines.InsertRange($insertIndex, $entryInsertLines)
  Set-Content -Path $progressLog -Value $logLines -Encoding UTF8
  Write-Host "Upserted progress entry in: $progressLog"
}

$pythonProgressLogPath = Join-Path $projectsRoot "bootdev-python-security\progress-log.md"
$journeyProgressLogPath = Join-Path $projectsRoot "bootdev-security-journey\progress-log.md"
$pythonSnapshot = Get-ProgressSnapshot -ProgressLogPath $pythonProgressLogPath
$journeySnapshot = Get-ProgressSnapshot -ProgressLogPath $journeyProgressLogPath
$pythonActiveDaysText = Format-ActiveDaysList -Dates $pythonSnapshot.ActiveDates
$journeyActiveDaysText = Format-ActiveDaysList -Dates $journeySnapshot.ActiveDates
$rangeDash = [char]0x2013
$statusCheck = [char]0x2705
$rightArrow = [char]0x2192

if (Test-Path $pythonProgressLogPath) {
  $pythonProgressLines = [System.Collections.Generic.List[string]](Get-Content -Path $pythonProgressLogPath -Encoding UTF8)
  if ($pythonSnapshot.MaxChapter) {
    $courseSummaryIndex = Find-LineIndex -Lines $pythonProgressLines -Predicate { param($line) $line -match '^## Course Summary' }
    if ($courseSummaryIndex -ge 0) {
      if (-not [string]::IsNullOrWhiteSpace($pythonSnapshot.MaxChapterTitle)) {
        $pythonProgressLines[$courseSummaryIndex] = "## Course Summary (Through Chapter $($pythonSnapshot.MaxChapter) - $($pythonSnapshot.MaxChapterTitle))"
      } else {
        $pythonProgressLines[$courseSummaryIndex] = "## Course Summary (Through Chapter $($pythonSnapshot.MaxChapter))"
      }
    }

    $chaptersCompletedIndex = Find-LineIndex -Lines $pythonProgressLines -Predicate { param($line) $line -match '^- \*\*Chapters Completed:\*\*' }
    if ($chaptersCompletedIndex -ge 0) {
      if (-not [string]::IsNullOrWhiteSpace($pythonSnapshot.MaxChapterTitle)) {
        $pythonProgressLines[$chaptersCompletedIndex] = "- **Chapters Completed:** $($pythonSnapshot.MaxChapter)/$($pythonSnapshot.MaxChapter) (Introduction $rightArrow $($pythonSnapshot.MaxChapterTitle))"
      } else {
        $pythonProgressLines[$chaptersCompletedIndex] = "- **Chapters Completed:** $($pythonSnapshot.MaxChapter)/$($pythonSnapshot.MaxChapter)"
      }
    }
  }

  $activeDaysLoggedIndex = Find-LineIndex -Lines $pythonProgressLines -Predicate { param($line) $line -match '^- \*\*Active Days Logged:\*\*' }
  if ($activeDaysLoggedIndex -ge 0) {
    $pythonProgressLines[$activeDaysLoggedIndex] = "- **Active Days Logged:** $(@($pythonSnapshot.ActiveDates).Count) days"
  }

  $chapterBreakdownHeaderIndex = Find-LineIndex -Lines $pythonProgressLines -Predicate { param($line) $line -match '^### Chapter Breakdown' }
  if ($chapterBreakdownHeaderIndex -ge 0 -and $pythonSnapshot.ChapterRecords.Count -gt 0) {
    $tableHeaderIndex = Find-LineIndex -Lines $pythonProgressLines -Predicate { param($line) $line.Trim() -match '^\|\s*Chapter\s*\|\s*Topic\s*\|\s*Completion Window\s*\|\s*Security Mapping\s*\|' } -StartIndex ($chapterBreakdownHeaderIndex + 1)
    if ($tableHeaderIndex -ge 0) {
      $separatorIndex = Find-LineIndex -Lines $pythonProgressLines -Predicate { param($line) $line.Trim() -match '^\|[-\s|]+\|$' } -StartIndex ($tableHeaderIndex + 1)
      if ($separatorIndex -ge 0) {
        $tableEnd = $pythonProgressLines.Count
        for ($i = $separatorIndex + 1; $i -lt $pythonProgressLines.Count; $i++) {
          $trimmed = $pythonProgressLines[$i].Trim()
          if ([string]::IsNullOrWhiteSpace($trimmed) -or $trimmed -notmatch '^\|') {
            $tableEnd = $i
            break
          }
        }

        $existingBreakdown = @{}
        for ($i = $separatorIndex + 1; $i -lt $tableEnd; $i++) {
          if ($pythonProgressLines[$i] -match '^\|\s*(\d+)\s*\|\s*([^|]+?)\s*\|\s*([^|]+?)\s*\|\s*([^|]+?)\s*\|') {
            $existingBreakdown[[int]$matches[1]] = [pscustomobject]@{
              Topic = $matches[2].Trim()
              Security = $matches[4].Trim()
            }
          }
        }

        $chapterGroups = @($pythonSnapshot.ChapterRecords | Group-Object Chapter | Sort-Object { [int]$_.Name })
        $newRows = [System.Collections.Generic.List[string]]::new()
        foreach ($chapterGroup in $chapterGroups) {
          $chapterNumber = [int]$chapterGroup.Name
          $records = @($chapterGroup.Group | Sort-Object Date)
          $topic = "Chapter $chapterNumber"
          $latestTitle = @($records | Where-Object { -not [string]::IsNullOrWhiteSpace($_.Title) } | Select-Object -Last 1)
          if ($latestTitle.Count -gt 0) {
            $topic = $latestTitle[0].Title
          } elseif ($existingBreakdown.ContainsKey($chapterNumber) -and -not [string]::IsNullOrWhiteSpace($existingBreakdown[$chapterNumber].Topic)) {
            $topic = $existingBreakdown[$chapterNumber].Topic
          }

          $completionWindow = Get-CompletionWindowText -Dates @($records | Select-Object -ExpandProperty Date)
          $securityText = if ($existingBreakdown.ContainsKey($chapterNumber) -and -not [string]::IsNullOrWhiteSpace($existingBreakdown[$chapterNumber].Security)) {
            $existingBreakdown[$chapterNumber].Security
          } elseif ($chapterBreakdownSecurityDefaults.ContainsKey($chapterNumber)) {
            $chapterBreakdownSecurityDefaults[$chapterNumber]
          } else {
            "OWASP mapping in progress"
          }

          if ($chapterNumberFromInput -and $chapterNumber -eq $chapterNumberFromInput -and -not [string]::IsNullOrWhiteSpace($SecurityConnection)) {
            if ($SecurityConnection -match '(?i)owasp') {
              $securityText = $SecurityConnection
            } else {
              $securityText = "OWASP $SecurityConnection"
            }
          }

          [void]$newRows.Add("| $chapterNumber | $topic | $completionWindow | $securityText |")
        }

        if ($tableEnd -gt ($separatorIndex + 1)) {
          $pythonProgressLines.RemoveRange($separatorIndex + 1, $tableEnd - ($separatorIndex + 1))
        }

        if ($newRows.Count -gt 0) {
          $pythonProgressLines.InsertRange($separatorIndex + 1, $newRows)
        }
      }
    }
  }

  Set-Content -Path $pythonProgressLogPath -Value $pythonProgressLines -Encoding UTF8
}

if (Test-Path $journeyProgressLogPath) {
  $journeyProgressLines = [System.Collections.Generic.List[string]](Get-Content -Path $journeyProgressLogPath -Encoding UTF8)
  if ($journeySnapshot.MaxChapter) {
    $journeyCourseIndex = Find-LineIndex -Lines $journeyProgressLines -Predicate { param($line) $line -match '^- \*\*Learn to Code in Python:\*\*' }
    if ($journeyCourseIndex -ge 0) {
      $journeyProgressLines[$journeyCourseIndex] = "- **Learn to Code in Python:** Chapters 1$rangeDash$($journeySnapshot.MaxChapter) completed and synced to GitHub docs"
    }
  }

  $journeyActiveIndex = Find-LineIndex -Lines $journeyProgressLines -Predicate { param($line) $line -match '^- \*\*Active days represented:\*\*' }
  if ($journeyActiveIndex -ge 0 -and -not [string]::IsNullOrWhiteSpace($journeyActiveDaysText)) {
    $journeyProgressLines[$journeyActiveIndex] = "- **Active days represented:** $journeyActiveDaysText"
  }

  $journeySecurityHeaderIndex = Find-LineIndex -Lines $journeyProgressLines -Predicate { param($line) $line -match '^### Security Mapping Progress' }
  if ($journeySecurityHeaderIndex -ge 0 -and $pythonSnapshot.ChapterRecords.Count -gt 0) {
    $journeySecurityEnd = $journeyProgressLines.Count
    for ($i = $journeySecurityHeaderIndex + 1; $i -lt $journeyProgressLines.Count; $i++) {
      if ($journeyProgressLines[$i] -match '^###\s+' -or $journeyProgressLines[$i] -match '^##\s+') {
        $journeySecurityEnd = $i
        break
      }
    }

    $securityLines = [System.Collections.Generic.List[string]]::new()
    [void]$securityLines.Add("### Security Mapping Progress")
    $journeyChapterGroups = @($pythonSnapshot.ChapterRecords | Group-Object Chapter | Sort-Object { [int]$_.Name })
    foreach ($chapterGroup in $journeyChapterGroups) {
      $chapterNumber = [int]$chapterGroup.Name
      $records = @($chapterGroup.Group | Sort-Object Date)
      $chapterLabel = "Chapter $chapterNumber"
      $latestTitle = @($records | Where-Object { -not [string]::IsNullOrWhiteSpace($_.Title) } | Select-Object -Last 1)
      if ($latestTitle.Count -gt 0) {
        $chapterLabel = $latestTitle[0].Title
      }

      $owaspSource = if ($chapterNumberFromInput -and $chapterNumber -eq $chapterNumberFromInput) {
        "$SecurityConnection $Security"
      } elseif ($chapterSecurityDefaults.ContainsKey($chapterNumber)) {
        $chapterSecurityDefaults[$chapterNumber]
      } else {
        ""
      }

      $owaspCodes = @(Get-OwaspCodesFromText -Text $owaspSource)
      $owaspText = if ($owaspCodes.Count -gt 0) { "OWASP " + ($owaspCodes -join '/') } else { "OWASP mapping in progress" }
      [void]$securityLines.Add("- CH$chapterNumber $chapterLabel $rightArrow $owaspText")
    }
    [void]$securityLines.Add("")

    $journeyProgressLines.RemoveRange($journeySecurityHeaderIndex, $journeySecurityEnd - $journeySecurityHeaderIndex)
    $journeyProgressLines.InsertRange($journeySecurityHeaderIndex, $securityLines)
  }

  Set-Content -Path $journeyProgressLogPath -Value $journeyProgressLines -Encoding UTF8
}

$statusChapter = if (-not [string]::IsNullOrWhiteSpace($Chapter) -and $Chapter -match '^\d+$') { [int]$Chapter } else { $pythonSnapshot.MaxChapter }
$statusChapterTitle = if (-not [string]::IsNullOrWhiteSpace($ChapterTitle)) { $ChapterTitle } else { $pythonSnapshot.MaxChapterTitle }

$pythonRepo = Join-Path $projectsRoot "bootdev-python-security"
$readmePath = Join-Path $pythonRepo "README.md"
$chaptersPath = Join-Path $pythonRepo "chapters"
$notesPath = Join-Path $pythonRepo "notes"

if (Test-Path $readmePath) {
  $readmeLines = [System.Collections.Generic.List[string]](Get-Content -Path $readmePath -Encoding UTF8)
  $treePipe = [char]0x2502
  $treeBranch = [char]0x251C
  $treeEnd = [char]0x2514
  $treeDash = [char]0x2500
  $branchToken = "$treeBranch$treeDash$treeDash"
  $endToken = "$treeEnd$treeDash$treeDash"
  $pipeToken = "$treePipe"
  $treeLinePattern = '^' + [regex]::Escape($pipeToken) + '\s+(' + [regex]::Escape($treeBranch) + '|' + [regex]::Escape($treeEnd) + ')' + [regex]::Escape("$treeDash$treeDash")
  $noteLinePattern = '^\s{4}(' + [regex]::Escape($treeBranch) + '|' + [regex]::Escape($treeEnd) + ')' + [regex]::Escape("$treeDash$treeDash") + '\s+(.*)'

  $statusIndex = Find-LineIndex -Lines $readmeLines -Predicate { param($line) $line -match "^\- \*\*Status:\*\*" }
  if ($statusIndex -ge 0 -and $statusChapter) {
    if (-not [string]::IsNullOrWhiteSpace($statusChapterTitle)) {
      $readmeLines[$statusIndex] = "- **Status:** $statusCheck Completed through **Chapter $statusChapter ($statusChapterTitle)**"
    } else {
      $readmeLines[$statusIndex] = "- **Status:** $statusCheck Completed through **Chapter $statusChapter**"
    }
  }

  $activeIndex = Find-LineIndex -Lines $readmeLines -Predicate { param($line) $line -match "^\- \*\*Active Days Synced:\*\*" }
  if ($activeIndex -ge 0 -and -not [string]::IsNullOrWhiteSpace($pythonActiveDaysText)) {
    $readmeLines[$activeIndex] = "- **Active Days Synced:** $pythonActiveDaysText"
  }

  $repoHeaderIndex = Find-LineIndex -Lines $readmeLines -Predicate { param($line) $line -eq "## Repository Structure" }
  if ($repoHeaderIndex -ge 0) {
    $blockStart = Find-LineIndex -Lines $readmeLines -Predicate { param($line) $line -match '^```text' } -StartIndex $repoHeaderIndex
    if ($blockStart -ge 0) {
      $blockEnd = Find-LineIndex -Lines $readmeLines -Predicate { param($line) $line -match '^```' } -StartIndex ($blockStart + 1)
      if ($blockEnd -gt $blockStart) {
        $blockLines = [System.Collections.Generic.List[string]]($readmeLines.GetRange($blockStart + 1, $blockEnd - $blockStart - 1))

        if (Test-Path $chaptersPath) {
          $chapterDirs = Get-ChildItem -Path $chaptersPath -Directory | Sort-Object Name | Select-Object -ExpandProperty Name
          if (-not [string]::IsNullOrWhiteSpace($ChapterFolder) -and ($chapterDirs -notcontains $ChapterFolder)) {
            $chapterDirs += $ChapterFolder
            $chapterDirs = $chapterDirs | Sort-Object
          }

          if ($chapterDirs.Count -gt 0) {
            $chaptersHeaderIndex = Find-LineIndex -Lines $blockLines -Predicate { param($line) $line -eq "$branchToken chapters/" }
            if ($chaptersHeaderIndex -ge 0) {
              $removeCount = 0
              for ($i = $chaptersHeaderIndex + 1; $i -lt $blockLines.Count; $i++) {
                if ($blockLines[$i] -match $treeLinePattern) {
                  $removeCount++
                } else {
                  break
                }
              }

              if ($removeCount -gt 0) {
                $blockLines.RemoveRange($chaptersHeaderIndex + 1, $removeCount)
              }

              for ($i = 0; $i -lt $chapterDirs.Count; $i++) {
                $prefix = if ($i -eq $chapterDirs.Count - 1) { "$pipeToken   $endToken" } else { "$pipeToken   $branchToken" }
                $blockLines.Insert($chaptersHeaderIndex + 1 + $i, "$prefix $($chapterDirs[$i])/" )
              }
            }
          }
        }

        if (Test-Path $notesPath) {
          $noteFiles = Get-ChildItem -Path $notesPath -File | Sort-Object Name | Select-Object -ExpandProperty Name
          $notesHeaderIndex = Find-LineIndex -Lines $blockLines -Predicate { param($line) $line -match "notes/" }
          if ($notesHeaderIndex -ge 0) {
            $noteLineIndices = @()
            $existingNoteNames = @()
            for ($i = $notesHeaderIndex + 1; $i -lt $blockLines.Count; $i++) {
              if ($blockLines[$i] -match $noteLinePattern) {
                $noteLineIndices += $i
                $existingNoteNames += $matches[2]
              } elseif ($blockLines[$i] -notmatch "^\s{4}") {
                break
              }
            }

            $newNotes = $noteFiles | Where-Object { $_ -notin $existingNoteNames }
            if ($newNotes.Count -gt 0) {
              if ($noteLineIndices.Count -gt 0) {
                $lastNoteIndex = $noteLineIndices[-1]
                $blockLines[$lastNoteIndex] = $blockLines[$lastNoteIndex] -replace [regex]::Escape($endToken), $branchToken
                $insertIndex = $lastNoteIndex + 1
              } else {
                $insertIndex = $notesHeaderIndex + 1
              }

              for ($n = 0; $n -lt $newNotes.Count; $n++) {
                $prefix = if ($n -eq $newNotes.Count - 1) { "    $endToken" } else { "    $branchToken" }
                $blockLines.Insert($insertIndex + $n, "$prefix $($newNotes[$n])")
              }
            }
          }
        }

        $readmeLines.RemoveRange($blockStart + 1, $blockEnd - $blockStart - 1)
        $readmeLines.InsertRange($blockStart + 1, $blockLines)
      }
    }
  }

  $trackHeaderIndex = Find-LineIndex -Lines $readmeLines -Predicate { param($line) $line -match '^## Chapter Track' }
  if ($trackHeaderIndex -ge 0 -and $statusChapter) {
    $readmeLines[$trackHeaderIndex] = "## Chapter Track (1$rangeDash$statusChapter)"
  }

  if (-not [string]::IsNullOrWhiteSpace($statusChapterTitle) -and $hasSpecificLearningPayload) {
    $trackHeaderIndex = Find-LineIndex -Lines $readmeLines -Predicate { param($line) $line -match "^## Chapter Track" }
    if ($trackHeaderIndex -ge 0) {
      $trackLineIndices = @()
      for ($i = $trackHeaderIndex + 1; $i -lt $readmeLines.Count; $i++) {
        if ($readmeLines[$i] -match "^\d+\.\s+\*\*") {
          $trackLineIndices += $i
        } elseif ($readmeLines[$i] -match "^##\s+") {
          break
        }
      }

      $chapterDetail = Get-ChapterTrackDetail -Summary $ChapterSummary -ConceptItems $lessonItems -FallbackConcept $Concept
      $newTrackLine = "$statusChapter. **$statusChapterTitle** $rangeDash $chapterDetail"
      $targetTrackIndex = -1
      foreach ($trackLineIndex in $trackLineIndices) {
        if ($readmeLines[$trackLineIndex] -match "^$statusChapter\.\s+\*\*") {
          $targetTrackIndex = $trackLineIndex
          break
        }
      }

      if ($targetTrackIndex -ge 0) {
        $readmeLines[$targetTrackIndex] = $newTrackLine
      } else {
        $insertTrackIndex = if ($trackLineIndices.Count -gt 0) { $trackLineIndices[-1] + 1 } else { $trackHeaderIndex + 1 }
        $readmeLines.Insert($insertTrackIndex, $newTrackLine)
      }
    }
  }

  Set-Content -Path $readmePath -Value $readmeLines -Encoding UTF8
  Write-Host "Updated README activity sections: $readmePath"
}

$securityMappingPath = Join-Path $pythonRepo "security-mapping.md"
if ((Test-Path $securityMappingPath) -and $statusChapter -and -not [string]::IsNullOrWhiteSpace($statusChapterTitle) -and $hasSpecificLearningPayload) {
  $securityLines = [System.Collections.Generic.List[string]](Get-Content -Path $securityMappingPath -Encoding UTF8)
  $mappingTitleIndex = Find-LineIndex -Lines $securityLines -Predicate { param($line) $line -match '^# Python to OWASP Security Mapping \(Chapters \d+\-\d+\)' }
  if ($mappingTitleIndex -ge 0) {
    $securityLines[$mappingTitleIndex] = "# Python to OWASP Security Mapping (Chapters 1-$statusChapter)"
  }

  $owaspSectionLabel = if (-not [string]::IsNullOrWhiteSpace($SecurityConnection) -and $SecurityConnection -match '(?i)owasp') {
    $SecurityConnection
  } elseif (-not [string]::IsNullOrWhiteSpace($SecurityConnection)) {
    "OWASP $SecurityConnection"
  } elseif ($chapterSecurityDefaults.ContainsKey($statusChapter)) {
    $chapterSecurityDefaults[$statusChapter]
  } else {
    "OWASP mapping in progress"
  }

  $mappingSectionHeader = "### Chapter ${statusChapter}: $statusChapterTitle"
  $mappingSectionStart = Find-LineIndex -Lines $securityLines -Predicate { param($line) $line.Trim() -eq $mappingSectionHeader }
  if ($mappingSectionStart -lt 0) {
    $mappingSectionStart = Find-LineIndex -Lines $securityLines -Predicate { param($line) $line -match "^### Chapter\s+$statusChapter\s*:" }
  }

  $mappingInsertAt = Find-LineIndex -Lines $securityLines -Predicate { param($line) $line -match '^## Quick OWASP Coverage Matrix' }
  if ($mappingInsertAt -lt 0) {
    $mappingInsertAt = $securityLines.Count
  }

  if ($mappingSectionStart -ge 0) {
    $mappingSectionEnd = $securityLines.Count
    for ($i = $mappingSectionStart + 1; $i -lt $securityLines.Count; $i++) {
      if ($securityLines[$i] -match '^###\s+Chapter' -or $securityLines[$i] -match '^##\s+Quick OWASP Coverage Matrix') {
        $mappingSectionEnd = $i
        break
      }
    }
    $securityLines.RemoveRange($mappingSectionStart, $mappingSectionEnd - $mappingSectionStart)
    $mappingInsertAt = $mappingSectionStart
  }

  $mappingSectionLines = [System.Collections.Generic.List[string]]::new()
  [void]$mappingSectionLines.Add($mappingSectionHeader)
  [void]$mappingSectionLines.Add("")
  [void]$mappingSectionLines.Add("**Core Concepts**")
  $mappingConceptItems = @($lessonItems | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -First 8)
  if ($mappingConceptItems.Count -eq 0 -and -not [string]::IsNullOrWhiteSpace($Concept)) {
    $mappingConceptItems = @($Concept -split ',' | ForEach-Object { $_.Trim() } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -First 8)
  }
  if ($mappingConceptItems.Count -eq 0) {
    $mappingConceptItems = @("Chapter concept coverage in progress")
  }
  foreach ($conceptItem in $mappingConceptItems) {
    [void]$mappingSectionLines.Add("- $conceptItem")
  }
  [void]$mappingSectionLines.Add("")
  [void]$mappingSectionLines.Add("**OWASP Connection**")
  [void]$mappingSectionLines.Add("- **$owaspSectionLabel**")
  [void]$mappingSectionLines.Add("- Connection: chapter concepts are mapped to this OWASP area for practical secure coding behavior.")
  [void]$mappingSectionLines.Add("")
  [void]$mappingSectionLines.Add("**Portfolio Application**")
  [void]$mappingSectionLines.Add("- Apply Chapter $statusChapter concepts in secure coding exercises and repo artifacts.")
  [void]$mappingSectionLines.Add("- Keep chapter mappings synchronized with logs, notes, and roadmap updates.")
  [void]$mappingSectionLines.Add("")

  $securityLines.InsertRange($mappingInsertAt, $mappingSectionLines)

  $matrixHeaderIndex = Find-LineIndex -Lines $securityLines -Predicate { param($line) $line.Trim() -eq '| Chapter | OWASP Focus |' }
  if ($matrixHeaderIndex -ge 0) {
    $matrixSeparatorIndex = Find-LineIndex -Lines $securityLines -Predicate { param($line) $line.Trim() -match '^\|[-\s|]+\|$' } -StartIndex ($matrixHeaderIndex + 1)
    if ($matrixSeparatorIndex -ge 0) {
      $matrixEnd = $securityLines.Count
      for ($i = $matrixSeparatorIndex + 1; $i -lt $securityLines.Count; $i++) {
        $trimmed = $securityLines[$i].Trim()
        if ([string]::IsNullOrWhiteSpace($trimmed) -or $trimmed -notmatch '^\|') {
          $matrixEnd = $i
          break
        }
      }

      $matrixRows = @()
      for ($i = $matrixSeparatorIndex + 1; $i -lt $matrixEnd; $i++) {
        if ($securityLines[$i] -match '^\|\s*(\d+)\s+([^|]+?)\s*\|\s*([^|]+?)\s*\|') {
          $matrixRows += [pscustomobject]@{
            Chapter = [int]$matches[1]
            Topic = $matches[2].Trim()
            Focus = $matches[3].Trim()
          }
        }
      }

      $currentMatrixCodes = @(Get-OwaspCodesFromText -Text "$SecurityConnection $Security")
      if ($currentMatrixCodes.Count -eq 0 -and $chapterSecurityDefaults.ContainsKey($statusChapter)) {
        $currentMatrixCodes = @(Get-OwaspCodesFromText -Text $chapterSecurityDefaults[$statusChapter])
      }
      $currentMatrixFocus = if ($currentMatrixCodes.Count -gt 0) { $currentMatrixCodes -join ', ' } else { "TBD" }

      $updatedRows = @()
      $rowUpdated = $false
      foreach ($row in $matrixRows) {
        if ($row.Chapter -eq $statusChapter) {
          $updatedRows += [pscustomobject]@{ Chapter = $statusChapter; Topic = $statusChapterTitle; Focus = $currentMatrixFocus }
          $rowUpdated = $true
        } else {
          $updatedRows += $row
        }
      }
      if (-not $rowUpdated) {
        $updatedRows += [pscustomobject]@{ Chapter = $statusChapter; Topic = $statusChapterTitle; Focus = $currentMatrixFocus }
      }

      $updatedRows = @($updatedRows | Sort-Object Chapter)
      $renderedRows = [System.Collections.Generic.List[string]]::new()
      foreach ($row in $updatedRows) {
        [void]$renderedRows.Add("| $($row.Chapter) $($row.Topic) | $($row.Focus) |")
      }

      if ($matrixEnd -gt ($matrixSeparatorIndex + 1)) {
        $securityLines.RemoveRange($matrixSeparatorIndex + 1, $matrixEnd - ($matrixSeparatorIndex + 1))
      }
      if ($renderedRows.Count -gt 0) {
        $securityLines.InsertRange($matrixSeparatorIndex + 1, $renderedRows)
      }
    }
  }

  Set-Content -Path $securityMappingPath -Value $securityLines -Encoding UTF8
  Write-Host "Updated security mapping sections: $securityMappingPath"
}

$pythonSecurityNotesPath = Join-Path $notesPath "python-security-notes.md"
if ((Test-Path $pythonSecurityNotesPath) -and $statusChapter -and -not [string]::IsNullOrWhiteSpace($statusChapterTitle) -and $hasSpecificLearningPayload) {
  $pythonSecurityNotesLines = [System.Collections.Generic.List[string]](Get-Content -Path $pythonSecurityNotesPath -Encoding UTF8)
  $notesTitleIndex = Find-LineIndex -Lines $pythonSecurityNotesLines -Predicate { param($line) $line -match '^# Python Security Notes \(Chapters \d+\-\d+\)' }
  if ($notesTitleIndex -ge 0) {
    $pythonSecurityNotesLines[$notesTitleIndex] = "# Python Security Notes (Chapters 1-$statusChapter)"
  }

  $chapterNotesHeader = "## Chapter ${statusChapter}: $statusChapterTitle"
  $chapterNotesStart = Find-LineIndex -Lines $pythonSecurityNotesLines -Predicate { param($line) $line.Trim() -eq $chapterNotesHeader }
  if ($chapterNotesStart -lt 0) {
    $chapterNotesStart = Find-LineIndex -Lines $pythonSecurityNotesLines -Predicate { param($line) $line -match "^## Chapter\s+$statusChapter\s*:" }
  }

  $crosswalkHeaderIndex = Find-LineIndex -Lines $pythonSecurityNotesLines -Predicate { param($line) $line -match '^## OWASP Crosswalk \(Quick\)' }
  if ($crosswalkHeaderIndex -lt 0) {
    $crosswalkHeaderIndex = $pythonSecurityNotesLines.Count
  }

  if ($chapterNotesStart -ge 0) {
    $chapterNotesEnd = $pythonSecurityNotesLines.Count
    for ($i = $chapterNotesStart + 1; $i -lt $pythonSecurityNotesLines.Count; $i++) {
      if ($pythonSecurityNotesLines[$i] -match '^##\s+Chapter\s+' -or $pythonSecurityNotesLines[$i] -match '^##\s+OWASP Crosswalk \(Quick\)') {
        $chapterNotesEnd = $i
        break
      }
    }
    $pythonSecurityNotesLines.RemoveRange($chapterNotesStart, $chapterNotesEnd - $chapterNotesStart)
    $crosswalkHeaderIndex = $chapterNotesStart
  }

  $chapterConceptsText = Get-ChapterTrackDetail -Summary $ChapterSummary -ConceptItems $lessonItems -FallbackConcept $Concept
  $chapterSecurityUseText = if (-not [string]::IsNullOrWhiteSpace($SecurityConnection)) {
    "practical chapter application aligned to $SecurityConnection."
  } else {
    "practical chapter application aligned to secure coding outcomes."
  }

  $chapterNotesLines = [System.Collections.Generic.List[string]]::new()
  [void]$chapterNotesLines.Add($chapterNotesHeader)
  [void]$chapterNotesLines.Add("")
  [void]$chapterNotesLines.Add("**Concepts:** $chapterConceptsText.")
  [void]$chapterNotesLines.Add("")
  [void]$chapterNotesLines.Add("**Security use:** $chapterSecurityUseText")
  [void]$chapterNotesLines.Add("")

  $pythonSecurityNotesLines.InsertRange($crosswalkHeaderIndex, $chapterNotesLines)

  $crosswalkHeaderIndex = Find-LineIndex -Lines $pythonSecurityNotesLines -Predicate { param($line) $line -match '^## OWASP Crosswalk \(Quick\)' }
  if ($crosswalkHeaderIndex -ge 0) {
    $crosswalkEnd = $pythonSecurityNotesLines.Count
    for ($i = $crosswalkHeaderIndex + 1; $i -lt $pythonSecurityNotesLines.Count; $i++) {
      if ($pythonSecurityNotesLines[$i] -match '^##\s+') {
        $crosswalkEnd = $i
        break
      }
    }

    $crosswalkCodes = @(Get-OwaspCodesFromText -Text "$SecurityConnection $Security")
    if ($crosswalkCodes.Count -eq 0 -and $chapterSecurityDefaults.ContainsKey($statusChapter)) {
      $crosswalkCodes = @(Get-OwaspCodesFromText -Text $chapterSecurityDefaults[$statusChapter])
    }
    $currentCrosswalkFocus = if ($crosswalkCodes.Count -gt 0) { $crosswalkCodes -join '/' } else { "TBD" }

    $crosswalkMap = @{}
    for ($i = $crosswalkHeaderIndex + 1; $i -lt $crosswalkEnd; $i++) {
      if ($pythonSecurityNotesLines[$i] -match '^\-\s*CH(\d+)\s+\S+\s+(.+)$') {
        $crosswalkMap[[int]$matches[1]] = $matches[2].Trim()
      }
    }
    $crosswalkMap[$statusChapter] = $currentCrosswalkFocus

    $rewriteStart = $crosswalkHeaderIndex + 1
    while ($rewriteStart -lt $crosswalkEnd -and [string]::IsNullOrWhiteSpace($pythonSecurityNotesLines[$rewriteStart])) {
      $rewriteStart++
    }

    if ($crosswalkEnd -gt $rewriteStart) {
      $pythonSecurityNotesLines.RemoveRange($rewriteStart, $crosswalkEnd - $rewriteStart)
    }

    $renderedCrosswalk = [System.Collections.Generic.List[string]]::new()
    foreach ($chapterNumber in @($crosswalkMap.Keys | Sort-Object)) {
      [void]$renderedCrosswalk.Add("- CH$chapterNumber $rightArrow $($crosswalkMap[$chapterNumber])")
    }
    [void]$renderedCrosswalk.Add("")

    if ($renderedCrosswalk.Count -gt 0) {
      $pythonSecurityNotesLines.InsertRange($rewriteStart, $renderedCrosswalk)
    }
  }

  Set-Content -Path $pythonSecurityNotesPath -Value $pythonSecurityNotesLines -Encoding UTF8
  Write-Host "Updated notes file: $pythonSecurityNotesPath"
}

$debuggingNotesPath = Join-Path $notesPath "debugging-notes.md"
if (Test-Path $debuggingNotesPath) {
  $debuggingNotesLines = [System.Collections.Generic.List[string]](Get-Content -Path $debuggingNotesPath -Encoding UTF8)
  $latestSyncHeader = "## Latest Learning Sync"
  $latestSyncStart = Find-LineIndex -Lines $debuggingNotesLines -Predicate { param($line) $line.Trim() -eq $latestSyncHeader }
  if ($latestSyncStart -ge 0) {
    $latestSyncEnd = $debuggingNotesLines.Count
    for ($i = $latestSyncStart + 1; $i -lt $debuggingNotesLines.Count; $i++) {
      if ($debuggingNotesLines[$i] -match '^##\s+') {
        $latestSyncEnd = $i
        break
      }
    }
    $debuggingNotesLines.RemoveRange($latestSyncStart, $latestSyncEnd - $latestSyncStart)
  } else {
    if ($debuggingNotesLines.Count -gt 0 -and -not [string]::IsNullOrWhiteSpace($debuggingNotesLines[$debuggingNotesLines.Count - 1])) {
      [void]$debuggingNotesLines.Add("")
    }
    $latestSyncStart = $debuggingNotesLines.Count
  }

  $latestSyncLines = [System.Collections.Generic.List[string]]::new()
  [void]$latestSyncLines.Add($latestSyncHeader)
  [void]$latestSyncLines.Add("")
  [void]$latestSyncLines.Add("- **Date:** $entryDateText")
  if (-not [string]::IsNullOrWhiteSpace($ChapterFocus)) {
    [void]$latestSyncLines.Add("- **Chapter focus:** $ChapterFocus")
  }
  if (-not [string]::IsNullOrWhiteSpace($SecurityConnection)) {
    [void]$latestSyncLines.Add("- **Security mapping:** $SecurityConnection")
  }
  [void]$latestSyncLines.Add("")

  $debuggingNotesLines.InsertRange($latestSyncStart, $latestSyncLines)
  Set-Content -Path $debuggingNotesPath -Value $debuggingNotesLines -Encoding UTF8
  Write-Host "Updated notes file: $debuggingNotesPath"
}

$journeyReadmePath = Join-Path $projectsRoot "bootdev-security-journey\README.md"
if (Test-Path $journeyReadmePath) {
  $journeyLines = [System.Collections.Generic.List[string]](Get-Content -Path $journeyReadmePath -Encoding UTF8)
  $timelineIndex = Find-LineIndex -Lines $journeyLines -Predicate { param($line) $line -eq "## Progress Timeline" }
  if ($timelineIndex -ge 0) {
    $sectionEnd = $journeyLines.Count
    for ($i = $timelineIndex + 1; $i -lt $journeyLines.Count; $i++) {
      if ($journeyLines[$i] -match '^##\s+') {
        $sectionEnd = $i
        break
      }
    }

    $latestLine = "- **Latest activity:** $entryDateText"
    if (-not [string]::IsNullOrWhiteSpace($ChapterFocus)) {
      $latestLine = "$latestLine ($ChapterFocus)"
    }

    $latestIndex = -1
    $lastBulletIndex = -1
    for ($i = $timelineIndex + 1; $i -lt $sectionEnd; $i++) {
      if ($journeyLines[$i] -match '^\- \*\*Latest activity:\*\*') {
        $latestIndex = $i
      }
      if ($journeyLines[$i] -match '^\- \*\*') {
        $lastBulletIndex = $i
      }
    }

    if ($latestIndex -ge 0) {
      $journeyLines[$latestIndex] = $latestLine
    } else {
      $insertIndex = if ($lastBulletIndex -ge 0) { $lastBulletIndex + 1 } else { $timelineIndex + 1 }
      $journeyLines.Insert($insertIndex, $latestLine)
    }
  }

  Set-Content -Path $journeyReadmePath -Value $journeyLines -Encoding UTF8
  Write-Host "Updated README activity sections: $journeyReadmePath"
}

$journeyRoadmapPath = Join-Path $projectsRoot "bootdev-security-journey\roadmap.md"
if (Test-Path $journeyRoadmapPath) {
  $journeyRoadmapLines = [System.Collections.Generic.List[string]](Get-Content -Path $journeyRoadmapPath -Encoding UTF8)
  $courseRepoInventory = @(Get-CourseRepoInventory -ProjectsRoot $projectsRoot)
  $mappingSnapshotCache = @{}

  $index = 0
  while ($index -lt $journeyRoadmapLines.Count) {
    if ($journeyRoadmapLines[$index] -match '^###\s+(.+)$') {
      $courseHeading = $matches[1].Trim()
      $sectionStart = $index
      $sectionEnd = $journeyRoadmapLines.Count
      for ($j = $sectionStart + 1; $j -lt $journeyRoadmapLines.Count; $j++) {
        if ($journeyRoadmapLines[$j] -match '^###\s+' -or $journeyRoadmapLines[$j] -match '^##\s+') {
          $sectionEnd = $j
          break
        }
      }

      $sectionLines = [System.Collections.Generic.List[string]]::new()
      for ($j = $sectionStart; $j -lt $sectionEnd; $j++) {
        [void]$sectionLines.Add($journeyRoadmapLines[$j])
      }

      $courseRepoPath = Resolve-CourseRepoPath -CourseHeading $courseHeading -ProjectsRoot $projectsRoot -RepoInventory $courseRepoInventory -SectionLines $sectionLines
      $mappingSnapshot = $null
      if (-not [string]::IsNullOrWhiteSpace($courseRepoPath)) {
        if (-not $mappingSnapshotCache.ContainsKey($courseRepoPath)) {
          $mappingSnapshotCache[$courseRepoPath] = Get-CourseSecurityMappingSnapshot -MappingPath (Join-Path $courseRepoPath 'security-mapping.md')
        }
        $mappingSnapshot = $mappingSnapshotCache[$courseRepoPath]
      }

      $updatedSectionLines = Update-RoadmapCourseSection -SectionLines $sectionLines -EntryDateText $entryDateText -MappingSnapshot $mappingSnapshot
      $journeyRoadmapLines.RemoveRange($sectionStart, $sectionEnd - $sectionStart)
      if ($updatedSectionLines.Count -gt 0) {
        for ($k = 0; $k -lt $updatedSectionLines.Count; $k++) {
          $journeyRoadmapLines.Insert($sectionStart + $k, [string]$updatedSectionLines[$k])
        }
      }

      $index = $sectionStart + $updatedSectionLines.Count
      continue
    }

    $index++
  }

  Set-Content -Path $journeyRoadmapPath -Value $journeyRoadmapLines -Encoding UTF8
  Write-Host "Updated roadmap status dates: $journeyRoadmapPath"
}

powershell -ExecutionPolicy Bypass -File $syncScript -Message $Message
