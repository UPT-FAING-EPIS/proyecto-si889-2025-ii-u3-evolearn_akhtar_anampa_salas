<?php
declare(strict_types=1);

require_once __DIR__ . '/db.php';
require_once __DIR__ . '/logger.php';

function getAuthorizationHeader(): ?string {
    // Prefer server vars exposed by Apache/FastCGI
    foreach ([
        'HTTP_AUTHORIZATION',
        'REDIRECT_HTTP_AUTHORIZATION',
        'Authorization',
        'HTTP_X_AUTH_TOKEN', // Fallback for alternative header name
    ] as $key) {
        if (isset($_SERVER[$key]) && is_string($_SERVER[$key]) && $_SERVER[$key] !== '') {
            $header = trim((string)$_SERVER[$key]);
            
            // If it's X_AUTH_TOKEN (alternative), treat it as Bearer token directly
            if ($key === 'HTTP_X_AUTH_TOKEN') {
                error_log("Authorization token found via HTTP_X_AUTH_TOKEN: " . substr($header, 0, 20) . "...");
                return 'Bearer ' . $header; // Wrap in Bearer format
            }
            
            error_log("Authorization header found in $_SERVER[$key]: " . substr($header, 0, 20) . "...");
            return $header;
        }
    }
    // Fallback: apache_request_headers with case-insensitive lookup
    if (function_exists('apache_request_headers')) {
        $requestHeaders = apache_request_headers();
        if (is_array($requestHeaders)) {
            foreach ($requestHeaders as $k => $v) {
                if (strcasecmp($k, 'Authorization') === 0) {
                    error_log("Authorization header found via apache_request_headers: " . substr($v, 0, 20) . "...");
                    return trim((string)$v);
                } elseif (strcasecmp($k, 'X-Auth-Token') === 0) {
                    error_log("Authorization token found via X-Auth-Token header: " . substr($v, 0, 20) . "...");
                    return 'Bearer ' . trim((string)$v);
                }
            }
        }
    }
    error_log("No Authorization header found. Available SERVER keys: " . implode(', ', array_filter(array_keys($_SERVER), fn($k) => strpos($k, 'HTTP') !== false)));
    return null;
}

function getBearerToken(): ?string {
    $headers = getAuthorizationHeader();
    if (!$headers) {
        // Last resort: check if token is in cookies (some clients might send it there)
        if (!empty($_COOKIE['auth_token'])) {
            error_log("Token found in cookie: " . substr($_COOKIE['auth_token'], 0, 20) . "...");
            return trim($_COOKIE['auth_token']);
        }
        return null;
    }
    
    // Try to extract Bearer token
    if (preg_match('/Bearer\s+(\S+)/i', $headers, $matches)) {
        return $matches[1];
    }
    
    // If no Bearer prefix, treat the whole header as token (for X-Auth-Token fallback)
    if (preg_match('/^[a-f0-9]{64}$/i', $headers)) {
        return $headers;
    }
    
    return null;
}

function issueToken(PDO $pdo, int $userId): string {
    $token = bin2hex(random_bytes(32)); // 64 hex chars
    $expires = (new DateTime('+7 days'))->format('Y-m-d H:i:s');
    $stmt = $pdo->prepare('UPDATE users SET auth_token = ?, token_expires_at = ? WHERE id = ?');
    $stmt->execute([$token, $expires, $userId]);
    return $token;
}

function requireAuth(PDO $pdo, bool $jsonResponse = true): array {
    $token = getBearerToken();
    if (!$token) {
        if ($jsonResponse) {
            jsonResponse(401, ['error' => 'Missing Bearer token']);
        } else {
            http_response_code(401);
            exit('No hay sesión activa');
        }
    }
    $stmt = $pdo->prepare('SELECT id, name, email, token_expires_at FROM users WHERE auth_token = ?');
    $stmt->execute([$token]);
    $user = $stmt->fetch();
    if (!$user) {
        if ($jsonResponse) {
            jsonResponse(401, ['error' => 'Invalid token']);
        } else {
            http_response_code(401);
            exit('Sesión inválida');
        }
    }
    if (!empty($user['token_expires_at']) && (new DateTime() > new DateTime($user['token_expires_at']))) {
        if ($jsonResponse) {
            jsonResponse(401, ['error' => 'Token expired']);
        } else {
            http_response_code(401);
            exit('Sesión expirada');
        }
    }
    logger_set_user((int)$user['id']);
    log_info('Auth OK', ['user_id' => (int)$user['id']]);
    return $user;
}

function isVip(PDO $pdo, array $user): bool {
    // VIP functionality removed - always return false (FS mode only)
    return false;
}