# Script simple para ejecutar migraciones usando el script PHP
# Uso: .\run_all_simple.ps1

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  Ejecutando migraciones SQL" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# Path al script run_migration.php
$runScript = Join-Path $PSScriptRoot "..\run_migration.php"

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
    Write-Host "Ejecutando: $($migration.Name)..." -ForegroundColor Cyan
    
    try {
        # Ejecutar migración
        $output = php $runScript $migration.FullName 2>&1 | Out-String
        
        if ($LASTEXITCODE -eq 0) {
            Write-Host "  OK" -ForegroundColor Green
            if ($output -match "SKIP") {
                Write-Host "  $output" -ForegroundColor Yellow
            }
            $successCount++
        } else {
            Write-Host "  FALLO" -ForegroundColor Red
            Write-Host "$output" -ForegroundColor Red
            $failCount++
        }
    } catch {
        Write-Host "  EXCEPCION" -ForegroundColor Red
        Write-Host "  Error: $($_.Exception.Message)" -ForegroundColor Red
        $failCount++
    }
    
    Write-Host ""
}

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  Resumen" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Total: $($migrations.Count) migraciones" -ForegroundColor White
Write-Host "Exitosas: $successCount" -ForegroundColor Green
Write-Host "Fallidas: $failCount" -ForegroundColor $(if ($failCount -gt 0) { "Red" } else { "White" })
Write-Host ""

if ($failCount -eq 0) {
    Write-Host "Todas las migraciones completadas!" -ForegroundColor Green
    exit 0
} else {
    Write-Host "Algunas migraciones fallaron" -ForegroundColor Red
    exit 1
}
