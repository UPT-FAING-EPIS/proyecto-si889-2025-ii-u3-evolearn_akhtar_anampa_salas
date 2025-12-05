<?php
declare(strict_types=1);
require_once 'cors.php';
require_once __DIR__ . '/../includes/bootstrap.php';
require_once __DIR__ . '/../includes/ai.php';

if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') { http_response_code(204); exit; }
if ($_SERVER['REQUEST_METHOD'] !== 'POST') jsonResponse(405, ['error' => 'Method not allowed']);

// Allow a bit more time when contacting external AI services
@set_time_limit(60);

$pdo = getPDO();
$user = requireAuth($pdo);

$raw = file_get_contents('php://input');
$data = json_decode($raw, true);
if (!is_array($data)) { $data = $_POST; }

$tema = trim((string)($data['tema'] ?? ''));
$summary = trim((string)($data['summary_text'] ?? ''));
if ($tema === '') {
    $tema = extract_tema_central($summary);
}
if ($tema === '') {
    jsonResponse(400, ['error' => 'No se pudo determinar el tema central']);
}

$resp = getCursosGratuitos($tema);
// getCursosGratuitos() ya devuelve array de cursos parseados
$items = $resp;
if (!is_array($items) || empty($items)) {
    jsonResponse(502, ['error' => 'No se encontraron cursos disponibles']);
}

jsonResponse(200, [
    'success' => true,
    'tema_central' => $tema,
    'courses' => $items,
]);