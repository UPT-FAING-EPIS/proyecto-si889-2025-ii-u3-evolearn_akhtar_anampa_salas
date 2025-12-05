<?php
declare(strict_types=1);
require_once 'cors.php';
require_once __DIR__ . '/../includes/bootstrap.php';

if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') { http_response_code(204); exit; }
if ($_SERVER['REQUEST_METHOD'] !== 'GET') jsonResponse(405, ['error' => 'Method not allowed']);

$pdo = getPDO();
$user = requireAuth($pdo);
$userId = (int)$user['id'];

$tema = trim((string)($_GET['tema'] ?? ''));
if ($tema === '') {
    jsonResponse(400, ['error' => 'Missing tema parameter']);
}

$stmt = $pdo->prepare('
    SELECT id, nombre_curso, duracion_horas, url
    FROM user_courses
    WHERE user_id = :user_id AND tema = :tema
    ORDER BY created_at DESC
');
$stmt->execute([
    ':user_id' => $userId,
    ':tema' => $tema,
]);
$courses = $stmt->fetchAll(PDO::FETCH_ASSOC);

// Convertir array keys a snake_case para consistency
$formatted = array_map(fn($c) => [
    'id' => (int)$c['id'],
    'nombre' => $c['nombre_curso'],
    'duracion_horas' => (int)$c['duracion_horas'],
    'url' => $c['url'],
], $courses);

jsonResponse(200, [
    'success' => true,
    'tema' => $tema,
    'courses' => $formatted,
    'count' => count($formatted),
]);
