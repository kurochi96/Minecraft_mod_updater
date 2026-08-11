param(
  [string]$ManifestPath = (Join-Path $PSScriptRoot "manifest.json")
)

$ErrorActionPreference = "Stop"

$AppDir = Join-Path $env:APPDATA ".swagsquad_updater"
$SettingsPath = Join-Path $AppDir "settings.json"

function Write-Info {
  param([string]$Message)
  Write-Host $Message -ForegroundColor Cyan
}

function Write-WarnJa {
  param([string]$Message)
  Write-Host $Message -ForegroundColor Yellow
}

function Write-ErrorJa {
  param([string]$Message)
  Write-Host "[エラー] $Message" -ForegroundColor Red
}

function Ensure-Directory {
  param([string]$Path)
  if (-not (Test-Path -LiteralPath $Path)) {
    New-Item -ItemType Directory -Path $Path -Force | Out-Null
  }
}

function Read-JsonFile {
  param(
    [string]$Path,
    [object]$DefaultValue = $null
  )
  if (-not (Test-Path -LiteralPath $Path)) {
    return $DefaultValue
  }
  $text = Get-Content -LiteralPath $Path -Raw -Encoding UTF8
  if ([string]::IsNullOrWhiteSpace($text)) {
    return $DefaultValue
  }
  return $text | ConvertFrom-Json
}

function Write-JsonFile {
  param(
    [string]$Path,
    [object]$Value
  )
  Ensure-Directory (Split-Path -Parent $Path)
  $json = $Value | ConvertTo-Json -Depth 20
  Set-Content -LiteralPath $Path -Value $json -Encoding UTF8
}

function Select-GameDirectory {
  param([string]$Description = "Minecraft のゲームディレクトリを選択してください")

  Add-Type -AssemblyName System.Windows.Forms
  $dialog = New-Object System.Windows.Forms.FolderBrowserDialog
  $dialog.Description = $Description
  $dialog.ShowNewFolderButton = $false

  $result = $dialog.ShowDialog()
  if ($result -ne [System.Windows.Forms.DialogResult]::OK -or [string]::IsNullOrWhiteSpace($dialog.SelectedPath)) {
    throw "フォルダが選択されませんでした。処理を中止します。"
  }

  return $dialog.SelectedPath
}

function Get-GameDirectory {
  $settings = Read-JsonFile -Path $SettingsPath -DefaultValue ([pscustomobject]@{})

  if ($settings -and $settings.gameDir -and (Test-Path -LiteralPath $settings.gameDir -PathType Container)) {
    return [string]$settings.gameDir
  }

  if ($settings -and $settings.gameDir) {
    Write-WarnJa "保存済みのゲームフォルダが見つかりません。選び直してください。"
  } else {
    Write-Info "初回起動のため、Minecraft のゲームディレクトリを選択してください。"
  }

  $selected = Select-GameDirectory
  Save-GameDirectory -GameDir $selected
  return $selected
}

function Save-GameDirectory {
  param([string]$GameDir)
  if (-not (Test-Path -LiteralPath $GameDir -PathType Container)) {
    throw "選択されたフォルダが存在しません: $GameDir"
  }

  Ensure-Directory $AppDir
  Write-JsonFile -Path $SettingsPath -Value ([ordered]@{
    gameDir = $GameDir
    updatedAt = (Get-Date).ToString("s")
  })
  Write-Info "ゲームフォルダを保存しました: $GameDir"
}

function Resolve-GamePath {
  param(
    [string]$GameDir,
    [string]$RelativePath
  )

  if ([string]::IsNullOrWhiteSpace($RelativePath)) {
    throw "manifest.json に空の path が含まれています。"
  }

  $normalizedRelative = $RelativePath -replace '/', '\'
  if ([System.IO.Path]::IsPathRooted($normalizedRelative) -or $normalizedRelative -match '(^|\\)\.\.(\\|$)') {
    throw "危険な相対パスのため処理できません: $RelativePath"
  }

  $baseFull = [System.IO.Path]::GetFullPath($GameDir)
  $targetFull = [System.IO.Path]::GetFullPath((Join-Path $GameDir $normalizedRelative))

  if (-not $targetFull.StartsWith($baseFull, [System.StringComparison]::OrdinalIgnoreCase)) {
    throw "ゲームフォルダ外を指すパスのため処理できません: $RelativePath"
  }

  return $targetFull
}

