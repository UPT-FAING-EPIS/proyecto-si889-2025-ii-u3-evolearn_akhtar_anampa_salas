<?php
declare(strict_types=1);
require_once 'cors.php';
require_once __DIR__ . '/../includes/bootstrap.php';
require_once __DIR__ . '/../includes/ai.php';

if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') { http_response_code(204); exit; }
if ($_SERVER['REQUEST_METHOD'] !== 'POST') jsonResponse(405, ['error' => 'Method not allowed']);

@set_time_limit(60);

$pdo = getPDO();
$user = requireAuth($pdo);
$user_id = $user['id'];

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

// 1. PRIMERO: Intentar cargar cursos guardados desde BD
$sql = 'SELECT id, nombre_curso, duracion_horas, url FROM user_courses WHERE user_id = ? AND tema = ? LIMIT 10';
$stmt = $pdo->prepare($sql);
$stmt->execute([$user_id, $tema]);
$savedCourses = $stmt->fetchAll(PDO::FETCH_ASSOC);

// Formatear cursos guardados para que coincidan con estructura de generados
$formattedSaved = [];
foreach ($savedCourses as $c) {
    $formattedSaved[] = [
        'id' => (int)$c['id'],
        'nombre' => $c['nombre_curso'],
        'duracion_horas' => (int)$c['duracion_horas'],
        'url' => $c['url'],
    ];
}

if (!empty($formattedSaved)) {
    // Cursos encontrados en BD - devolver directamente sin generar
    log_info('Returning saved courses', [
        'tema' => $tema,
        'count' => count($formattedSaved),
    ]);
    
    jsonResponse(200, [
        'success' => true,
        'tema_central' => $tema,
        'courses' => $formattedSaved,
        'source' => 'database',
    ]);
}

// 2. Si no hay guardados, generar nuevos con Gemini
log_info('No saved courses found, generating new ones', ['tema' => $tema]);

$resp = getCursosGratuitos($tema);
$items = $resp;

if (!is_array($items) || empty($items)) {
    // No hay cursos disponibles ni en BD ni generados
    jsonResponse(200, [
        'success' => true,
        'tema_central' => $tema,
        'courses' => [],
        'source' => 'none',
        'message' => 'No se encontraron cursos disponibles para este tema',
    ]);
}

// 3. Guardar los cursos generados en BD y obtener sus IDs
$generatedWithIds = [];
foreach ($items as $course) {
    $insert_sql = '
        INSERT INTO user_courses (user_id, tema, nombre_curso, duracion_horas, url)
        VALUES (?, ?, ?, ?, ?)
        ON DUPLICATE KEY UPDATE duracion_horas = VALUES(duracion_horas), url = VALUES(url)
    ';
    $insert_stmt = $pdo->prepare($insert_sql);
    $insert_stmt->execute([
        $user_id,
        $tema,
        $course['nombre'] ?? '',
        $course['duracion_horas'] ?? 0,
        $course['url'] ?? '',
    ]);
    
    // Obtener el ID del curso insertado
    $lastId = $pdo->lastInsertId();
    if ($lastId && $lastId !== '0') {
        $course['id'] = (int)$lastId;
    } else {
        // Si es un UPDATE (DUPLICATE KEY), buscar el ID existente
        $sel_sql = 'SELECT id FROM user_courses WHERE user_id = ? AND tema = ? AND nombre_curso = ? LIMIT 1';
        $sel_stmt = $pdo->prepare($sel_sql);
        $sel_stmt->execute([$user_id, $tema, $course['nombre'] ?? '']);
        $existing = $sel_stmt->fetch(PDO::FETCH_ASSOC);
        if ($existing) {
            $course['id'] = (int)$existing['id'];
        }
    }
    
    $generatedWithIds[] = $course;
}

log_info('Courses generated and saved', ['tema' => $tema, 'count' => count($generatedWithIds)]);

jsonResponse(200, [
    'success' => true,
    'tema_central' => $tema,
    'courses' => $generatedWithIds,
    'source' => 'generated',
]);
