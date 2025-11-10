@echo off
REM Complete Infrastructure Cleanup Script for Windows
REM This script removes all containers, images, volumes, and networks for MyFinance

echo ==========================================
echo MyFinance Infrastructure - Complete Cleanup
echo ==========================================
echo.
echo WARNING: This will remove:
echo    - All MyFinance containers (including Jenkins)
echo    - All MyFinance Docker images
echo    - All MyFinance volumes (data will be lost)
echo    - MyFinance network
echo.
set /p CONFIRM="Are you sure you want to continue? (yes/no): "

if not "%CONFIRM%"=="yes" (
    echo Cleanup cancelled.
    exit /b 0
)

echo.
echo Starting cleanup...
echo.

REM Stop and remove all MyFinance containers
echo 1. Stopping and removing containers...
for /f "tokens=*" %%i in ('docker ps -a --filter "name=myfinance" --format "{{.Names}}"') do (
    echo    Stopping %%i...
    docker stop %%i 2>nul
    echo    Removing %%i...
    docker rm %%i 2>nul
)

REM Remove blue-green environment containers
for %%e in (blue green) do (
    for %%s in (api client) do (
        echo    Checking myfinance-%%s-%%e...
        docker stop myfinance-%%s-%%e 2>nul
        docker rm myfinance-%%s-%%e 2>nul
    )
)

echo Done - Containers removed
echo.

REM Remove MyFinance images
echo 2. Removing Docker images...
for /f "tokens=*" %%i in ('docker images --format "{{.Repository}}:{{.Tag}}" ^| findstr myfinance') do (
    echo    Removing image: %%i
    docker rmi %%i 2>nul
)

REM Remove ghcr.io images
for /f "tokens=*" %%i in ('docker images --format "{{.Repository}}:{{.Tag}}" ^| findstr ghcr.io/rocsa65/myfinance') do (
    echo    Removing image: %%i
    docker rmi %%i 2>nul
)

echo Done - Images removed
echo.

REM Remove volumes
echo 3. Removing Docker volumes...
for /f "tokens=*" %%i in ('docker volume ls --format "{{.Name}}" ^| findstr /I "myfinance jenkins nginx"') do (
    echo    Removing volume: %%i
    docker volume rm %%i 2>nul
)

REM Remove specific volumes
for %%v in (jenkins_data nginx_config nginx_main_config nginx_logs blue_api_data blue_api_logs green_api_data green_api_logs blue_client_data green_client_data) do (
    echo    Checking volume: %%v
    docker volume rm %%v 2>nul
)

echo Done - Volumes removed
echo.

REM Remove networks
echo 4. Removing Docker networks...
docker network rm myfinance-network 2>nul
docker network rm jenkins-network 2>nul
echo Done - Networks removed
echo.

REM Clean up nginx backup files
echo 5. Cleaning up nginx backup files...
if exist "docker\nginx\blue-green.conf.backup.*" (
    del /q "docker\nginx\blue-green.conf.backup.*"
    echo    Removed nginx backup files
)
echo Done - Backup files cleaned
echo.

REM Clean up log files
echo 6. Cleaning up log files...
if exist "logs\" (
    del /q "logs\*.*" 2>nul
    echo    Cleared logs directory
)
echo Done - Logs cleaned
echo.

REM Clean up current-environment.txt
if exist "current-environment.txt" (
    del /q "current-environment.txt"
    echo    Removed current-environment.txt
)

REM Prune system
echo 7. Pruning Docker system...
docker system prune -f
echo Done - System pruned
echo.

echo ==========================================
echo Done - Cleanup Complete!
echo ==========================================
echo.
echo All MyFinance infrastructure has been removed.
echo.
echo To start fresh:
echo   1. Create the network: docker network create myfinance-network
echo   2. Start Jenkins: cd jenkins\docker ^&^& docker-compose up -d
echo   3. Access Jenkins at: http://localhost:8081
echo   4. Run backend deployment pipeline
echo   5. Run frontend deployment pipeline
echo.
pause
