<?php
declare(strict_types=1);
require_once 'cors.php';
require_once __DIR__ . '/../includes/bootstrap.php';

if ($_SERVER['REQUEST_METHOD'] !== 'POST') {
    jsonResponse(405, ['error' => 'Method not allowed']);
}

$pdo = getPDO();
$user = requireAuth($pdo);

$input = json_decode(file_get_contents('php://input'), true);
$jobId = (int)($input['job_id'] ?? 0);
if ($jobId <= 0) {
    jsonResponse(400, ['error' => 'Se requiere un job_id válido.']);
}

try {
    // Verify ownership and current status
    $stmt = $pdo->prepare('SELECT id, status FROM summary_jobs WHERE id = ? AND user_id = ?');
    $stmt->execute([$jobId, $user['id']]);
    $job = $stmt->fetch(PDO::FETCH_ASSOC);

    if (!$job) {
        jsonResponse(404, ['error' => 'Tarea no encontrada o no autorizada.']);
    }

    $status = (string)$job['status'];

    if (in_array($status, ['completed','failed','canceled'], true)) {
        jsonResponse(200, ['success' => true, 'message' => 'La tarea ya no está en ejecución.', 'status' => $status]);
    }

    // Mark as canceled
    $upd = $pdo->prepare("UPDATE summary_jobs SET status = 'canceled', error_message = 'Canceled by user', updated_at = NOW() WHERE id = ? AND user_id = ?");
    $upd->execute([$jobId, $user['id']]);

    jsonResponse(200, ['success' => true, 'message' => 'La tarea fue cancelada.']);

} catch (Throwable $e) {
    log_error('Failed to cancel summary job', ['error' => $e->getMessage(), 'job_id' => $jobId]);
    jsonResponse(500, ['error' => 'Error interno al cancelar la tarea.']);
}
