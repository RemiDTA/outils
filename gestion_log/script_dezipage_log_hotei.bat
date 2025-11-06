@echo off
setlocal enabledelayedexpansion
:: Ce script a pour but de simplifier la lecture des logs récupérer depuis hotei
:: Il doit être placé à côté du dossier "wildfly" qui contient des dossiers contenant les logs de PROD
:: Il s'agit d'un script à destination des développeurs pour automatiser une partie de la TMA
:: Théoriquement il faudrait lancer le script, puis via un outil comme n++ (ctrl + F et rechercher dans les fichiers) ou vsc, faire une recherche sur un
:: TRANSNUM ou un CODE dossier ou autre dans le contenu des fichiers en fournissant à n++ / vsc le dossier wildfly

:: Dans les grandes lignes le script va récupérer une date en paramètre, cette date est en fait le suffixe des fichier .gz qui intéresse le développeur
:: Puis il va dans chacun des dossier sous ./wildfly et pour chaque fichier gz, vérifier s'il existe des fichiers au format *_DATE_SUFIXE.gz
:: Déziper ces fichiers et à la fin supprimer tous les gz

:: Le choix de le faire en .bat tient au fait que le PC CASA est sous windows et qu'on ne peut pas tout installer (Comme PowerShell)

::TODO : A voir s'il ne serait pas intéressant que ce script gère le dézipage de pse-jee*.tar.gz

:: Chemin vers l'exécutable 7z
set "SEVENZIP=%ProgramFiles%\7-Zip\7z.exe"

:: Vérifie l'existence de 7z.exe
if not exist "%SEVENZIP%" (
    echo [ERREUR] L'outil 7-Zip est introuvable : "%SEVENZIP%"
    echo Installez 7-Zip ou modifiez le chemin dans le script.
    exit /b 1
)

:: Demande la date a l'utilisateur
set /p TARGET_DATE="Entrez la date a traiter (format YYYY-MM-DD) :"
if "%TARGET_DATE%"=="" (
	::Si aucune date n'a ete saisie, peut être qu'il faut tout deziper
	set /p DEZIP_ALL="Voulez-vous tout deziper (y pour oui)"
	if /I not "%DEZIP_ALL%"=="y" (
		echo [ERREUR] Aucune date saisie / ou dezipe all. Abandon.
		exit /b 1
	)
)

set "WILDFLY_DIR=%~dp0wildfly"

:: Verifie l'existence du dossier wildfly
if not exist "%WILDFLY_DIR%" (
    echo [ERREUR] Le dossier "wildfly" n'existe pas dans le repertoire courant.
    exit /b 1
)

echo [INFO] Recherche des fichiers *.gz...

:: Parcours recursif des fichiers .gz dans wildfly
for /R "%WILDFLY_DIR%" %%F in (*.gz) do (
    set "FILENAME=%%~nxF"
    set "FULLPATH=%%~fF"

    :: Suffixe de type .YYYY-MM-DD.gz
    set "SUFFIX=!FILENAME:~-14!"

    set "DEZIP=n"
    if "!SUFFIX!"==".%TARGET_DATE%.gz" set "DEZIP=y"
    if "!DEZIP_ALL!"=="y" set "DEZIP=y"

    if "!DEZIP!"=="y" (
        echo [INFO] Decompression de "%%F"...

        :: Dezippe dans le même dossier
        "%SEVENZIP%" x -y "%%F" -o"%%~dpF" >nul

        :: Nom sans .gz
        set "WITHOUT_GZ=%%~nF"

        :: Extraire la date depuis le suffixe : .YYYY-MM-DD.gz → YYYY-MM-DD
        set "DATE_FROM_NAME=!SUFFIX:~1,10!"

        :: Enlève la date du nom
        set "BASE_WITH_EXT=!WITHOUT_GZ:.!DATE_FROM_NAME!=!"

        :: Separer extension reelle
        for %%X in ("!BASE_WITH_EXT!") do (
            set "NAME_ONLY=%%~nX"
        )

        :: Construit le nom final : <DATE>_<NOM><EXT>
        set "NEWNAME=!DATE_FROM_NAME!_!NAME_ONLY!"

        ren "%%~dpF!WITHOUT_GZ!" "!NEWNAME!"
        echo [INFO] Renomme en "!NEWNAME!"
    )
)

:: Déplacement des fichiers .gz dans save_gz
echo [INFO] Déplacement des fichiers .gz vers le dossier save_gz...

:: Dossier de sauvegarde
set "SAVE_GZ_DIR=%~dp0save_gz"

:: Création du dossier s'il n'existe pas
if not exist "%SAVE_GZ_DIR%" (
    mkdir "%SAVE_GZ_DIR%"
)

for /R "%WILDFLY_DIR%" %%F in (*.gz) do (
    echo [INFO] Déplacement de "%%F" vers "%SAVE_GZ_DIR%"...
    move "%%F" "%SAVE_GZ_DIR%" >nul
)

echo [TERMINE] Tous les fichiers ont ete traites.
exit /b 0