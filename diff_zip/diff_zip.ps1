<#
.SYNOPSIS
Compare récursivement le contenu de deux fichiers ZIP (ou JAR/EAR/WAR).

.DESCRIPTION
Ce script utilise 7-Zip pour comparer deux fichiers ZIP sans tout extraire.
Il utilise une arborescence de dossiers temporaires logique et imbriquée.
Comparaison récursive, avec gestion de l'arrêt précoce pour les fichiers manquants
et affichage détaillé des fichiers responsables des différences de taille.

.PARAMETER zip1
Chemin du premier fichier ZIP.

.PARAMETER zip2
Chemin du second fichier ZIP.

.PARAMETER nbOctet
Tolérance en octets pour la comparaison de tailles.

.EXAMPLE
.\diff_zip.ps1 "C:\workspace\zip1.zip" "C:\workspace\zip2.zip" 800 -Verbose
#>

param(
    [Parameter(Mandatory=$true)][string]$zip1,
    [Parameter(Mandatory=$true)][string]$zip2,
    [Parameter(Mandatory=$true)][int]$nbOctet
)

$sevenZip = "C:\Program Files\7-Zip\7z.exe"

# 💡 Définition des chemins temporaires logiques et déterministes.
# On garde un GUID pour le dossier racine afin d'assurer l'isolation entre plusieurs exécutions.
$globalTempDir = [System.IO.Path]::GetFullPath((Join-Path ([System.IO.Path]::GetFullPath($env:TEMP)) ("diffzip_" + [Guid]::NewGuid())))
$tempZip1Root = Join-Path $globalTempDir "zip1_temp"
$tempZip2Root = Join-Path $globalTempDir "zip2_temp"


function Get-ZipListing {
    param([string]$zipPath)

    Write-Verbose "Lecture du contenu de : $zipPath"
    
    $output = & $sevenZip l -slt $zipPath 2>$null

    $entries = @()
    $current = @{}
    foreach ($line in $output) {
        if ($line -match "^Path = (.+)$") {
            $path = $matches[1]
            
            # 💡 Filtre essentiel pour ignorer les chemins absolus (faux positifs de 7z.exe)
            if ([System.IO.Path]::IsPathRooted($path)) {
                $current["Path"] = $null
            } else {
                $current["Path"] = $path
            }
        }
        elseif ($line -match "^Size = (\d+)$") {
            $current["Size"] = [int64]$matches[1]
        }
        elseif ($line -eq "") {
            if ($current["Path"]) {
                $entries += [PSCustomObject]@{
                    Path = $current["Path"]
                    Size = $current["Size"]
                }
            }
            $current = @{}
        }
    }

    return $entries
}

