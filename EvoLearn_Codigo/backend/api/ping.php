<?php
// SIMPLE PING ENDPOINT - NO AUTH REQUIRED
header('Content-Type: application/json');

$response = [
    'success' => true,
    'message' => 'Ping OK from backend',
    'timestamp' => date('Y-m-d H:i:s'),
    'server_time' => time(),
    'php_version' => PHP_VERSION,
];

http_response_code(200);
echo json_encode($response);
?>
