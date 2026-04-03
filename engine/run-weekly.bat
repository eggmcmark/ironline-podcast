@echo off
REM Ironline Podcast Engine — Weekly Episode Generation
REM Runs every Thursday at 3:00 AM via Windows Task Scheduler

cd /d "C:\Users\mark\CODE\ironline-podcast"

REM Run the orchestrator via Git Bash
"C:\Program Files\Git\bin\bash.exe" -l -c "cd /c/Users/mark/CODE/ironline-podcast && ./engine/orchestrate.sh the-future-economy" >> "C:\Users\mark\CODE\ironline-podcast\engine\logs\scheduled_run.log" 2>&1