function Get-FileSha256 {
  param([string]$Path)
  if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
    return $null
  }
  return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Download-ManagedFile {
  param(
    [string]$Url,
    [string]$Destination,
    [string]$ExpectedSha256,
    [string]$DownloadDir
  )

  if ([string]::IsNullOrWhiteSpace($Url)) {
    throw "ダウンロードURLが空です: $Destination"
  }

  Ensure-Directory $DownloadDir
  Ensure-Directory (Split-Path -Parent $Destination)

  $tempName = [System.Guid]::NewGuid().ToString("N") + ".download"
  $tempPath = Join-Path $DownloadDir $tempName

  try {
    Write-Host "取得中: $Url"
    Invoke-WebRequest -Uri $Url -OutFile $tempPath -UseBasicParsing

    if (-not [string]::IsNullOrWhiteSpace($ExpectedSha256)) {
      $actual = Get-FileSha256 -Path $tempPath
      if ($actual -ne $ExpectedSha256.ToLowerInvariant()) {
        throw "SHA256 が一致しません。期待値: $ExpectedSha256 / 実際: $actual"
      }
    }

    Move-Item -LiteralPath $tempPath -Destination $Destination -Force
  } catch {
    if (Test-Path -LiteralPath $tempPath) {
      Remove-Item -LiteralPath $tempPath -Force
    }
    throw
  }
}

function Backup-Mods {
  param([string]$GameDir)

  $modsDir = Join-Path $GameDir "mods"
  if (-not (Test-Path -LiteralPath $modsDir -PathType Container)) {
    Ensure-Directory $modsDir
    return $null
  }

  $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
  $backupDir = Join-Path $GameDir ".swagsquad\backup\$timestamp\mods"
  Ensure-Directory $backupDir

  Copy-Item -LiteralPath (Join-Path $modsDir "*") -Destination $backupDir -Recurse -Force -ErrorAction SilentlyContinue
  return (Split-Path -Parent $backupDir)
}

function Convert-ManifestToDesiredFiles {
  param([object]$Manifest)

  $desired = New-Object System.Collections.Generic.List[object]

  foreach ($mod in @($Manifest.mods)) {
    if (-not $mod.fileName) {
      throw "manifest.json の mods に fileName がない項目があります。"
    }
    $desired.Add([pscustomobject]@{
      path = "mods/$($mod.fileName)"
      url = [string]$mod.url
      sha256 = [string]$mod.sha256
      kind = "mod"
      id = [string]$mod.id
    })
  }

  foreach ($file in @($Manifest.syncFiles)) {
    if (-not $file.path) {
      throw "manifest.json の syncFiles に path がない項目があります。"
    }
    $desired.Add([pscustomobject]@{
      path = [string]$file.path
      url = [string]$file.url
      sha256 = [string]$file.sha256
      kind = [string]$file.kind
      id = [string]$file.id
    })
  }

  return $desired
}

function Remove-OldManagedFiles {
  param(
    [string]$GameDir,
    [object]$State,
    [string[]]$DesiredPaths
  )

  if (-not $State -or -not $State.managedFiles) {
    return
  }

  $desiredSet = @{}
  foreach ($path in $DesiredPaths) {
    $desiredSet[$path.ToLowerInvariant()] = $true
  }

  foreach ($old in @($State.managedFiles)) {
    $oldPath = [string]$old.path
    if ([string]::IsNullOrWhiteSpace($oldPath)) {
      continue
    }
    if ($desiredSet.ContainsKey($oldPath.ToLowerInvariant())) {
      continue
    }

    $fullPath = Resolve-GamePath -GameDir $GameDir -RelativePath $oldPath
    if (Test-Path -LiteralPath $fullPath -PathType Leaf) {
      Write-WarnJa "旧管理ファイルを削除: $oldPath"
      Remove-Item -LiteralPath $fullPath -Force
    }
  }
}

