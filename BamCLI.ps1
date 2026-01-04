$ErrorActionPreference = "SilentlyContinue"

# Вывод ASCII арта в начале
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

function Get-Signature {
    param ([string[]]$FilePath)

    $Existence = Test-Path -PathType "Leaf" -Path $FilePath
    $Authenticode = (Get-AuthenticodeSignature -FilePath $FilePath -ErrorAction SilentlyContinue).Status

    if ($Existence) {
        if ($Authenticode -eq "Valid") { return "Valid Signature" }
        elseif ($Authenticode -eq "NotSigned") { return "Invalid Signature (NotSigned)" }
        else { return "Invalid Signature" }
    } else {
        return "File Was Not Found"
    }
}

try {
    $Users = foreach($ii in ("bam", "bam\State")) {
        Get-ChildItem -Path "HKLM:\SYSTEM\CurrentControlSet\Services\$($ii)\UserSettings\" | Select-Object -ExpandProperty PSChildName
    }
}
catch {
    Write-Warning "Error Parsing BAM Key"
    Exit
}

$rpath = @("HKLM:\SYSTEM\CurrentControlSet\Services\bam\","HKLM:\SYSTEM\CurrentControlSet\Services\bam\state\")

$Bam = Foreach ($Sid in $Users) {
    foreach($rp in $rpath) {
        $BamItems = Get-Item -Path "$($rp)UserSettings\$Sid" -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Property

        ForEach ($Item in $BamItems) {
            $Key = Get-ItemProperty -Path "$($rp)UserSettings\$Sid" -ErrorAction SilentlyContinue | Select-Object -ExpandProperty $Item

            If($key.length -eq 24) {
                $Hex = [System.BitConverter]::ToString($key[7..0]) -replace "-",""
                $TimeUTC = Get-Date ([DateTime]::FromFileTimeUtc([Convert]::ToInt64($Hex, 16))) -Format "dd.MM.yy HH:mm"

                if((((split-path -path $item) | ConvertFrom-String -Delimiter "\\").P3)-match '\d{1}') {
                    $path = Join-Path -Path "C:" -ChildPath ($item).Remove(1,23)
                    $sig = Get-Signature -FilePath $path
                    $app = Split-path -leaf ($item).TrimStart()
                } else {
                    $path = ""
                    $sig = "N/A"
                    $app = $item
                }

                [PSCustomObject]@{
                    'Time' = $TimeUTC
                    'Application' = $app
                    'Signature' = $sig
                    'Path' = $path
                    'SortDate' = [DateTime]::FromFileTimeUtc([Convert]::ToInt64($Hex, 16))
                }
            }
        }
    }
}

$FilteredBam = $Bam | Where-Object {
    $_.Signature -eq "Invalid Signature (NotSigned)" -or
    $_.Signature -eq "File Was Not Found"
} | Sort-Object SortDate -Descending

if ($FilteredBam) {
    Write-Host "--- Found potentially suspicious entries ---`n" -ForegroundColor Gray
    $FilteredBam | ForEach-Object {
        [PSCustomObject]@{
            'Time' = $_.Time
            'Application' = $_.Application
            'Signature' = $_.Signature
            'Path' = $_.Path
        }
    } | Format-Table -AutoSize | Out-String | ForEach-Object {
        $lines = $_ -split "`r`n"
        foreach ($line in $lines) {
            if ($line -match "File Was Not Found") {
                Write-Host $line -ForegroundColor Yellow
            } elseif ($line -match "Invalid Signature") {
                Write-Host $line -ForegroundColor Red
            } else {
                Write-Host $line
            }
        }
    }
} else {
    Write-Host "No filtered entries found. System looks clean." -ForegroundColor Green
}
