@echo off
cd /d "C:\Users\USUARIO\Documents\walter\PATRONES\EvoLearn_Patrones\backend"
echo Starting PHP Server...
echo.
echo Local (Windows/Mac): http://127.0.0.1:8003
echo Android Emulator: http://10.0.2.2:8003
echo.
echo Starting on 0.0.0.0:8003 (all interfaces)...
echo.
php -S 0.0.0.0:8003
pause
