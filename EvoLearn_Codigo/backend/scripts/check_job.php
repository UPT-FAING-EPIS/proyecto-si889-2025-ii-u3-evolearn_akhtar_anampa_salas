<?php
/**
 * Check status and error details of a specific job
 */
declare(strict_types=1);

if ($argc < 2) {
    echo "Usage: php check_job.php <job_id>\n";
    exit(1);
}

$jobId = (int)$argv[1];

require_once __DIR__ . '/../includes/bootstrap.php';

$pdo = getPDO();

$stmt = $pdo->prepare('SELECT * FROM summary_jobs WHERE id = ?');
$stmt->execute([$jobId]);
$job = $stmt->fetch(PDO::FETCH_ASSOC);

if (!$job) {
    echo "Job $jobId not found\n";
    exit(1);
}

echo "=== JOB #$jobId STATUS ===\n\n";
echo "Status: {$job['status']}\n";
echo "Progress: {$job['progress']}%\n";
echo "User ID: {$job['user_id']}\n";
echo "File: {$job['file_rel_path']}\n";
echo "Analysis Type: {$job['analysis_type']}\n";
echo "Model: {$job['model']}\n";
echo "Created: {$job['created_at']}\n";
echo "Updated: {$job['updated_at']}\n";

if ($job['error_message']) {
    echo "\n⚠️ ERROR MESSAGE:\n";
    echo "  {$job['error_message']}\n";
}

if ($job['summary_text']) {
    echo "\n✓ Summary Length: " . strlen($job['summary_text']) . " chars\n";
    echo "Summary Preview (first 200 chars):\n";
    echo substr($job['summary_text'], 0, 200) . "...\n";
}

echo "\n";
