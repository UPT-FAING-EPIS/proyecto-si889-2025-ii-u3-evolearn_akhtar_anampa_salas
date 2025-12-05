@echo off
REM Script para instalar Task Scheduler en Windows
REM Ejecutar como administrador

setlocal enabledelayedexpansion

set TASK_NAME=EvoLearn_ProcessSummaries
set PHP_PATH=php
set SCRIPT_PATH=C:\Users\USUARIO\Documents\walter\PATRONES\EvoLearn_Patrones\backend\cron\process_summaries.php
set BACKEND_PATH=C:\Users\USUARIO\Documents\walter\PATRONES\EvoLearn_Patrones\backend

REM Eliminar tarea si existe
tasklist /FI "TASKNAME eq %TASK_NAME%" 2>NUL | find /I /N "%TASK_NAME%">NUL
if "%ERRORLEVEL%"=="0" (
    echo Eliminando tarea existente: %TASK_NAME%
    schtasks /delete /tn "%TASK_NAME%" /f >NUL 2>&1
)

REM Crear tarea que se ejecute cada minuto
echo Creando tarea programada: %TASK_NAME%
schtasks /create /tn "%TASK_NAME%" /tr "%PHP_PATH% %SCRIPT_PATH%" /sc minute /mo 1 /f /ru SYSTEM

if %ERRORLEVEL% EQU 0 (
    echo.
    echo ====================================
    echo Tarea instalada exitosamente!
    echo ====================================
    echo Nombre: %TASK_NAME%
    echo Frecuencia: Cada 1 minuto
    echo Script: %SCRIPT_PATH%
    echo.
    echo La tarea se ejecutara automaticamente cada minuto
    echo.
) else (
    echo Error al crear la tarea
    exit /b 1
)

pause
