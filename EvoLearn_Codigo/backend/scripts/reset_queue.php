<?php
declare(strict_types=1);

require_once __DIR__ . '/../includes/db.php';

$pdo = getPDO();

echo "=== RESET COMPLETO DE COLA ===\n\n";
echo "⚠️  ADVERTENCIA: Este script cancelará TODOS los jobs pending/processing.\n";
echo "    Solo jobs completados se mantendrán.\n\n";

// Opción: cancelar todo o solo los viejos
$cancelAll = true; // Cambiar a false para cancelar solo > 30 minutos

if ($cancelAll) {
    echo "Cancelando TODOS los jobs pending y processing...\n";
    
    // Marcar todos los pending y processing como failed
    $stmt = $pdo->prepare("
        UPDATE summary_jobs 
        SET status = 'failed',
            error_message = 'Job cancelado por reset manual del sistema (cuota excedida).'
        WHERE status IN ('pending', 'processing')
    ");
    $stmt->execute();
    $affected = $stmt->rowCount();
    echo "✓ Cancelados: $affected jobs\n";
} else {
    echo "Cancelando jobs pending/processing de más de 30 minutos...\n";
    
    $stmt = $pdo->prepare("
        UPDATE summary_jobs 
        SET status = 'failed',
            error_message = 'Job cancelado por timeout (más de 30 min sin completarse).'
        WHERE status IN ('pending', 'processing')
          AND updated_at < DATE_SUB(NOW(), INTERVAL 30 MINUTE)
    ");
    $stmt->execute();
    $affected = $stmt->rowCount();
    echo "✓ Cancelados: $affected jobs antiguos\n";
}

// Limpiar archivos de processing_queue
echo "\nLimpiando archivos de cola...\n";
$processingDir = __DIR__ . '/../uploads/processing_queue';
if (is_dir($processingDir)) {
    $files = glob($processingDir . '/*.pdf');
    foreach ($files as $file) {
        unlink($file);
    }
    echo "✓ Eliminados: " . count($files) . " archivos PDF de cola\n";
}

echo "\n=== RESUMEN FINAL ===\n\n";
$stmt = $pdo->query("SELECT status, COUNT(*) as count FROM summary_jobs GROUP BY status ORDER BY status");
$statusCounts = $stmt->fetchAll(PDO::FETCH_ASSOC);

foreach ($statusCounts as $row) {
    echo sprintf("%-12s: %d jobs\n", strtoupper($row['status']), $row['count']);
}

echo "\n✅ Reset completado. El sistema está listo para nuevos análisis.\n";
echo "💡 Recuerda: El cron ahora procesa 1 job a la vez para evitar saturar la cuota.\n";
