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
$entryDetailLines = @(
  "- **Streak Activity:** $StreakActivity Boot.dev/GitHub $activityWord",
  "- **Chapter Focus:** $ChapterFocus",
  "- **Lesson Concepts Covered:** $LessonConceptsCovered",
  "- **Security Connection:** $SecurityConnection"
)
$entryMarkdownLines = @($entryHeaderLine) + $entryDetailLines + @("")
$entryMarkdownBlock = ($entryMarkdownLines -join [Environment]::NewLine)
$legacyEntryLines = @(
  $entryDateText,
  "Streak Activity: $StreakActivity Boot.dev/GitHub $activityWord",
  "Chapter Focus: $ChapterFocus",
  "Lesson Concepts Covered: $LessonConceptsCovered",
  "Security Connection: $SecurityConnection"
)

$progressLogs = @(
  (Join-Path $projectsRoot "bootdev-python-security\progress-log.md"),
  (Join-Path $projectsRoot "bootdev-security-journey\progress-log.md")
)

foreach ($progressLog in $progressLogs) {
  if (-not (Test-Path $progressLog)) {
    Write-Host "Skipping missing progress log: $progressLog"
    continue
  }

  $logLines = [System.Collections.Generic.List[string]](Get-Content -Path $progressLog)
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

  $monthIndex = $logLines.FindIndex({ $_.Trim() -eq $entryMonthHeader })
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
  Set-Content -Path $progressLog -Value $logLines
  Write-Host "Upserted progress entry in: $progressLog"
}

$pythonRepo = Join-Path $projectsRoot "bootdev-python-security"
$readmePath = Join-Path $pythonRepo "README.md"
$chaptersPath = Join-Path $pythonRepo "chapters"
$notesPath = Join-Path $pythonRepo "notes"

