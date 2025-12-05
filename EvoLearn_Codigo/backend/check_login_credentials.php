<?php
// Verificar credenciales de login
require_once __DIR__ . '/includes/db.php';

echo "╔════════════════════════════════════════════╗\n";
echo "║  VERIFICACIÓN DE CREDENCIALES DE LOGIN      ║\n";
echo "╚════════════════════════════════════════════╝\n\n";

try {
    $pdo = getPDO();
    
    // Obtener todos los usuarios
    $stmt = $pdo->query('SELECT id, email, name, password_hash FROM users');
    $users = $stmt->fetchAll(PDO::FETCH_ASSOC);
    
    echo "Usuarios en la base de datos:\n";
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n";
    
    foreach ($users as $user) {
        echo "\nID: {$user['id']}\n";
        echo "Email: {$user['email']}\n";
        echo "Nombre: {$user['name']}\n";
        echo "Password Hash: " . substr($user['password_hash'], 0, 50) . "...\n";
    }
    
    // Probar con credenciales conocidas
    echo "\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n";
    echo "PRUEBA DE CONTRASEÑA:\n";
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n";
    
    // Según database.sql, el usuario de prueba es:
    // Email: test@example.com
    // Contraseña: 123456
    
    $testEmail = 'ws2022073896@virtual.upt.pe';
    $testPassword = '72943816';
    
    $stmt = $pdo->prepare('SELECT id, password_hash FROM users WHERE email = ?');
    $stmt->execute([$testEmail]);
    $user = $stmt->fetch();
    
    if ($user) {
        echo "\nUsuario encontrado: $testEmail\n";
        $isValid = password_verify($testPassword, $user['password_hash']);
        echo "¿Contraseña '$testPassword' válida?: " . ($isValid ? "✓ SÍ" : "✗ NO") . "\n";
    } else {
        echo "\n✗ Usuario $testEmail NO encontrado\n";
    }
    
} catch (Exception $e) {
    echo "✗ Error: " . $e->getMessage() . "\n";
    exit(1);
}

echo "\n╔════════════════════════════════════════════╗\n";
echo "║  VERIFICACIÓN COMPLETADA                   ║\n";
echo "╚════════════════════════════════════════════╝\n";
