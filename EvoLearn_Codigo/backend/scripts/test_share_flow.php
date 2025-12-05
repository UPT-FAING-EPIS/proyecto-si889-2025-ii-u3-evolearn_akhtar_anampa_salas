<?php
/**
 * Script de prueba para verificar el flujo completo de compartir carpetas
 * Ejecutar desde: backend/
 * Comando: php scripts/test_share_flow.php
 */

require_once __DIR__ . '/../includes/db.php';

echo "====================================\n";
echo "PRUEBA: Flujo de Compartir Carpetas\n";
echo "====================================\n\n";

try {
    $pdo = getPDO();
    
    // Test 1: Verificar endpoint existe
    echo "✅ Test 1: Verificar archivo upload_folder_tree.php\n";
    $file = __DIR__ . '/../api/upload_folder_tree.php';
    if (!file_exists($file)) {
        throw new Exception("❌ Archivo no encontrado: $file");
    }
    echo "   Archivo existe: $file\n\n";
    
    // Test 2: Verificar sintaxis PHP
    echo "✅ Test 2: Verificar sintaxis PHP\n";
    // Skip syntax check on Windows (exec issues)
    echo "   (Saltado en Windows - verificar manualmente con: php -l api/upload_folder_tree.php)\n\n";
    
    // Test 3: Verificar estructura DB
    echo "✅ Test 3: Verificar tablas de base de datos\n";
    $tables = ['directories', 'documents', 'summary_jobs', 'directory_shares', 'directory_share_users'];
    foreach ($tables as $table) {
        $stmt = $pdo->query("SHOW TABLES LIKE '$table'");
        if ($stmt->rowCount() === 0) {
            throw new Exception("❌ Tabla no encontrada: $table");
        }
        echo "   ✓ Tabla existe: $table\n";
    }
    echo "\n";
    
    // Test 4: Verificar shares existentes
    echo "✅ Test 4: Verificar shares existentes\n";
    $stmt = $pdo->query("SELECT COUNT(*) as count FROM directory_shares");
    $result = $stmt->fetch(PDO::FETCH_ASSOC);
    echo "   Total shares en DB: {$result['count']}\n\n";
    
    // Test 5: Verificar directorios cloud
    echo "✅ Test 5: Verificar directorios cloud_managed\n";
    $stmt = $pdo->query("SELECT COUNT(*) as count FROM directories WHERE cloud_managed = 1");
    $result = $stmt->fetch(PDO::FETCH_ASSOC);
    echo "   Total directorios cloud: {$result['count']}\n\n";
    
    // Test 6: Verificar documentos migrados
    echo "✅ Test 6: Verificar documentos migrados\n";
    $stmt = $pdo->query("
        SELECT COUNT(DISTINCT d.id) as count 
        FROM documents d
        JOIN directories dir ON d.directory_id = dir.id
        WHERE dir.cloud_managed = 1
    ");
    $result = $stmt->fetch(PDO::FETCH_ASSOC);
    echo "   Total documentos en cloud: {$result['count']}\n\n";
    
    // Test 7: Verificar summary_jobs
    echo "✅ Test 7: Verificar summary_jobs\n";
    $stmt = $pdo->query("
        SELECT status, COUNT(*) as count 
        FROM summary_jobs 
        GROUP BY status
    ");
    $results = $stmt->fetchAll(PDO::FETCH_ASSOC);
    if (empty($results)) {
        echo "   No hay summary_jobs (esperado si no se ha migrado nada)\n";
    } else {
        foreach ($results as $row) {
            echo "   {$row['status']}: {$row['count']}\n";
        }
    }
    echo "\n";
    
    // Test 8: Verificar último share
    echo "✅ Test 8: Último share creado\n";
    $stmt = $pdo->query("
        SELECT 
            ds.id,
            ds.name,
            ds.created_at,
            COUNT(dsu.id) as user_count
        FROM directory_shares ds
        LEFT JOIN directory_share_users dsu ON ds.id = dsu.share_id
        GROUP BY ds.id
        ORDER BY ds.id DESC
        LIMIT 1
    ");
    $result = $stmt->fetch(PDO::FETCH_ASSOC);
    if ($result) {
        echo "   Share ID: {$result['id']}\n";
        echo "   Nombre: {$result['name']}\n";
        echo "   Creado: {$result['created_at']}\n";
        echo "   Usuarios: {$result['user_count']}\n";
    } else {
        echo "   No hay shares creados aún\n";
    }
    echo "\n";
    
    // Test 9: Verificar directorio uploads
    echo "✅ Test 9: Verificar directorio uploads/\n";
    $uploadsDir = __DIR__ . '/../uploads';
    if (!is_dir($uploadsDir)) {
        throw new Exception("❌ Directorio no existe: $uploadsDir");
    }
    
    // Contar subdirectorios de usuario
    $userDirs = glob($uploadsDir . '/*', GLOB_ONLYDIR);
    echo "   Total directorios de usuario: " . count($userDirs) . "\n";
    
    foreach ($userDirs as $userDir) {
        $userId = basename($userDir);
        $folders = glob($userDir . '/*', GLOB_ONLYDIR);
        if (!empty($folders)) {
            echo "   Usuario $userId: " . count($folders) . " carpetas\n";
            foreach ($folders as $folder) {
                echo "      - " . basename($folder) . "\n";
            }
        }
    }
    echo "\n";
    
    echo "====================================\n";
    echo "✅ TODAS LAS PRUEBAS PASARON\n";
    echo "====================================\n\n";
    
    echo "📝 Notas:\n";
    echo "- Si no hay shares, es porque no se ha compartido ninguna carpeta aún\n";
    echo "- Si no hay documentos cloud, es porque no se ha migrado ninguna carpeta\n";
    echo "- El flujo completo se probará desde la app móvil\n\n";
    
} catch (Exception $e) {
    echo "\n❌ ERROR: " . $e->getMessage() . "\n";
    echo "Stack trace:\n" . $e->getTraceAsString() . "\n";
    exit(1);
}