if (Test-Path $readmePath) {
  $readmeLines = [System.Collections.Generic.List[string]](Get-Content -Path $readmePath)
  $treePipe = [char]0x2502
  $treeBranch = [char]0x251C
  $treeEnd = [char]0x2514
  $treeDash = [char]0x2500
  $branchToken = "$treeBranch$treeDash$treeDash"
  $endToken = "$treeEnd$treeDash$treeDash"
  $pipeToken = "$treePipe"
  $treeLinePattern = '^' + [regex]::Escape($pipeToken) + '\s+(' + [regex]::Escape($treeBranch) + '|' + [regex]::Escape($treeEnd) + ')' + [regex]::Escape("$treeDash$treeDash")
  $noteLinePattern = '^\s{4}(' + [regex]::Escape($treeBranch) + '|' + [regex]::Escape($treeEnd) + ')' + [regex]::Escape("$treeDash$treeDash") + '\s+(.*)'

  $statusIndex = $readmeLines.FindIndex({ $_ -match "^\- \*\*Status:\*\*" })
  if ($statusIndex -ge 0 -and -not [string]::IsNullOrWhiteSpace($Chapter) -and -not [string]::IsNullOrWhiteSpace($ChapterTitle)) {
    $readmeLines[$statusIndex] = "- **Status:** ✅ Completed through **Chapter $Chapter ($ChapterTitle)**"
  }

  $activeIndex = $readmeLines.FindIndex({ $_ -match "^\- \*\*Active Days Synced:\*\*" })
  if ($activeIndex -ge 0) {
    $activeLine = $readmeLines[$activeIndex]
    $startMonth = $EntryDate.ToString("MMMM")
    $startDay = $EntryDate.Day
    $yearValue = $EntryDate.Year

    if ($activeLine -match "\*\*Active Days Synced:\*\*\s+([A-Za-z]+)\s+(\d{1,2})\s*-\s*([A-Za-z]+)\s+(\d{1,2})\s+\((\d{4})\)") {
      $startMonth = $matches[1]
      $startDay = [int]$matches[2]
      $yearValue = [int]$matches[5]
    } elseif ($activeLine -match "\*\*Active Days Synced:\*\*\s+([A-Za-z]+)\s+(\d{1,2})") {
      $startMonth = $matches[1]
      $startDay = [int]$matches[2]
      if ($activeLine -match "\((\d{4})\)") {
        $yearValue = [int]$matches[1]
      }
    }

    $endMonth = $EntryDate.ToString("MMMM")
    $endDay = $EntryDate.Day
    $readmeLines[$activeIndex] = "- **Active Days Synced:** $startMonth $startDay - $endMonth $endDay ($yearValue)"
  }

  $repoHeaderIndex = $readmeLines.FindIndex({ $_ -eq "## Repository Structure" })
  if ($repoHeaderIndex -ge 0) {
    $blockStart = $readmeLines.FindIndex($repoHeaderIndex, { $_ -match '^```text' })
    if ($blockStart -ge 0) {
      $blockEnd = $readmeLines.FindIndex($blockStart + 1, { $_ -match '^```' })
      if ($blockEnd -gt $blockStart) {
        $blockLines = [System.Collections.Generic.List[string]]($readmeLines.GetRange($blockStart + 1, $blockEnd - $blockStart - 1))

        if (Test-Path $chaptersPath) {
          $chapterDirs = Get-ChildItem -Path $chaptersPath -Directory | Sort-Object Name | Select-Object -ExpandProperty Name
          if (-not [string]::IsNullOrWhiteSpace($ChapterFolder) -and ($chapterDirs -notcontains $ChapterFolder)) {
            $chapterDirs += $ChapterFolder
            $chapterDirs = $chapterDirs | Sort-Object
          }

          if ($chapterDirs.Count -gt 0) {
            $chaptersHeaderIndex = $blockLines.FindIndex({ $_ -eq "$branchToken chapters/" })
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
          $notesHeaderIndex = $blockLines.FindIndex({ $_ -match "notes/" })
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

  if (-not [string]::IsNullOrWhiteSpace($ChapterTitle)) {
    $trackHeaderIndex = $readmeLines.FindIndex({ $_ -match "^## Chapter Track" })
    if ($trackHeaderIndex -ge 0) {
      $trackLineIndices = @()
      for ($i = $trackHeaderIndex + 1; $i -lt $readmeLines.Count; $i++) {
        if ($readmeLines[$i] -match "^\d+\.\s+\*\*") {
          $trackLineIndices += $i
        } elseif ($readmeLines[$i] -match "^##\s+") {
          break
        }
      }

      $alreadyTracked = $readmeLines | Where-Object { $_ -match "\*\*$([Regex]::Escape($ChapterTitle))\*\*" }
      if (-not $alreadyTracked) {
        $nextNumber = if (-not [string]::IsNullOrWhiteSpace($Chapter) -and $Chapter -match "^\d+$") {
          [int]$Chapter
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

        $newTrackLine = "$nextNumber. **$ChapterTitle** - $chapterDetail"
        if ($trackLineIndices.Count -gt 0) {
          $readmeLines.Insert($trackLineIndices[-1] + 1, $newTrackLine)
        } else {
          $readmeLines.Insert($trackHeaderIndex + 1, $newTrackLine)
        }
      }
    }
  }

  Set-Content -Path $readmePath -Value $readmeLines
  Write-Host "Updated README activity sections: $readmePath"
}

$journeyReadmePath = Join-Path $projectsRoot "bootdev-security-journey\README.md"
if (Test-Path $journeyReadmePath) {
  $journeyLines = [System.Collections.Generic.List[string]](Get-Content -Path $journeyReadmePath)
  $timelineIndex = $journeyLines.FindIndex({ $_ -eq "## Progress Timeline" })
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

  Set-Content -Path $journeyReadmePath -Value $journeyLines
  Write-Host "Updated README activity sections: $journeyReadmePath"
}

powershell -ExecutionPolicy Bypass -File $syncScript -Message $Message
