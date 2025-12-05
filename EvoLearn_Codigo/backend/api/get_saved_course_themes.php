<?php
declare(strict_types=1);
require_once 'cors.php';
require_once __DIR__ . '/../includes/bootstrap.php';

if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') { http_response_code(204); exit; }
if ($_SERVER['REQUEST_METHOD'] !== 'GET') jsonResponse(405, ['error' => 'Method not allowed']);

$pdo = getPDO();
$user = requireAuth($pdo);
$userId = (int)$user['id'];

// Get unique themes from saved courses for this user
$stmt = $pdo->prepare('
    SELECT DISTINCT tema 
    FROM user_courses 
    WHERE user_id = ? 
    AND tema IS NOT NULL 
    AND tema != ""
    ORDER BY tema ASC
');
$stmt->execute([$userId]);
$themes = $stmt->fetchAll(PDO::FETCH_COLUMN);

jsonResponse(200, [
    'success' => true,
    'themes' => $themes,
    'count' => count($themes),
]);
