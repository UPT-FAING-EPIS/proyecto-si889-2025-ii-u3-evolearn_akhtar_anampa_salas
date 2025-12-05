# Script PowerShell para ejecutar migraciones SQL usando PHP
# Uso: .\run_all_migrations_php.ps1

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  Ejecutando migraciones SQL via PHP" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

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
    
    # Crear script PHP temporal para ejecutar la migración
    $phpScript = @"
<?php
require_once __DIR__ . '/../../includes/bootstrap.php';
`$pdo = getPDO();

try {
    `$sql = file_get_contents('$($migration.FullName)');
    
    // Dividir por ; para ejecutar múltiples statements
    `$statements = array_filter(
        array_map('trim', explode(';', `$sql)),
        function(`$s) { return !empty(`$s) && !preg_match('/^--/', `$s); }
    );
    
    `$pdo->beginTransaction();
    
    foreach (`$statements as `$stmt) {
        if (!empty(`$stmt)) {
            `$pdo->exec(`$stmt);
        }
    }
    
    `$pdo->commit();
    echo "SUCCESS";
    exit(0);
} catch (Throwable `$e) {
    if (`$pdo->inTransaction()) {
        `$pdo->rollBack();
    }
    echo "ERROR: " . `$e->getMessage();
    exit(1);
}
"@

    # Guardar script temporal
    $tempPhp = [System.IO.Path]::GetTempFileName() + ".php"
    Set-Content -Path $tempPhp -Value $phpScript -Encoding UTF8
    
    try {
        # Ejecutar con PHP
        $output = php $tempPhp 2>&1
        $exitCode = $LASTEXITCODE
        
        if ($exitCode -eq 0 -and $output -match "SUCCESS") {
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
    } finally {
        # Limpiar archivo temporal
        if (Test-Path $tempPhp) {
            Remove-Item $tempPhp -Force
        }
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