function Update-ModsAndFiles {
  param([string]$GameDir)

  if (-not (Test-Path -LiteralPath $ManifestPath -PathType Leaf)) {
    throw "manifest.json が見つかりません: $ManifestPath"
  }

  $manifest = Read-JsonFile -Path $ManifestPath
  if (-not $manifest) {
    throw "manifest.json を読み込めませんでした。"
  }

  Write-Info "対象: Minecraft $($manifest.minecraft.version) / $($manifest.minecraft.loader) $($manifest.minecraft.loaderVersion)"

  $swagDir = Join-Path $GameDir ".swagsquad"
  $statePath = Join-Path $swagDir "state.json"
  $downloadDir = Join-Path $swagDir "downloads"
  Ensure-Directory $swagDir

  $state = Read-JsonFile -Path $statePath -DefaultValue ([pscustomobject]@{ managedFiles = @() })
  $desired = Convert-ManifestToDesiredFiles -Manifest $manifest
  $desiredPaths = @($desired | ForEach-Object { [string]$_.path })

  $backupRoot = Backup-Mods -GameDir $GameDir
  if ($backupRoot) {
    Write-Info "mods のバックアップを作成しました: $backupRoot"
  }

  Remove-OldManagedFiles -GameDir $GameDir -State $state -DesiredPaths $desiredPaths

  $managedRecords = New-Object System.Collections.Generic.List[object]

  foreach ($item in $desired) {
    $relativePath = [string]$item.path
    $targetPath = Resolve-GamePath -GameDir $GameDir -RelativePath $relativePath
    $expectedSha = [string]$item.sha256
    $currentSha = Get-FileSha256 -Path $targetPath

    if ((Test-Path -LiteralPath $targetPath -PathType Leaf) -and
        (-not [string]::IsNullOrWhiteSpace($expectedSha)) -and
        ($currentSha -eq $expectedSha.ToLowerInvariant())) {
      Write-Host "最新です: $relativePath"
    } else {
      Download-ManagedFile -Url ([string]$item.url) -Destination $targetPath -ExpectedSha256 $expectedSha -DownloadDir $downloadDir
      $currentSha = Get-FileSha256 -Path $targetPath
      Write-Info "更新しました: $relativePath"
    }

    $managedRecords.Add([ordered]@{
      path = $relativePath
      sha256 = $currentSha
      kind = [string]$item.kind
      id = [string]$item.id
      updatedAt = (Get-Date).ToString("s")
    })
  }

  Write-JsonFile -Path $statePath -Value ([ordered]@{
    manifestName = [string]$manifest.name
    manifestVersion = [string]$manifest.version
    minecraft = $manifest.minecraft
    managedFiles = $managedRecords
    lastUpdatedAt = (Get-Date).ToString("s")
  })

  Write-Info "更新が完了しました。"
}

function Show-Menu {
  param([string]$GameDir)

  Write-Host ""
  Write-Host "========================================"
  Write-Host " SwagSquad Minecraft MOD Updater"
  Write-Host "========================================"
  Write-Host "現在のゲームフォルダ:"
  Write-Host " $GameDir"
  Write-Host ""
  Write-Host "[1] MODを更新"
  Write-Host "[2] ゲームフォルダを選び直す"
  Write-Host "[3] 終了"
  Write-Host ""
  return Read-Host "番号を入力してください"
}

try {
  Ensure-Directory $AppDir
  $gameDir = Get-GameDirectory

  while ($true) {
    if (-not (Test-Path -LiteralPath $gameDir -PathType Container)) {
      Write-WarnJa "保存済みのゲームフォルダが存在しません。選び直してください。"
      $gameDir = Select-GameDirectory
      Save-GameDirectory -GameDir $gameDir
    }

    $choice = Show-Menu -GameDir $gameDir

    switch ($choice) {
      "1" {
        Update-ModsAndFiles -GameDir $gameDir
      }
      "2" {
        $gameDir = Select-GameDirectory -Description "新しい Minecraft のゲームディレクトリを選択してください"
        Save-GameDirectory -GameDir $gameDir
      }
      "3" {
        Write-Host "終了します。"
        exit 0
      }
      default {
        Write-WarnJa "1、2、3 のいずれかを入力してください。"
      }
    }
  }
} catch {
  Write-ErrorJa $_.Exception.Message
  Write-WarnJa "途中で失敗した場合でも、管理対象外の個人設定には触れていません。"
  exit 1
}
