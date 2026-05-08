@echo off
REM Double-click this file to regenerate Episode 3 audio and publish to Spotify.
REM
REM What it does:
REM   1. Generates the new "Salt" audio with ElevenLabs (~5-10 minutes)
REM   2. Copies it into audio/ as the-future-economy-ep003-v2.mp3
REM   3. Removes the old ep003 entry from feed.xml
REM   4. Inserts the new ep003-v2 entry at the top of the feed
REM   5. Commits everything and pushes to GitHub
REM
REM Spotify will pick up the new episode within an hour after the push completes.

REM Locate Git Bash on Windows.
set "BASH_EXE=C:\Program Files\Git\bin\bash.exe"
if not exist "%BASH_EXE%" set "BASH_EXE=C:\Program Files (x86)\Git\bin\bash.exe"
if not exist "%BASH_EXE%" set "BASH_EXE=%LOCALAPPDATA%\Programs\Git\bin\bash.exe"

if not exist "%BASH_EXE%" (
    echo ERROR: Could not find Git Bash on this machine.
    echo Looked in:
    echo   C:\Program Files\Git\bin\bash.exe
    echo   C:\Program Files ^(x86^)\Git\bin\bash.exe
    echo   %LOCALAPPDATA%\Programs\Git\bin\bash.exe
    echo.
    echo Please install Git for Windows from https://git-scm.com/download/win
    pause
    exit /b 1
)

cd /d "%~dp0"

echo ===============================================================
echo  Publishing Episode 3 v2 -- "Salt"
echo ===============================================================
echo.
echo This will take about 5-10 minutes (most of it is ElevenLabs
echo generating the audio). Leave this window open until it finishes.
echo.

"%BASH_EXE%" engine/scripts/publish-ep3-v2.sh

echo.
echo ===============================================================
echo  All done. Check feed.xml and audio/the-future-economy-ep003-v2.mp3
echo ===============================================================
echo.
pause
