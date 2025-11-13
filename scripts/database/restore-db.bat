@echo off
setlocal enabledelayedexpansion

REM =============================================================================
REM MyFinance Database Restore Script (Windows)
REM =============================================================================
REM Restores the shared SQLite database from a backup file
REM 
REM Usage:
REM   scripts\database\restore-db.bat <backup-file>
REM
REM Description:
REM   - Restores database to both blue and green environments
REM   - Creates safety backup before restore
REM   - Verifies restore integrity
REM   - Requires manual confirmation before proceeding
REM =============================================================================

REM Configuration
set DB_FILE=myfinance.db
set SAFETY_BACKUP_DIR=backups\safety

echo ==================================================
echo    MyFinance Database Restore
echo ==================================================
echo.

REM Check if backup file is provided
if "%~1"=="" (
    echo [ERROR] Backup file not specified
    echo.
    echo Usage: %~nx0 ^<backup-file^>
    echo.
    echo Available backups:
    dir /b backups\myfinance-*.db 2>nul
    exit /b 1
)

set BACKUP_FILE=%~1

REM Verify backup file exists
if not exist "%BACKUP_FILE%" (
    echo [ERROR] Backup file not found: %BACKUP_FILE%
    exit /b 1
)

for %%A in ("%BACKUP_FILE%") do set BACKUP_SIZE=%%~zA
echo Backup file: %BACKUP_FILE%
echo Size: %BACKUP_SIZE% bytes
echo.

REM Find running containers
set BLUE_RUNNING=false
set GREEN_RUNNING=false

docker ps --format "{{.Names}}" | findstr /C:"myfinance-api-blue" >nul 2>&1
if !errorlevel! equ 0 set BLUE_RUNNING=true

docker ps --format "{{.Names}}" | findstr /C:"myfinance-api-green" >nul 2>&1
if !errorlevel! equ 0 set GREEN_RUNNING=true

if "%BLUE_RUNNING%"=="false" if "%GREEN_RUNNING%"=="false" (
    echo [ERROR] No running MyFinance API container found
    echo Please ensure at least one environment ^(blue or green^) is running
    exit /b 1
)

echo Running containers:
if "%BLUE_RUNNING%"=="true" echo   - Blue ^(myfinance-api-blue^)
if "%GREEN_RUNNING%"=="true" echo   - Green ^(myfinance-api-green^)
echo.

REM Warning and confirmation
echo WARNING: This will replace the current database with the backup
echo          Both blue and green environments will be affected
echo.
set /p CONFIRM="Do you want to continue? (yes/no): "
if /i not "%CONFIRM%"=="yes" (
    echo Restore cancelled
    exit /b 0
)
echo.

REM Create safety backup directory
if not exist "%SAFETY_BACKUP_DIR%" mkdir "%SAFETY_BACKUP_DIR%"

REM Create safety backup from current database
for /f "tokens=2-4 delims=/ " %%a in ('date /t') do (set MYDATE=%%c%%a%%b)
for /f "tokens=1-2 delims=/:" %%a in ('time /t') do (set MYTIME=%%a%%b)
set MYTIME=%MYTIME: =0%
set SAFETY_TIMESTAMP=%MYDATE%-%MYTIME%
set SAFETY_BACKUP=%SAFETY_BACKUP_DIR%\pre-restore-%SAFETY_TIMESTAMP%.db

echo Creating safety backup of current database...
if "%GREEN_RUNNING%"=="true" (
    set CONTAINER=myfinance-api-green
) else (
    set CONTAINER=myfinance-api-blue
)

docker cp "!CONTAINER!:/data/%DB_FILE%" "%SAFETY_BACKUP%" >nul 2>&1
if !errorlevel! equ 0 (
    echo [OK] Safety backup created: %SAFETY_BACKUP%
) else (
    echo [WARNING] Could not create safety backup
    set /p CONFIRM2="Continue anyway? (yes/no): "
    if /i not "!CONFIRM2!"=="yes" (
        echo Restore cancelled
        exit /b 0
    )
)

echo.
echo Restoring database...

REM Restore to running containers
set RESTORE_SUCCESS=false

if "%BLUE_RUNNING%"=="true" (
    echo Restoring to blue environment...
    docker cp "%BACKUP_FILE%" "myfinance-api-blue:/data/%DB_FILE%"
    if !errorlevel! equ 0 (
        echo [OK] Blue environment restored
        set RESTORE_SUCCESS=true
    ) else (
        echo [ERROR] Failed to restore blue environment
    )
)

if "%GREEN_RUNNING%"=="true" (
    echo Restoring to green environment...
    docker cp "%BACKUP_FILE%" "myfinance-api-green:/data/%DB_FILE%"
    if !errorlevel! equ 0 (
        echo [OK] Green environment restored
        set RESTORE_SUCCESS=true
    ) else (
        echo [ERROR] Failed to restore green environment
    )
)

if "%RESTORE_SUCCESS%"=="false" (
    echo [ERROR] Restore failed
    exit /b 1
)

REM Restart containers to reload database connection
echo.
echo Restarting containers to apply changes...

if "%BLUE_RUNNING%"=="true" (
    docker restart myfinance-api-blue >nul
    echo [OK] Blue container restarted
)

if "%GREEN_RUNNING%"=="true" (
    docker restart myfinance-api-green >nul
    echo [OK] Green container restarted
)

REM Summary
echo.
echo ==================================================
echo Restore completed successfully!
echo ==================================================
echo Restored from: %BACKUP_FILE%
echo Safety backup: %SAFETY_BACKUP%
echo.
echo Database has been restored and containers restarted
echo.

endlocal
