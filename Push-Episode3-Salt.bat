@echo off
REM Double-click this file to finish publishing Episode 3 v2 ("Salt").
REM
REM What it does:
REM   1. Removes a stale .git\index.lock file that's blocking commits
REM   2. Stages all the rewrite work + the new audio + the new feed.xml
REM   3. Commits with a clear message
REM   4. Pushes to GitHub Pages so Spotify can pull the new feed
REM
REM This script is safe to re-run.

set "BASH_EXE=C:\Program Files\Git\bin\bash.exe"
if not exist "%BASH_EXE%" set "BASH_EXE=C:\Program Files (x86)\Git\bin\bash.exe"
if not exist "%BASH_EXE%" set "BASH_EXE=%LOCALAPPDATA%\Programs\Git\bin\bash.exe"

if not exist "%BASH_EXE%" (
    echo ERROR: Could not find Git Bash on this machine.
    pause
    exit /b 1
)

cd /d "%~dp0"

echo ===============================================================
echo  Pushing Episode 3 v2 -- "Salt" -- to GitHub
echo ===============================================================
echo.

echo Step 1: Removing stale git lock file (if present)...
if exist ".git\index.lock" (
    del /f ".git\index.lock"
    echo   Lock removed.
) else (
    echo   No lock file. Good.
)
echo.

echo Step 2: Staging all rewrite files...
"%BASH_EXE%" -c "git add feed.xml audio/the-future-economy-ep003-v2.mp3 series/the-future-economy/ engine/prompts/write-episode.md engine/scripts/publish-ep3-v2.sh engine/scripts/republish-ep3-v2.sh Publish-Episode3-Salt.bat Push-Episode3-Salt.bat 2>nul; git status --short"
echo.

echo Step 3: Committing...
"%BASH_EXE%" -c "git commit -m 'Republish: The Future Economy S1E03 -- Salt (rewrite)' -m 'Replaces the original The Frontier (ep003 v1, GUID the-future-economy-ep003) with a new script and audio (GUID the-future-economy-ep003-v2). Old GUID removed from feed.xml so Spotify pulls the v2 as a fresh episode rather than caching the v1.' -m 'Also updates: writer prompt with anti-slop discipline; outline rebuilt as v5 with antagonist planted by Ep 3; continuity files updated; v1 ep3 archived as script-v1.md.'"
echo.

echo Step 4: Pushing to GitHub...
"%BASH_EXE%" -c "git push origin main"
echo.

echo ===============================================================
echo  All done.
echo  Spotify will pick up the new "Salt" episode within an hour.
echo ===============================================================
echo.
pause
