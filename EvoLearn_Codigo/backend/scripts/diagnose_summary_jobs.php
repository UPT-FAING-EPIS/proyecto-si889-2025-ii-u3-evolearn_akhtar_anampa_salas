<?php
/**
 * Script de diagnóstico para inspeccionar la tabla summary_jobs
 * Uso: php diagnose_summary_jobs.php
 */
declare(strict_types=1);

require_once __DIR__ . '/../includes/bootstrap.php';

echo "=== DIAGNOSTICO SUMMARY_JOBS ===\n\n";

try {
    $pdo = getPDO();
    echo "✓ Conexión a BD establecida.\n\n";
    
    // 1. Contar registros por estado
    echo "1. Conteo de jobs por estado:\n";
    $stmt = $pdo->query("SELECT status, COUNT(*) as count FROM summary_jobs GROUP BY status");
    $rows = $stmt->fetchAll(PDO::FETCH_ASSOC);
    if (count($rows) === 0) {
        echo "   ⚠ NO HAY JOBS EN LA TABLA.\n";
    } else {
        foreach ($rows as $row) {
            echo "   - {$row['status']}: {$row['count']}\n";
        }
    }
    
    // 2. Listar últimos 5 jobs
    echo "\n2. Últimos 5 jobs creados:\n";
    $stmt = $pdo->query("SELECT id, user_id, file_rel_path, analysis_type, status, progress, created_at, updated_at FROM summary_jobs ORDER BY id DESC LIMIT 5");
    $jobs = $stmt->fetchAll(PDO::FETCH_ASSOC);
    if (count($jobs) === 0) {
        echo "   ⚠ No hay jobs.\n";
    } else {
        foreach ($jobs as $job) {
            echo "   ID: {$job['id']} | User: {$job['user_id']} | File: {$job['file_rel_path']} | Type: {$job['analysis_type']} | Status: {$job['status']} | Progress: {$job['progress']}%\n";
            echo "      Created: {$job['created_at']} | Updated: {$job['updated_at']}\n";
        }
    }
    
    // 3. Contar usuarios
    echo "\n3. Usuarios en BD:\n";
    $stmt = $pdo->query("SELECT id, name, email FROM users");
    $users = $stmt->fetchAll(PDO::FETCH_ASSOC);
    if (count($users) === 0) {
        echo "   ⚠ No hay usuarios.\n";
    } else {
        foreach ($users as $user) {
            echo "   ID: {$user['id']} | Name: {$user['name']} | Email: {$user['email']}\n";
        }
    }
    
    // 4. Verificar estructura de tabla
    echo "\n4. Estructura de tabla summary_jobs:\n";
    $stmt = $pdo->query("DESCRIBE summary_jobs");
    $cols = $stmt->fetchAll(PDO::FETCH_ASSOC);
    foreach ($cols as $col) {
        echo "   - {$col['Field']}: {$col['Type']} {$col['Null']} {$col['Key']} {$col['Default']}\n";
    }
    
    // 5. Ver logs del API de analyse
    echo "\n5. Últimas líneas del ai.log:\n";
    $logFile = __DIR__ . '/../logs/ai.log';
    if (file_exists($logFile)) {
        $lines = shell_exec("tail -n 10 \"$logFile\"");
        if ($lines) {
            echo "   " . str_replace("\n", "\n   ", trim($lines)) . "\n";
        }
    } else {
        echo "   ⚠ Archivo ai.log no existe.\n";
    }
    
    echo "\n=== FIN DIAGNÓSTICO ===\n";
    
} catch (Throwable $e) {
    echo "✗ Error: " . $e->getMessage() . "\n";
    echo "Trace: " . $e->getTraceAsString() . "\n";
}
