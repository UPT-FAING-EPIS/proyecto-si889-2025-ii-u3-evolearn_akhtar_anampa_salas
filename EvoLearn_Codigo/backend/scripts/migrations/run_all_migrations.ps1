# Script PowerShell para ejecutar todas las migraciones SQL en orden
# Uso: .\run_all_migrations.ps1

param(
    [string]$User = "php_user",
    [string]$Database = "estudiafacil",
    [string]$DbHost = "161.132.49.24",
    [string]$DbPort = "3306"
)

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  Ejecutando migraciones SQL" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Base de datos: ${Database}@${DbHost}:${DbPort}" -ForegroundColor Yellow
Write-Host "Usuario: $User" -ForegroundColor Yellow
Write-Host ""

# Obtener contraseña
$Password = Read-Host "Ingresa la contrasena para $User" -AsSecureString
$BSTR = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($Password)
$PlainPassword = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($BSTR)

# Obtener todas las migraciones SQL en orden
$migrations = Get-ChildItem -Path $PSScriptRoot -Filter "*.sql" | Sort-Object Name

if ($migrations.Count -eq 0) {
    Write-Host "No se encontraron migraciones SQL" -ForegroundColor Red
    exit 1
}

Write-Host "Migraciones encontradas: $($migrations.Count)" -ForegroundColor Green
Write-Host ""

$successCount = 0
$failCount = 0

foreach ($migration in $migrations) {
    Write-Host "Ejecutando: $($migration.Name)..." -ForegroundColor Cyan -NoNewline
    
    try {
        # Ejecutar migracion usando mysql client
        $output = Get-Content $migration.FullName | mysql -h $DbHost -P $DbPort -u $User -p$PlainPassword $Database 2>&1
        
        if ($LASTEXITCODE -eq 0) {
            Write-Host " OK" -ForegroundColor Green
            $successCount++
        } else {
            Write-Host " FALLO" -ForegroundColor Red
            Write-Host "  Error: $output" -ForegroundColor Red
            $failCount++
        }
    } catch {
        Write-Host " EXCEPCION" -ForegroundColor Red
        Write-Host "  Error: $($_.Exception.Message)" -ForegroundColor Red
        $failCount++
    }
}

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  Resumen" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Total: $($migrations.Count) migraciones" -ForegroundColor White
Write-Host "Exitosas: $successCount" -ForegroundColor Green
Write-Host "Fallidas: $failCount" -ForegroundColor $(if ($failCount -gt 0) { "Red" } else { "White" })
Write-Host ""

if ($failCount -eq 0) {
    Write-Host "Todas las migraciones se ejecutaron correctamente" -ForegroundColor Green
    exit 0
} else {
    Write-Host "Algunas migraciones fallaron. Revisa los errores arriba." -ForegroundColor Red
    exit 1
}
