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

if (-not (Test-Path $syncScript)) {
  Write-Error "Sync script not found: $syncScript"
  exit 1
}

$defaultOwasp = "A09: Security Logging and Monitoring Failures"
$defaultScreenshotDir = Join-Path $projectsRoot "Boot.Dev screenshots"
if ([string]::IsNullOrWhiteSpace($ScreenshotDir)) {
  $ScreenshotDir = $defaultScreenshotDir
}

if (([string]::IsNullOrWhiteSpace($Chapter) -or [string]::IsNullOrWhiteSpace($ChapterTitle) -or [string]::IsNullOrWhiteSpace($Concept)) -and (-not $ScreenshotPaths -or $ScreenshotPaths.Count -eq 0)) {
  if (Test-Path $ScreenshotDir) {
    $ScreenshotPaths = Get-ChildItem -Path $ScreenshotDir -File -Include *.png,*.jpg,*.jpeg,*.bmp,*.gif |
      Where-Object { $_.LastWriteTime.Date -eq $EntryDate.Date } |
      Sort-Object LastWriteTime |
      Select-Object -ExpandProperty FullName
  }
}

if ($ScreenshotPaths -and $ScreenshotPaths.Count -gt 0) {
  $tesseractCommand = Get-Command $TesseractPath -ErrorAction SilentlyContinue
  if ($tesseractCommand) {
    $ocrText = ""
    foreach ($path in $ScreenshotPaths) {
      if (-not (Test-Path $path)) {
        Write-Host "Screenshot not found: $path"
        continue
      }

      $ocrText += (& $TesseractPath $path stdout 2>$null)
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
$entryLines = @(
  $entryDateText,
  "Streak Activity: $StreakActivity Boot.dev/GitHub $activityWord",
  "Chapter Focus: $ChapterFocus",
  "Lesson Concepts Covered: $LessonConceptsCovered",
  "Security Connection: $SecurityConnection"
)
$entryBlock = ($entryLines -join [Environment]::NewLine)

$progressLogs = @(
  (Join-Path $projectsRoot "bootdev-python-security\progress-log.md"),
  (Join-Path $projectsRoot "bootdev-security-journey\progress-log.md")
)

foreach ($progressLog in $progressLogs) {
  if (-not (Test-Path $progressLog)) {
    Write-Host "Skipping missing progress log: $progressLog"
    continue
  }

  $existingContent = Get-Content -Path $progressLog -Raw
  if ($existingContent -like "*$entryBlock*") {
    Write-Host "Progress entry already exists in: $progressLog"
    continue
  }

  if (-not [string]::IsNullOrWhiteSpace($existingContent) -and -not $existingContent.EndsWith([Environment]::NewLine)) {
    Add-Content -Path $progressLog -Value ""
  }

  Add-Content -Path $progressLog -Value ""
  Add-Content -Path $progressLog -Value $entryBlock
  Write-Host "Appended progress entry to: $progressLog"
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
