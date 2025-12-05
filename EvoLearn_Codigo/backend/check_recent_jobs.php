<?php
require_once 'includes/db.php';

$pdo = getPDO();

echo "📋 Verificando jobs recientes...\n\n";

// Ver todos los jobs
$query = "SELECT id, user_id, file_rel_path, analysis_type, status, error_message, updated_at
         FROM summary_jobs
         ORDER BY id DESC
         LIMIT 10";

$result = $pdo->query($query);
$jobs = $result->fetchAll(PDO::FETCH_ASSOC);

foreach ($jobs as $job) {
    $status_icon = match($job['status']) {
        'pending' => '⏳',
        'processing' => '⚙️',
        'completed' => '✅',
        'failed' => '❌',
        'canceled' => '⛔',
        default => '?'
    };
    
    echo "$status_icon Job ID {$job['id']}: {$job['analysis_type']}\n";
    echo "  File: {$job['file_rel_path']}\n";
    echo "  Status: {$job['status']}\n";
    if ($job['error_message']) {
        echo "  Error: {$job['error_message']}\n";
    }
    echo "  Updated: {$job['updated_at']}\n\n";
}
?>
