@echo off
setlocal enabledelayedexpansion

REM =============================================================================
REM MyFinance Database Backup Script (Windows)
REM =============================================================================
REM Creates a timestamped backup of the shared SQLite database
REM 
REM Usage:
REM   scripts\database\backup-db.bat
REM
REM Description:
REM   - Backs up the shared database file (myfinance.db) used by both blue and green environments
REM   - Creates timestamped backup in backups\ directory
REM   - Verifies backup integrity
REM   - Retains last 10 backups automatically
REM =============================================================================

REM Configuration
set BACKUP_DIR=backups
set DB_FILE=myfinance.db
for /f "tokens=2-4 delims=/ " %%a in ('date /t') do (set MYDATE=%%c%%a%%b)
for /f "tokens=1-2 delims=/:" %%a in ('time /t') do (set MYTIME=%%a%%b)
set MYTIME=%MYTIME: =0%
set TIMESTAMP=%MYDATE%-%MYTIME%
set BACKUP_FILE=%BACKUP_DIR%\myfinance-%TIMESTAMP%.db
set KEEP_BACKUPS=10

echo ==================================================
echo    MyFinance Database Backup
echo ==================================================
echo.

REM Create backup directory if it doesn't exist
if not exist "%BACKUP_DIR%" mkdir "%BACKUP_DIR%"

REM Find running container (try green first, then blue)
set CONTAINER_NAME=
docker ps --format "{{.Names}}" | findstr /C:"myfinance-api-green" >nul 2>&1
if !errorlevel! equ 0 (
    set CONTAINER_NAME=myfinance-api-green
) else (
    docker ps --format "{{.Names}}" | findstr /C:"myfinance-api-blue" >nul 2>&1
    if !errorlevel! equ 0 (
        set CONTAINER_NAME=myfinance-api-blue
    )
)

if "%CONTAINER_NAME%"=="" (
    echo [ERROR] No running MyFinance API container found
    echo Please ensure either blue or green environment is running
    exit /b 1
)

echo Using container: %CONTAINER_NAME%
echo.

REM Backup database
echo Backing up database...
docker cp "%CONTAINER_NAME%:/data/%DB_FILE%" "%BACKUP_FILE%"
if !errorlevel! equ 0 (
    echo [OK] Backup created: %BACKUP_FILE%
) else (
    echo [ERROR] Failed to create backup
    exit /b 1
)

REM Verify backup
for %%A in ("%BACKUP_FILE%") do set BACKUP_SIZE=%%~zA
if %BACKUP_SIZE% gtr 0 (
    echo [OK] Backup verified ^(%BACKUP_SIZE% bytes^)
) else (
    echo [ERROR] Backup file is empty or invalid
    exit /b 1
)

REM Cleanup old backups
echo.
echo Cleaning up old backups ^(keeping last %KEEP_BACKUPS%^)...
set COUNT=0
for /f %%F in ('dir /b /o-d "%BACKUP_DIR%\myfinance-*.db" 2^>nul') do (
    set /a COUNT+=1
    if !COUNT! gtr %KEEP_BACKUPS% (
        del "%BACKUP_DIR%\%%F"
    )
)
if !COUNT! gtr %KEEP_BACKUPS% (
    echo [OK] Old backups cleaned up
) else (
    echo No cleanup needed ^(!COUNT! backups total^)
)

REM Summary
echo.
echo ==================================================
echo Backup completed successfully!
echo ==================================================
echo Backup file: %BACKUP_FILE%
echo Size: %BACKUP_SIZE% bytes

REM Count current backups
set TOTAL=0
for %%F in ("%BACKUP_DIR%\myfinance-*.db") do set /a TOTAL+=1
echo Total backups: %TOTAL%
echo.
echo To restore this backup:
echo   scripts\database\restore-db.bat %BACKUP_FILE%
echo.

endlocal
