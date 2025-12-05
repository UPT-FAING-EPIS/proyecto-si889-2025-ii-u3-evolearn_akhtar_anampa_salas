<?php
declare(strict_types=1);

require_once __DIR__ . '/../includes/db.php';

$pdo = getPDO();

echo "=== RESUMEN DE JOBS ===\n\n";

// Contar por estado
$stmt = $pdo->query("SELECT status, COUNT(*) as count FROM summary_jobs GROUP BY status");
$statusCounts = $stmt->fetchAll(PDO::FETCH_ASSOC);

foreach ($statusCounts as $row) {
    echo sprintf("%-12s: %d jobs\n", strtoupper($row['status']), $row['count']);
}

echo "\n=== JOBS PENDIENTES/PROCESANDO (últimos 10) ===\n\n";

// Ver jobs pending/processing
$stmt = $pdo->query("
    SELECT id, user_id, status, progress, error_message, created_at, updated_at 
    FROM summary_jobs 
    WHERE status IN ('pending', 'processing') 
    ORDER BY created_at 
    LIMIT 10
");
$jobs = $stmt->fetchAll(PDO::FETCH_ASSOC);

foreach ($jobs as $job) {
    echo sprintf(
        "Job #%d | User: %d | Status: %s | Progress: %d%% | Error: %s | Created: %s | Updated: %s\n",
        $job['id'],
        $job['user_id'],
        $job['status'],
        $job['progress'],
        $job['error_message'] ?: 'None',
        $job['created_at'],
        $job['updated_at']
    );
}

echo "\n=== OPCIONES ===\n";
echo "Para limpiar jobs antiguos pendientes con rate limit:\n";
echo "  php scripts/clean_old_pending.php\n\n";
