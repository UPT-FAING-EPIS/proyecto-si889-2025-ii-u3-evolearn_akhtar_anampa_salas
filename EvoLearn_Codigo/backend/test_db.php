<?php
error_reporting(E_ALL);
ini_set('display_errors', '1');

echo "=== TEST DE CONEXION A BASE DE DATOS ===\n\n";

require_once __DIR__ . '/includes/db.php';

try {
    $pdo = getPDO();
    echo "✓ Conexión exitosa a la base de datos!\n\n";
    
    // Probar una consulta simple
    $stmt = $pdo->query('SELECT COUNT(*) as total FROM users');
    $result = $stmt->fetch();
    echo "✓ Usuarios en la base de datos: " . $result['total'] . "\n";
    
} catch (PDOException $e) {
    echo "✗ Error de conexión PDO:\n";
    echo "  Mensaje: " . $e->getMessage() . "\n";
    echo "  Código: " . $e->getCode() . "\n\n";
    
    echo "POSIBLES SOLUCIONES:\n";
    echo "1. Verifica que el servidor MySQL esté accesible desde tu máquina\n";
    echo "2. Verifica las credenciales en backend/includes/db.php\n";
    echo "3. Verifica que el firewall permita conexiones al puerto 3306\n";
    echo "4. Considera usar una base de datos local para desarrollo\n";
} catch (Exception $e) {
    echo "✗ Error general:\n";
    echo "  " . $e->getMessage() . "\n";
}
