<?php
declare(strict_types=1);
require_once 'cors.php';
require_once __DIR__ . '/../includes/bootstrap.php';

if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') { http_response_code(204); exit; }
if ($_SERVER['REQUEST_METHOD'] !== 'POST') jsonResponse(405, ['error' => 'Method not allowed']);

$pdo = getPDO();
$user = requireAuth($pdo);
$userId = (int)$user['id'];

$raw = file_get_contents('php://input');
$data = json_decode($raw, true);
if (!is_array($data)) { $data = $_POST; }

$tema = trim((string)($data['tema'] ?? ''));
$courses = $data['courses'] ?? [];

if ($tema === '' || !is_array($courses) || empty($courses)) {
    jsonResponse(400, ['error' => 'Missing tema or courses']);
}

$pdo->beginTransaction();

try {
    $stmt = $pdo->prepare('
        INSERT INTO user_courses (user_id, tema, nombre_curso, duracion_horas, url)
        VALUES (:user_id, :tema, :nombre, :duracion, :url)
        ON DUPLICATE KEY UPDATE created_at = CURRENT_TIMESTAMP
    ');
    
    $saved = 0;
    foreach ($courses as $course) {
        if (!is_array($course)) continue;
        
        $nombre = trim((string)($course['nombre'] ?? $course['name'] ?? ''));
        $duracion = (int)($course['duracion_horas'] ?? $course['duration_hours'] ?? 0);
        $url = trim((string)($course['url'] ?? ''));
        
        if ($nombre === '' || $url === '') continue;
        
        $stmt->execute([
            ':user_id' => $userId,
            ':tema' => $tema,
            ':nombre' => $nombre,
            ':duracion' => $duracion,
            ':url' => $url,
        ]);
        
        $saved++;
    }
    
    $pdo->commit();
    
    jsonResponse(200, [
        'success' => true,
        'saved' => $saved,
        'tema' => $tema,
    ]);
    
} catch (Exception $e) {
    $pdo->rollBack();
    log_error('Error saving courses', ['error' => $e->getMessage(), 'user_id' => $userId]);
    jsonResponse(500, ['error' => 'Error saving courses']);
}