function Compare-ZipListings {
    param(
        [string]$zip1,
        [string]$zip2,
        [int]$tolerance,
        [string]$context = ""
    )

    Write-Verbose "Comparaison de : $zip1 et $zip2 ($context)"

    $list1 = Get-ZipListing $zip1
    $list2 = Get-ZipListing $zip2

    $paths1 = $list1.Path
    $paths2 = $list2.Path

    $only1 = $paths1 | Where-Object { $_ -notin $paths2 }
    $only2 = $paths2 | Where-Object { $_ -notin $paths1 }
    $common = $paths1 | Where-Object { $_ -in $paths2 }

    $diff1 = @()
    $diff2 = @()
	$exist1 = @()
	$exist2 = @()
    
    # Regex pour détecter les sous-archives
    $recursivePattern = '\.(zip|jar|war|ear)$'

    # Règle 1 : Fichiers/Dossiers uniquement présents - Arrêt précoce
    foreach ($p in $only1) {
        $exist1 += $list1 | Where-Object { $_.Path -eq $p }
    }
    foreach ($p in $only2) {
        $exist2 += $list2 | Where-Object { $_.Path -eq $p }
    }

    # Fichiers communs : comparer les tailles
    foreach ($p in $common) {
        $f1 = ($list1 | Where-Object { $_.Path -eq $p })[0]
        $f2 = ($list2 | Where-Object { $_.Path -eq $p })[0]

        $delta = [Math]::Abs($f1.Size - $f2.Size)

        if ($delta -gt $tolerance) {
            Write-Verbose " Différence de taille ($delta octets) : $p"
            
            # Vérifie si c'est une sous-archive
            if ($p -match $recursivePattern) {
                # Règle 2 : Archive de taille différente : on descend.

                # --- 💡 NOUVELLE LOGIQUE D'ARBORESCENCE IMBRIQUÉE ---
                
                # Le chemin relatif de la nouvelle archive (ex: root\sub.zip)
				Write-Verbose "$context $p nextContext p oktamer 1"
				$lastDir = Split-Path $p -Leaf
                $nextContext = Join-Path $context $lastDir
				
				Write-Verbose "$nextContext nextContext oktamer 2"

                # 💡 Les dossiers temporaires sont basés sur le chemin interne $nextContext.
                # Par exemple: $tempZip1Root\root\PFSE-V7.1.7-SNAPSHOT...\pfse-batch...zip
                $subDir1 = Join-Path $tempZip1Root $nextContext
                $subDir2 = Join-Path $tempZip2Root $nextContext
				
				Write-Verbose "$subDir1 $subDir2 subDir1 et subDir2 oktamer 1"
                
                # On s'assure que le dossier parent existe (nécessaire pour l'imbrication)
                New-Item -ItemType Directory -Force -Path $subDir1, $subDir2 | Out-Null
                # --- FIN NOUVELLE LOGIQUE ---
                
                # Extraction du fichier $p dans le nouveau dossier.
                # Note: 7z va extraire le fichier dans le dossier $subDirX, il portera le nom $p.
                & $sevenZip e "-o$subDir1" $zip1 $p -y | Out-Null
                & $sevenZip e "-o$subDir2" $zip2 $p -y | Out-Null

                $subZip1 = Join-Path $subDir1 (Split-Path $p -Leaf)
                $subZip2 = Join-Path $subDir2 (Split-Path $p -Leaf)
				
				Write-Verbose "$subDir1 $subDir2 subDir1 et subDir2 oktamer 2"

                if ((Test-Path $subZip1) -and (Test-Path $subZip2)) {
                    # L'appel récursif utilise le chemin complet $nextContext comme contexte
                    $subDiff = Compare-ZipListings $subZip1 $subZip2 $tolerance $nextContext
                    
                    $prefix = "$nextContext\"
					Write-Verbose "$prefix prefix oktamer"
                    
                    # Règle 2 : Remonter uniquement les différences internes (Exist1/2 et Diff1/2)
                    
                    $exist1 += $subDiff.Exist1 | Select-Object @{N='Path';E={$prefix + $_.Path}}, Size
                    $exist2 += $subDiff.Exist2 | Select-Object @{N='Path';E={$prefix + $_.Path}}, Size
                    
                    $diff1 += $subDiff.Diff1 | Select-Object @{N='Path';E={$prefix + $_.Path}}, Size
                    $diff2 += $subDiff.Diff2 | Select-Object @{N='Path';E={$prefix + $_.Path}}, Size
                }

                # Nettoyage des dossiers temporaires de cette itération
                # (Commenté pour le débogage, mais préférable de le remettre)
                # Remove-Item $subDir1,$subDir2 -Recurse -Force -ErrorAction SilentlyContinue
                
            } else {
                # C'est un fichier simple avec une différence de taille : on l'ajoute.
                $diff1 += $f1
                $diff2 += $f2
            }
        }
    }

    # --- Post-traitement pour Règle 1 (Nettoyage de la duplication des chemins manquants) ---
    $uniqueExist1 = @()
    $Exist1Paths = $exist1.Path -as [System.Collections.Generic.HashSet[string]]
    foreach ($f in $exist1) {
        $isSubPath = $false
        foreach ($otherPath in $Exist1Paths) {
            if ($otherPath -ne $f.Path -and ($f.Path.StartsWith($otherPath + '/') -or $f.Path.StartsWith($otherPath + '\'))) {
                $isSubPath = $true
                break
            }
        }
        if (-not $isSubPath) {
            $uniqueExist1 += $f
        }
    }
    
    $uniqueExist2 = @()
    $Exist2Paths = $exist2.Path -as [System.Collections.Generic.HashSet[string]]
    foreach ($f in $exist2) {
        $isSubPath = $false
        foreach ($otherPath in $Exist2Paths) {
            if ($otherPath -ne $f.Path -and ($f.Path.StartsWith($otherPath + '/') -or $f.Path.StartsWith($otherPath + '\'))) {
                $isSubPath = $true
                break
            }
        }
        if (-not $isSubPath) {
            $uniqueExist2 += $f
        }
    }
    
    # --- Post-traitement pour Règle 2 (Nettoyage des archives dans Diff1/Diff2) ---
    $FinalDiff1 = $diff1 | Where-Object { $_.Path -notmatch $recursivePattern }
    $FinalDiff2 = $diff2 | Where-Object { $_.Path -notmatch $recursivePattern }

    return [PSCustomObject]@{
        Diff1 = $FinalDiff1
        Diff2 = $FinalDiff2
		Exist1 = $uniqueExist1
		Exist2 = $uniqueExist2
    }
}

# -------------------------------------------------------------------------
# Bloc Principal
# -------------------------------------------------------------------------

try {
    Write-Verbose "=== Début de la comparaison ==="

    $zip1Full = Resolve-Path $zip1
    $zip2Full = Resolve-Path $zip2
    
    # Création des dossiers temporaires racines (logiques)
    New-Item -ItemType Directory -Force -Path $globalTempDir, $tempZip1Root, $tempZip2Root | Out-Null

    $result = Compare-ZipListings $zip1Full $zip2Full $nbOctet "root"

    # --- AFFICHAGE DES RÉSULTATS ---
    
	Write-Host "`n[Fichiers/Dossiers présents uniquement dans $zip1]"
    foreach ($f in $result.Exist1) {
        Write-Host ".\$zip1\$($f.Path)"
    }
	
	Write-Host "`n[Fichiers/Dossiers présents uniquement dans $zip2]"
    foreach ($f in $result.Exist2) {
        Write-Host ".\$zip2\$($f.Path)"
    }

    Write-Host "`n[Fichiers avec une taille différente (+ $nbOctet octets)]"
    foreach ($f in $result.Diff1) {
        Write-Host ".\$zip1\$($f.Path)"
    }

} catch {
    Write-Error "Erreur : $_"
} finally {
    # 💡 REMARQUE : La suppression est commentée pour la revue de l'arborescence.
    # Décommenter la section suivante pour le nettoyage automatique en production.
    # --------------------------------------------------------------------------
    # if (Test-Path $globalTempDir) {
    #     Write-Verbose "Nettoyage du dossier temporaire racine : $globalTempDir"
    #     try {
    #         Remove-Item -LiteralPath $globalTempDir -Recurse -Force -ErrorAction SilentlyContinue
    #     } catch {
    #         Write-Warning "Impossible de supprimer le dossier temporaire : $globalTempDir"
    #     }
    # }
    # --------------------------------------------------------------------------
    Write-Verbose "=== Fin de la comparaison ==="
}