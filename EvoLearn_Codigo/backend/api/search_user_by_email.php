<?php
/**
 * Search user by email
 * GET /api/search_user_by_email.php?email=user@example.com
 */

declare(strict_types=1);
require_once __DIR__ . '/../includes/bootstrap.php';

header('Content-Type: application/json');

$pdo = getPDO();
$currentUser = requireAuth($pdo);

// Validate email parameter
$email = trim($_GET['email'] ?? '');

if (empty($email)) {
    jsonResponse(400, ['error' => 'Email parameter required']);
}

if (!filter_var($email, FILTER_VALIDATE_EMAIL)) {
    jsonResponse(400, ['error' => 'Invalid email format']);
}

try {
    // Search for user by email (exclude current user)
    $stmt = $pdo->prepare('
        SELECT id, name, email, created_at 
        FROM users 
        WHERE email = ? AND id != ?
        LIMIT 1
    ');
    $stmt->execute([$email, $currentUser['id']]);
    $user = $stmt->fetch(PDO::FETCH_ASSOC);
    
    if (!$user) {
        jsonResponse(404, ['error' => 'User not found']);
    }
    
    // Return user info (without sensitive data)
    jsonResponse(200, [
        'ok' => true,
        'user' => [
            'id' => (int)$user['id'],
            'name' => $user['name'],
            'email' => $user['email'],
        ]
    ]);
    
} catch (PDOException $e) {
    log_error('DB error searching user', ['error' => $e->getMessage()]);
    jsonResponse(500, ['error' => 'Database error']);
}
