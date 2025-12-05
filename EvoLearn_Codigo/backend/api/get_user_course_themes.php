<?php
declare(strict_types=1);
require_once 'cors.php';
require_once __DIR__ . '/../includes/bootstrap.php';

if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') { http_response_code(204); exit; }
if ($_SERVER['REQUEST_METHOD'] !== 'GET') jsonResponse(405, ['error' => 'Method not allowed']);

$pdo = getPDO();
$user = requireAuth($pdo);
$userId = (int)$user['id'];

// Obtener todos los temas únicos del usuario
$stmt = $pdo->prepare('
    SELECT DISTINCT tema
    FROM user_courses
    WHERE user_id = :user_id
    ORDER BY tema ASC
');
$stmt->execute([':user_id' => $userId]);
$themes = $stmt->fetchAll(PDO::FETCH_ASSOC);

$temas = array_map(fn($row) => $row['tema'], $themes);

jsonResponse(200, [
    'success' => true,
    'temas' => $temas,
    'count' => count($temas),
]);
