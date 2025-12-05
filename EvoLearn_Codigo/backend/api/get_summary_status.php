<?php
declare(strict_types=1);
require_once 'cors.php';
require_once __DIR__ . '/../includes/bootstrap.php';

if ($_SERVER['REQUEST_METHOD'] !== 'GET') {
    jsonResponse(405, ['error' => 'Method not allowed']);
}

$pdo = getPDO();
$user = requireAuth($pdo);

$jobId = filter_input(INPUT_GET, 'job_id', FILTER_VALIDATE_INT);
if (!$jobId) {
    jsonResponse(400, ['error' => 'Se requiere un job_id válido.']);
}

try {
    $stmt = $pdo->prepare(
        'SELECT id, status, progress, summary_text, error_message, updated_at 
         FROM summary_jobs 
         WHERE id = ? AND user_id = ?'
    );
    $stmt->execute([$jobId, $user['id']]);
    $job = $stmt->fetch(PDO::FETCH_ASSOC);

    if (!$job) {
        jsonResponse(404, ['error' => 'Tarea no encontrada o no autorizada.']);
    }

    // Convertir tipos para la respuesta JSON
    $job['id'] = (int)$job['id'];
    $job['progress'] = (float)($job['progress'] ?? 0.0);

    jsonResponse(200, ['job' => $job]);

} catch (Throwable $e) {
    log_error('Failed to get summary job status', ['error' => $e->getMessage(), 'job_id' => $jobId]);
    jsonResponse(500, ['error' => 'Error interno del servidor al consultar la tarea.']);
}
