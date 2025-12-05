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

$courseId = (int)($data['course_id'] ?? 0);
if ($courseId <= 0) {
    jsonResponse(400, ['error' => 'Missing or invalid course_id']);
}

try {
    // Verify the course belongs to this user before deleting
    $stmt = $pdo->prepare('SELECT user_id FROM user_courses WHERE id = ?');
    $stmt->execute([$courseId]);
    $course = $stmt->fetch(PDO::FETCH_ASSOC);
    
    if (!$course) {
        jsonResponse(404, ['error' => 'Course not found']);
        exit;
    }
    
    if ((int)$course['user_id'] !== $userId) {
        jsonResponse(403, ['error' => 'Unauthorized']);
        exit;
    }
    
    // Delete the course
    $stmt = $pdo->prepare('DELETE FROM user_courses WHERE id = ? AND user_id = ?');
    $stmt->execute([$courseId, $userId]);
    
    jsonResponse(200, [
        'success' => true,
        'message' => 'Course deleted successfully',
    ]);
} catch (Exception $e) {
    log_error('Error deleting course', ['error' => $e->getMessage(), 'user_id' => $userId]);
    jsonResponse(500, ['error' => 'Error deleting course']);
}

