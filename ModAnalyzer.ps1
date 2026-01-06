Clear-Host
$Logo = @"
 _____      _        _____ _                
|  ___|_ _| | _____|_   _(_)_ __ ___   ___ 
| |_ / _` | |/ / _ \ | | | | '_ ` _ \ / _ \
|  _| (_| |   <  __/ | | | | | | | | |  __/
|_|  \__,_|_|\_\___| |_| |_|_| |_| |_|\___|
"@
Write-Host $Logo -ForegroundColor Cyan
Write-Host "" # Пустая строка для отступа

$defaultMods = "$env:USERPROFILE\AppData\Roaming\.minecraft\mods"
$mods = $defaultMods

if (-not (Test-Path $mods -PathType Container)) {
    Write-Host "Папка mods не найдена! Путь: $mods" -ForegroundColor Red
    exit 1
}

Write-Host "Найден путь: $mods" -ForegroundColor White
Write-Host

function Get-SHA1 {
    param ([string]$filePath)
    return (Get-FileHash -Path $filePath -Algorithm SHA1).Hash
}

function Get-ZoneIdentifier {
    param ([string]$filePath)
	$ads = Get-Content -Raw -Stream Zone.Identifier $filePath -ErrorAction SilentlyContinue
	if ($ads -match "HostUrl=(.+)") {
		return $matches[1]
	}
	return $null
}

function Fetch-Modrinth {
    param ([string]$hash)
    try {
        $response = Invoke-RestMethod -Uri "https://api.modrinth.com/v2/version_file/$hash" -Method Get -UseBasicParsing -ErrorAction Stop
		if ($response.project_id) {
            $projectResponse = "https://api.modrinth.com/v2/project/$($response.project_id)"
            $projectData = Invoke-RestMethod -Uri $projectResponse -Method Get -UseBasicParsing -ErrorAction Stop
            return @{ Name = $projectData.title; Slug = $projectData.slug }
        }
    } catch {}
	return @{ Name = ""; Slug = "" }
}

function Fetch-Megabase {
    param ([string]$hash)
    try {
        $response = Invoke-RestMethod -Uri "https://megabase.vercel.app/api/query?hash=$hash" -Method Get -UseBasicParsing -ErrorAction Stop
		if (-not $response.error) {
			return $response.data
		}
    } catch {}
	return $null
}

$cheatStrings = @(
  "AimAssist", "AnchorTweaks", "AutoAnchor", "AutoCrystal", "AutoDoubleHand",
  "AutoHitCrystal", "AutoPot", "AutoTotem", "AutoArmor", "InventoryTotem",
  "Hitboxes", "JumpReset", "LegitTotem", "PingSpoof", "SelfDestruct",
  "ShieldBreaker", "TriggerBot", "Velocity", "AxeSpam", "WebMacro",
  "FastPlace", "areyoufuckingdump", "me.didyoumuch.Native", "stubborn.website",
  "Vsevolod", "(Lbrx;DDD)VI", "Lbrx;DDD)VL", "(Lbrx;DDD)Vg", ".crash",
  "bushroot", "imapDef", "imoRs", "BaoBab", "waohitbox", "ogohiti",
  "MagicThe", "reach:", "#size", "neathitbox", "Derick1337"
)

function Check-Jar-Content {
	param ([string]$jarPath)
	
	try {
		Add-Type -AssemblyName System.IO.Compression.FileSystem
		$jarFile = [System.IO.Compression.ZipFile]::OpenRead($jarPath)
		
		$foundStrings = [System.Collections.Generic.HashSet[string]]::new()
		
		foreach ($entry in $jarFile.Entries) {
			if ($entry.Name.EndsWith(".class") -or $entry.Name.EndsWith(".json") -or 
				$entry.Name -match "\.(txt|yml|yaml|properties|cfg)$") {
				
				try {
					$reader = New-Object System.IO.StreamReader $entry.Open()
					$content = $reader.ReadToEnd()
					$reader.Close()
					
					foreach ($cheatString in $cheatStrings) {
						if ($content -match [regex]::Escape($cheatString)) {
							$foundStrings.Add($cheatString) | Out-Null
						}
					}
				} catch {}
			}
		}
		
		$jarFile.Dispose()
		return $foundStrings
	} catch {
		return [System.Collections.Generic.HashSet[string]]::new()
	}
}

function Check-Jar-File {
	param ([string]$jarPath)
	
	try {
		$foundStrings = [System.Collections.Generic.HashSet[string]]::new()
		$fileBytes = [System.IO.File]::ReadAllBytes($jarPath)
		$fileText = [System.Text.Encoding]::Default.GetString($fileBytes)
		
		foreach ($cheatString in $cheatStrings) {
			if ($fileText.Contains($cheatString)) {
				$foundStrings.Add($cheatString) | Out-Null
			}
		}
		
		return $foundStrings
	} catch {
		return [System.Collections.Generic.HashSet[string]]::new()
	}
}

$verifiedMods = @()
$unknownMods = @()
$cheatMods = @()
$jarFiles = Get-ChildItem -Path $mods -Filter *.jar

if ($jarFiles.Count -eq 0) {
    Write-Host "В папке mods не найдено файлов .jar!" -ForegroundColor Red
    exit 1
}

Write-Host "Сканирование модов..." -ForegroundColor Cyan
Write-Host

foreach ($file in $jarFiles) {
	$hash = Get-SHA1 -filePath $file.FullName
	
    $modDataModrinth = Fetch-Modrinth -hash $hash
    if ($modDataModrinth.Slug) {
		$verifiedMods += [PSCustomObject]@{ ModName = $modDataModrinth.Name; FileName = $file.Name }
		continue
    }
	
	$modDataMegabase = Fetch-Megabase -hash $hash
	if ($modDataMegabase.name) {
		$verifiedMods += [PSCustomObject]@{ ModName = $modDataMegabase.Name; FileName = $file.Name }
		continue
	}
	
	$zoneId = Get-ZoneIdentifier $file.FullName
	$unknownMods += [PSCustomObject]@{ FileName = $file.Name; FilePath = $file.FullName; ZoneId = $zoneId }
}

if ($unknownMods.Count -gt 0) {
	Write-Host "Поиск вредоносных строк в неизвестных модах..." -ForegroundColor Cyan
	
	foreach ($mod in $unknownMods) {
		$foundStrings = Check-Jar-Content -jarPath $mod.FilePath
		
		if ($foundStrings.Count -eq 0) {
			$foundStrings = Check-Jar-File -jarPath $mod.FilePath
		}
		
		if ($foundStrings.Count -gt 0) {
			$unknownMods = @($unknownMods | Where-Object -FilterScript {$_ -ne $mod})
			$cheatMods += [PSCustomObject]@{ FileName = $mod.FileName; StringsFound = $foundStrings }
		}
	}
}

Write-Host

if ($verifiedMods.Count -gt 0) {
	Write-Host "{ Проверенные моды ($($verifiedMods.Count)) }" -ForegroundColor DarkCyan
	foreach ($mod in $verifiedMods) {
		Write-Host "> $($mod.ModName)" -ForegroundColor Green
	}
	Write-Host
}

if ($unknownMods.Count -gt 0) {
	Write-Host "{ Неизвестные моды ($($unknownMods.Count)) }" -ForegroundColor DarkCyan
	foreach ($mod in $unknownMods) {
		Write-Host "> $($mod.FileName)" -ForegroundColor DarkYellow
	}
	Write-Host
}

if ($cheatMods.Count -gt 0) {
	Write-Host "{ Потенциально опасные моды ($($cheatMods.Count)) }" -ForegroundColor Red
	foreach ($mod in $cheatMods) {
		Write-Host "> $($mod.FileName)" -ForegroundColor Red
		Write-Host "  Обнаружены строки: $($mod.StringsFound -join ', ')" -ForegroundColor DarkMagenta
	}
	Write-Host
}

Write-Host "Всего модов: $($jarFiles.Count)" -ForegroundColor White
Write-Host "Проверенные: $($verifiedMods.Count)" -ForegroundColor Green
Write-Host "Неизвестные: $($unknownMods.Count)" -ForegroundColor DarkYellow
Write-Host "Подозрительные: $($cheatMods.Count)" -ForegroundColor Red
Write-Host
