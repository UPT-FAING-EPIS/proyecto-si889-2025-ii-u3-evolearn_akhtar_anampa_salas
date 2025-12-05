<?php
/**
 * Test script to verify Authorization header is being received
 * Endpoints:
 * - GET /api/test_auth_header.php - Returns headers info
 * - POST /api/test_auth_header.php - Returns headers + parsed body
 */
declare(strict_types=1);
require_once __DIR__ . '/../includes/db.php';
require_once __DIR__ . '/../includes/auth.php';

// Log everything received
$output = [
    'method' => $_SERVER['REQUEST_METHOD'] ?? 'UNKNOWN',
    'content_type' => $_SERVER['CONTENT_TYPE'] ?? 'NONE',
    'php_version' => PHP_VERSION,
    'sapi' => php_sapi_name(),
];

// Check all potential authorization header locations
$output['headers_found'] = [];
foreach (['HTTP_AUTHORIZATION', 'REDIRECT_HTTP_AUTHORIZATION', 'Authorization', 'CONTENT_TYPE', 'HTTP_CONTENT_TYPE'] as $key) {
    if (isset($_SERVER[$key])) {
        $value = (string)$_SERVER[$key];
        if (stripos($key, 'authorization') !== false) {
            // Don't expose full token
            $output['headers_found'][$key] = 'Bearer ' . substr($value, 7, 10) . '... (first 10 chars of token)';
        } else {
            $output['headers_found'][$key] = $value;
        }
    }
}

// Try apache_request_headers
if (function_exists('apache_request_headers')) {
    $output['apache_headers'] = [];
    foreach (apache_request_headers() as $k => $v) {
        if (stripos($k, 'authorization') !== false) {
            $output['apache_headers'][$k] = 'Bearer ' . substr($v, 7, 10) . '... (first 10 chars)';
        }
    }
}

// Log raw input
$raw = @file_get_contents('php://input');
$output['raw_input_length'] = strlen($raw);
if (strlen($raw) > 0) {
    $output['raw_input_preview'] = substr($raw, 0, 150);
    $decoded = json_decode($raw, true);
    if ($decoded) {
        $output['json_parse'] = 'SUCCESS';
        $output['parsed_keys'] = array_keys($decoded);
    } else {
        $output['json_parse'] = 'FAILED - ' . json_last_error_msg();
    }
}

// Try to authenticate if token was sent
$output['auth_test'] = 'NOT ATTEMPTED';
try {
    $pdo = getPDO();
    $token = getBearerToken();
    
    if ($token) {
        $output['auth_test'] = 'Token found, checking DB...';
        $stmt = $pdo->prepare('SELECT id, email, token_expires_at FROM users WHERE auth_token = ? LIMIT 1');
        $stmt->execute([$token]);
        $user = $stmt->fetch(PDO::FETCH_ASSOC);
        
        if ($user) {
            $output['auth_test'] = 'SUCCESS - Token valid for user_id=' . $user['id'] . ' email=' . $user['email'];
            if ($user['token_expires_at']) {
                $expires = new DateTime($user['token_expires_at']);
                $now = new DateTime();
                if ($now > $expires) {
                    $output['auth_test'] .= ' (BUT TOKEN IS EXPIRED)';
                } else {
                    $output['auth_test'] .= ' - expires: ' . $user['token_expires_at'];
                }
            }
        } else {
            $output['auth_test'] = 'FAILED - Token not found in DB';
        }
    } else {
        $output['auth_test'] = 'NO TOKEN FOUND IN HEADERS';
    }
} catch (Throwable $e) {
    $output['auth_test'] = 'ERROR: ' . $e->getMessage();
}

header('Content-Type: application/json');
echo json_encode($output, JSON_PRETTY_PRINT | JSON_UNESCAPED_SLASHES);
?>
