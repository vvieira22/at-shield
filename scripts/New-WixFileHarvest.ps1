# Generates a WiX Fragment ComponentGroup from a directory under installer\staging.
# Deterministic component GUIDs (MD5 of relative path) so upgrades stay stable.
param(
  [Parameter(Mandatory = $true)][string]$StagingRoot,
  [Parameter(Mandatory = $true)][string]$RelativeDir,
  [Parameter(Mandatory = $true)][string]$DirectoryId,
  [Parameter(Mandatory = $true)][string]$ComponentGroupId,
  [Parameter(Mandatory = $true)][string]$OutFile,
  [string[]]$ExcludeNames = @()
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-DeterministicGuid([string]$s) {
  $md5 = [System.Security.Cryptography.MD5]::Create()
  try {
    $bytes = $md5.ComputeHash([Text.Encoding]::UTF8.GetBytes("ATShield|$s"))
  } finally {
    $md5.Dispose()
  }
  $bytes[7] = ($bytes[7] -band 0x0F) -bor 0x50
  $bytes[8] = ($bytes[8] -band 0x3F) -bor 0x80
  return [guid]::new($bytes).ToString().ToUpperInvariant()
}

function Get-SafeId([string]$rel) {
  $id = ($rel -replace '[^A-Za-z0-9]', '_')
  if ($id.Length -gt 60) {
    $hash = Get-DeterministicGuid $rel
    $id = $id.Substring(0, 40) + '_' + $hash.Substring(0, 8)
  }
  if ($id -match '^[0-9]') { $id = "F_$id" }
  return $id
}

$sourceDir = Join-Path $StagingRoot $RelativeDir
if (-not (Test-Path -LiteralPath $sourceDir)) {
  throw "SourceDir not found: $sourceDir"
}

$root = (Resolve-Path -LiteralPath $sourceDir).Path
$files = Get-ChildItem -LiteralPath $root -Recurse -File | Sort-Object FullName
$excludeSet = [System.Collections.Generic.HashSet[string]]::new(
  [string[]]$ExcludeNames,
  [StringComparer]::OrdinalIgnoreCase
)

$relPrefix = $RelativeDir.TrimEnd('\', '/').Replace('/', '\')

$sb = [System.Text.StringBuilder]::new()
[void]$sb.AppendLine('<?xml version="1.0" encoding="UTF-8"?>')
[void]$sb.AppendLine('<Wix xmlns="http://wixtoolset.org/schemas/v4/wxs">')
[void]$sb.AppendLine('  <Fragment>')
[void]$sb.AppendLine("    <ComponentGroup Id=`"$ComponentGroupId`">")

$count = 0
foreach ($f in $files) {
  if ($excludeSet.Contains($f.Name)) { continue }
  $rel = $f.FullName.Substring($root.Length).TrimStart('\', '/')
  $relUnix = $rel.Replace('\', '/')
  $dirRel = Split-Path -Parent $rel
  $compId = 'c_' + (Get-SafeId "$relPrefix/$relUnix")
  $fileId = 'f_' + (Get-SafeId "$relPrefix/$relUnix")
  $guid = Get-DeterministicGuid "$ComponentGroupId|$relPrefix|$relUnix"
  $fileSource = "!(bindpath.Staging)\$relPrefix\$($rel.Replace('/','\'))"

  if ([string]::IsNullOrEmpty($dirRel)) {
    [void]$sb.AppendLine("      <Component Id=`"$compId`" Directory=`"$DirectoryId`" Guid=`"$guid`">")
  } else {
    $sub = $dirRel.Replace('/', '\')
    [void]$sb.AppendLine("      <Component Id=`"$compId`" Directory=`"$DirectoryId`" Subdirectory=`"$sub`" Guid=`"$guid`">")
  }
  [void]$sb.AppendLine("        <File Id=`"$fileId`" Source=`"$fileSource`" KeyPath=`"yes`" />")
  [void]$sb.AppendLine('      </Component>')
  $count++
}

[void]$sb.AppendLine('    </ComponentGroup>')
[void]$sb.AppendLine('  </Fragment>')
[void]$sb.AppendLine('</Wix>')

$outDir = Split-Path -Parent $OutFile
if ($outDir -and -not (Test-Path $outDir)) { New-Item -ItemType Directory -Path $outDir | Out-Null }
[System.IO.File]::WriteAllText($OutFile, $sb.ToString(), [Text.UTF8Encoding]::new($false))
Write-Host "[harvest] $ComponentGroupId → $count files → $OutFile"
