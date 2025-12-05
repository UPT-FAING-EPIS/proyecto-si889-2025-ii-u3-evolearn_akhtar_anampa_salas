<?php
declare(strict_types=1);

require_once __DIR__ . '/../includes/db.php';

$pdo = getPDO();

echo "=== LIMPIEZA DE JOBS ANTIGUOS CON RATE LIMIT ===\n\n";

// Marcar como failed los jobs pending con rate limit de más de 1 hora
$stmt = $pdo->prepare("
    UPDATE summary_jobs 
    SET status = 'failed', 
        error_message = 'Job cancelado por exceder límite de cuota de IA. Intenta de nuevo más tarde.' 
    WHERE status = 'pending' 
      AND error_message LIKE '%rate limit%' 
      AND updated_at < DATE_SUB(NOW(), INTERVAL 1 HOUR)
");
$stmt->execute();
$affected = $stmt->rowCount();

echo "✓ Marcados como 'failed': $affected jobs antiguos con rate limit\n";

// Eliminar archivos huérfanos en processing_queue
$processingDir = __DIR__ . '/../uploads/processing_queue';
$files = glob($processingDir . '/*.pdf');
$cleaned = 0;

foreach ($files as $file) {
    $filename = basename($file);
    $stmt = $pdo->prepare("SELECT id FROM summary_jobs WHERE file_path LIKE ?");
    $stmt->execute(['%' . $filename]);
    
    if (!$stmt->fetch()) {
        unlink($file);
        $cleaned++;
    }
}

echo "✓ Eliminados: $cleaned archivos huérfanos de processing_queue\n\n";

echo "=== RESUMEN ACTUAL ===\n\n";
$stmt = $pdo->query("SELECT status, COUNT(*) as count FROM summary_jobs GROUP BY status");
$statusCounts = $stmt->fetchAll(PDO::FETCH_ASSOC);

foreach ($statusCounts as $row) {
    echo sprintf("%-12s: %d jobs\n", strtoupper($row['status']), $row['count']);
}

echo "\n✅ Limpieza completada\n";
