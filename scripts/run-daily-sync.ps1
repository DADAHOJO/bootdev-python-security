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
    $ChapterFolder = "$Chapter-$slug"
  }
}

if ([string]::IsNullOrWhiteSpace($Security) -or $Security -eq "OWASP mapping update") {
  $Security = $defaultOwasp
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

$activityWord = if ($StreakActivity -eq 1) { "activity" } else { "activities" }
$entryDateText = $EntryDate.ToString("MMMM d, yyyy")
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
    $daysText = ($groupDates | ForEach-Object { $_.Day }) -join ", "
    $segments += "$monthName $daysText ($yearValue)"
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

    $chapterNumber = $null
    $chapterTitle = ""
    if ($trimmed -match 'Chapter\s+(\d+)\s*-\s*([^\|]+)$') {
      $chapterNumber = [int]$matches[1]
      $chapterTitle = $matches[2].Trim()
    } elseif ($trimmed -match 'Chapter\s+(\d+)\s*\(([^\)]+)\)') {
      $chapterNumber = [int]$matches[1]
      $chapterTitle = $matches[2].Trim()
    } elseif ($trimmed -match 'Chapter\s+(\d+)') {
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
        $pythonProgressLines[$chaptersCompletedIndex] = "- **Chapters Completed:** $($pythonSnapshot.MaxChapter)/$($pythonSnapshot.MaxChapter) (Introduction → $($pythonSnapshot.MaxChapterTitle))"
      } else {
        $pythonProgressLines[$chaptersCompletedIndex] = "- **Chapters Completed:** $($pythonSnapshot.MaxChapter)/$($pythonSnapshot.MaxChapter)"
      }
    }
  }

  $activeDaysLoggedIndex = Find-LineIndex -Lines $pythonProgressLines -Predicate { param($line) $line -match '^- \*\*Active Days Logged:\*\*' }
  if ($activeDaysLoggedIndex -ge 0) {
    $pythonProgressLines[$activeDaysLoggedIndex] = "- **Active Days Logged:** $(@($pythonSnapshot.ActiveDates).Count) days"
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

  if (-not [string]::IsNullOrWhiteSpace($statusChapterTitle)) {
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

      $alreadyTracked = $readmeLines | Where-Object { $_ -match "\*\*$([Regex]::Escape($statusChapterTitle))\*\*" }
      if (-not $alreadyTracked) {
        $nextNumber = if ($statusChapter) {
          [int]$statusChapter
        } elseif ($trackLineIndices.Count -gt 0 -and $readmeLines[$trackLineIndices[-1]] -match "^(\d+)\.") {
          [int]$matches[1] + 1
        } else {
          1
        }

        $chapterDetail = if (-not [string]::IsNullOrWhiteSpace($ChapterSummary)) {
          $ChapterSummary
        } elseif (-not [string]::IsNullOrWhiteSpace($Concept)) {
          $Concept
        } else {
          "topic coverage"
        }

        $newTrackLine = "$nextNumber. **$statusChapterTitle** - $chapterDetail"
        if ($trackLineIndices.Count -gt 0) {
          $readmeLines.Insert($trackLineIndices[-1] + 1, $newTrackLine)
        } else {
          $readmeLines.Insert($trackHeaderIndex + 1, $newTrackLine)
        }
      }
    }
  }

  Set-Content -Path $readmePath -Value $readmeLines -Encoding UTF8
  Write-Host "Updated README activity sections: $readmePath"
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

powershell -ExecutionPolicy Bypass -File $syncScript -Message $Message
