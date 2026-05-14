param(
  [Parameter(Mandatory = $false)]
  [int]$Day,

  [Parameter(Mandatory = $true)]
  [string]$Chapter,

  [Parameter(Mandatory = $true)]
  [string]$Concept,

  [string]$Security = "OWASP mapping update",
  [string]$Type = "docs"
)

if (-not $PSBoundParameters.ContainsKey("Day")) {
  $Day = (Get-Date).Day
}

$chapterSlug = $Chapter.Trim()
$conceptSlug = $Concept.Trim()
$securitySlug = $Security.Trim()

$message = "$Type(day-$Day): ch$chapterSlug $conceptSlug + $securitySlug"
Write-Output $message
