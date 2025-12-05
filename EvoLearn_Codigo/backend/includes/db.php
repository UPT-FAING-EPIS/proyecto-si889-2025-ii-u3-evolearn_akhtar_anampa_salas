<?php
declare(strict_types=1);

function getPDO(): PDO {
    // Ajustar estos valores a tu entorno local
    $host = '161.132.49.24';
    $db   = 'estudiafacil';
    $user = 'php_user';
    $pass = 'psswdphp8877'; // Cambia si tu MySQL tiene contraseña
    $port = 3306;
    $charset = 'utf8mb4';

    $dsn = "mysql:host=$host;port=$port;dbname=$db;charset=$charset";
    $options = [
        PDO::ATTR_ERRMODE            => PDO::ERRMODE_EXCEPTION,
        PDO::ATTR_DEFAULT_FETCH_MODE => PDO::FETCH_ASSOC,
        PDO::ATTR_EMULATE_PREPARES   => false,
        PDO::ATTR_TIMEOUT            => 300,
        PDO::MYSQL_ATTR_INIT_COMMAND => "SET SESSION wait_timeout=300, net_write_timeout=300, net_read_timeout=300",
    ];

    return new PDO($dsn, $user, $pass, $options);
}

function jsonResponse(int $status, array $payload): void {
    http_response_code($status);
    header('Content-Type: application/json; charset=utf-8');
    header('Cache-Control: no-cache, must-revalidate');
    header('Pragma: no-cache');
    
    // Encode JSON
    $json = json_encode($payload, JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES);
    
    // Get size
    $size = strlen($json);
    
    // Set Content-Length
    header('Content-Length: ' . $size);
    
    // Close output buffering if active and send
    while (ob_get_level() > 0) {
        ob_end_clean();
    }
    
    echo $json;
    flush();
    exit;
}