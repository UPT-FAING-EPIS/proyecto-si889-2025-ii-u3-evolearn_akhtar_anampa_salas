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
    $stmt = $pdo->prepare('SELECT * FROM summary_jobs WHERE id = ?');
    $stmt->execute([$jobId]);
    $job = $stmt->fetch(PDO::FETCH_ASSOC);

    if (!$job) {
        jsonResponse(404, ['error' => 'Tarea de análisis no encontrada.']);
    }

    // Asegurarse de que el usuario solo pueda consultar sus propios jobs
    if ((int)$job['user_id'] !== (int)$user['id']) {
        jsonResponse(403, ['error' => 'No tienes permiso para acceder a esta tarea.']);
    }

    $status = $job['status'];
    $response = [
        'job_id' => (int)$job['id'],
        'status' => $status,
    ];

    if ($status === 'completed') {
        $response['summary_text'] = $job['summary_text'];
        // Opcional: una vez completado y consultado, se podría eliminar el job para limpiar la tabla
        // $deleteStmt = $pdo->prepare('DELETE FROM summary_jobs WHERE id = ?');
        // $deleteStmt->execute([$jobId]);
    } elseif ($status === 'failed') {
        $response['error'] = $job['error_message'] ?? 'La tarea de análisis falló sin un mensaje específico.';
    }

    jsonResponse(200, $response);

} catch (Throwable $e) {
    log_error('Failed to fetch summary job', ['job_id' => $jobId, 'error' => $e->getMessage()]);
    jsonResponse(500, ['error' => 'Error interno del servidor al consultar la tarea.']);
}