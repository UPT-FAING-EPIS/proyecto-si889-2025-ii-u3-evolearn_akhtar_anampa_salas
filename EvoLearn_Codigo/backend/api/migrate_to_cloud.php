<?php
/**
 * Migrate a local FS directory to cloud (database)
 * POST /api/migrate_to_cloud.php
 * Body: { "fs_path": "Redes/Lab1", "share_name": "Compartir Lab Redes" }
 * 
 * This scans the entire FS tree and migrates it to the database,
 * marking everything as cloud_managed=1 and creating a share
 */

declare(strict_types=1);
require_once 'cors.php';
require_once '../includes/bootstrap.php';
require_once __DIR__ . '/../includes/fs.php';

if ($_SERVER['REQUEST_METHOD'] !== 'POST') {
    jsonResponse(405, ['error' => 'Method not allowed']);
}

$pdo = getPDO();
$user = requireAuth($pdo);

$data = json_decode(file_get_contents('php://input'), true) ?? $_POST;
$fsPath = normalizeRelativePath((string)($data['fs_path'] ?? ''));
$shareName = trim($data['share_name'] ?? '');

log_info('migrate_to_cloud request', [
    'fs_path' => $fsPath,
    'share_name' => $shareName,
    'user_id' => $user['id']
]);

if ($fsPath === '') {
    log_error('migrate_to_cloud: fs_path is empty');
    jsonResponse(400, ['error' => 'fs_path es requerido']);
}

if ($shareName === '') {
    log_error('migrate_to_cloud: share_name is empty');
    jsonResponse(400, ['error' => 'share_name es requerido']);
}

$absPath = absPathForUser((int)$user['id'], $fsPath);

log_info('migrate_to_cloud: resolved absolute path', [
    'abs_path' => $absPath,
    'exists' => is_dir($absPath),
    'readable' => is_readable($absPath)
]);

if (!is_dir($absPath)) {
    log_error('migrate_to_cloud: directory does not exist', [
        'abs_path' => $absPath,
        'fs_path' => $fsPath
    ]);
    jsonResponse(404, ['error' => 'El directorio no existe en el sistema de archivos']);
}

try {
    $pdo->beginTransaction();
    
    // First, check if this directory already has a cloud-managed version
    // by checking if a share exists for this fs_path
    $parts = array_filter(explode('/', $fsPath), fn($p) => $p !== '');
    $dirName = empty($parts) ? basename($absPath) : end($parts);
    
    // Check if there's already a cloud directory with this name and path for this user
    $checkCloudStmt = $pdo->prepare('
        SELECT d.id, ds.id as share_id, ds.name as share_name
        FROM directories d
        LEFT JOIN directory_shares ds ON ds.directory_root_id = d.id AND ds.owner_user_id = ?
        WHERE d.user_id = ? AND d.name = ? AND d.cloud_managed = 1 AND d.parent_id IS NULL
        LIMIT 1
    ');
    $checkCloudStmt->execute([(int)$user['id'], (int)$user['id'], $dirName]);
    $existingCloud = $checkCloudStmt->fetch(PDO::FETCH_ASSOC);
    
    if ($existingCloud && $existingCloud['share_id']) {
        // Share ya existe, solo devolver el share_id
        $pdo->commit();
        
        // Delete from FS since it's already in cloud
        try {
            deleteDirectory($absPath);
            log_info('FS directory deleted (share already exists in cloud)', [
                'fs_path' => $fsPath,
                'abs_path' => $absPath
            ]);
        } catch (Exception $e) {
            log_error('Failed to delete FS directory after finding existing share', [
                'error' => $e->getMessage(),
                'fs_path' => $fsPath
            ]);
        }
        
        log_info('Reusing existing cloud directory and share', [
            'share_id' => $existingCloud['share_id'],
            'root_directory_id' => $existingCloud['id'],
            'fs_path' => $fsPath
        ]);
        
        jsonResponse(200, [
            'success' => true,
            'share_id' => (int)$existingCloud['share_id'],
            'root_directory_id' => (int)$existingCloud['id'],
            'share_name' => $existingCloud['share_name'],
            'message' => 'Share existente reutilizado. Directorio eliminado del sistema local.',
            'reused' => true
        ]);
        return;
    }
    
    // Recursive migration function
    $migrateTree = function($currentFsPath, $parentDbId = null) use ($pdo, $user, &$migrateTree, $absPath) {
        $parts = array_filter(explode('/', $currentFsPath), fn($p) => $p !== '');
        $dirName = empty($parts) ? basename($absPath) : array_pop($parts);
        $currentAbs = absPathForUser((int)$user['id'], $currentFsPath);
        
        log_info('Migrating directory', [
            'fs_path' => $currentFsPath,
            'dir_name' => $dirName,
            'parent_id' => $parentDbId
        ]);
        
        // Read metadata
        $meta = readDirMeta($currentAbs);
        $color = $meta['color'] ?? '#1565C0';
        
        // Insert directory
        $stmt = $pdo->prepare('
            INSERT INTO directories (user_id, parent_id, name, color_hex, cloud_managed)
            VALUES (?, ?, ?, ?, 1)
        ');
        $stmt->execute([(int)$user['id'], $parentDbId, $dirName, $color]);
        $dirId = (int)$pdo->lastInsertId();
        
        log_info('Directory inserted to DB', [
            'directory_id' => $dirId,
            'name' => $dirName
        ]);
        
        // Scan children
        $iterator = new DirectoryIterator($currentAbs);
        $subdirCount = 0;
        $pdfCount = 0;
        
        foreach ($iterator as $item) {
            if ($item->isDot()) continue;
            
            $itemName = $item->getFilename();
            $itemPath = $currentFsPath !== '' ? ($currentFsPath . '/' . $itemName) : $itemName;
            
            if ($item->isDir()) {
                // Skip .meta
                if ($itemName === '.meta') continue;
                
                log_info('Found subdirectory', ['name' => $itemName, 'path' => $itemPath]);
                $subdirCount++;
                
                // Recursive migration
                $migrateTree($itemPath, $dirId);
            } elseif ($item->isFile()) {
                // Migrate PDF and TXT documents
                $ext = strtolower(pathinfo($itemName, PATHINFO_EXTENSION));
                
                if ($ext === 'pdf' || $ext === 'txt') {
                    $filePath = $currentAbs . DIRECTORY_SEPARATOR . $itemName;
                    $fileSize = filesize($filePath);
                    $displayName = pathinfo($itemName, PATHINFO_FILENAME);
                    $mimeType = $ext === 'pdf' ? 'application/pdf' : 'text/plain';
                    $textContent = '';
                    
                    if ($ext === 'pdf') {
                        log_info('Found PDF file', ['name' => $itemName]);
                        $pdfCount++;
                        
                        // Try to extract text from PDF
                        try {
                            require_once __DIR__ . '/../vendor/autoload.php';
                            $parser = new \Smalot\PdfParser\Parser();
                            $pdf = $parser->parseFile($filePath);
                            $textContent = $pdf->getText();
                        } catch (\Throwable $e) {
                            log_error('PDF parsing failed during migration', ['file' => $itemName, 'error' => $e->getMessage()]);
                            $textContent = '';
                        }
                    } else {
                        // TXT file
                        log_info('Found TXT file', ['name' => $itemName]);
                        $textContent = file_get_contents($filePath);
                    }
                    
                    // Insert document into database
                    // NOTE: file_rel_path must be relative to user root WITHOUT the uploads/userid/ prefix
                    // It's used later with absPathForUser() which will add that prefix automatically
                    $fileRelPath = $itemPath;
                    
                    $docStmt = $pdo->prepare('
                        INSERT INTO documents (
                            user_id, 
                            directory_id, 
                            original_filename, 
                            display_name, 
                            stored_filename, 
                            file_rel_path,
                            mime_type, 
                            size_bytes, 
                            text_content
                        )
                        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
                    ');
                    $docStmt->execute([
                        (int)$user['id'], 
                        $dirId, 
                        $itemName,
                        $displayName . '.' . $ext, 
                        $itemName,
                        $fileRelPath,
                        $mimeType,
                        $fileSize,
                        $textContent
                    ]);
                    
                    $documentId = (int)$pdo->lastInsertId();
                    
                    log_info('Document inserted to DB', [
                        'document_id' => $documentId,
                        'filename' => $itemName,
                        'type' => $ext,
                        'directory_id' => $dirId
                    ]);
                    
                    // If it's a PDF and summary exists, save it
                    if ($ext === 'pdf') {
                        $summaryFile = $currentAbs . DIRECTORY_SEPARATOR . 'Resumen_' . $itemName . '.txt';
                        $summaryText = '';
                        if (file_exists($summaryFile)) {
                            $summaryText = file_get_contents($summaryFile);
                        }
                        
                        if ($summaryText !== '') {
                            // Create a summary job record as completed
                            $summaryJobStmt = $pdo->prepare('
                                INSERT INTO summary_jobs (
                                    user_id, 
                                    file_path, 
                                    analysis_type, 
                                    model, 
                                    status, 
                                    progress, 
                                    summary_text
                                )
                                VALUES (?, ?, ?, ?, ?, ?, ?)
                            ');
                            $summaryJobStmt->execute([
                                (int)$user['id'],
                                $itemPath,
                                'summary_fast',
                                'migrated',
                                'completed',
                                100,
                                $summaryText
                            ]);
                            
                            log_info('Summary migrated', [
                                'document_id' => $documentId,
                                'has_summary' => true
                            ]);
                        }
                    }
                }
            }
        }
        
        log_info('Directory migration completed', [
            'directory_id' => $dirId,
            'name' => $dirName,
            'subdirs_found' => $subdirCount,
            'pdfs_found' => $pdfCount
        ]);
        
        return $dirId;
    };
    
    // Start migration from root (only if we didn't reuse existing share)
    log_info('Starting FS→Cloud migration', ['fs_path' => $fsPath, 'user_id' => $user['id']]);
    $rootDirId = $migrateTree($fsPath, null);
    
    // Create new share (we only get here if no existing share was found)
    $shareStmt = $pdo->prepare('
        INSERT INTO directory_shares (directory_root_id, owner_user_id, name, created_at)
        VALUES (?, ?, ?, NOW())
    ');
    $shareStmt->execute([$rootDirId, (int)$user['id'], $shareName]);
    $shareId = (int)$pdo->lastInsertId();
    
    // Add root directory to share nodes
    $nodeStmt = $pdo->prepare('
        INSERT INTO directory_share_nodes (share_id, directory_id, include_subtree)
        VALUES (?, ?, 1)
    ');
    $nodeStmt->execute([$shareId, $rootDirId]);
    
    // Log event
    logDirectoryEvent($pdo, (int)$user['id'], 'share_created', $shareId, $rootDirId, null, [
        'share_name' => $shareName,
        'migrated_from_fs' => $fsPath
    ]);
    
    $pdo->commit();
    
    // After successful migration to cloud, DELETE from FS
    // This ensures the directory only exists in one place: either FS or Cloud
    log_info('Attempting to delete FS directory', [
        'abs_path' => $absPath,
        'fs_path' => $fsPath,
        'exists' => file_exists($absPath)
    ]);
    
    try {
        deleteDirectory($absPath);
        log_info('FS directory deleted successfully', [
            'fs_path' => $fsPath,
            'abs_path' => $absPath,
            'still_exists' => file_exists($absPath)
        ]);
    } catch (Exception $e) {
        // Log error but don't fail the migration since data is safely in cloud
        log_error('Failed to delete FS directory after migration', [
            'error' => $e->getMessage(),
            'trace' => $e->getTraceAsString(),
            'fs_path' => $fsPath,
            'abs_path' => $absPath
        ]);
    }
    
    log_info('FS→Cloud migration completed', [
        'share_id' => $shareId,
        'root_directory_id' => $rootDirId,
        'fs_path' => $fsPath
    ]);
    
    jsonResponse(201, [
        'success' => true,
        'share_id' => $shareId,
        'root_directory_id' => $rootDirId,
        'share_name' => $shareName,
        'message' => 'Directorio migrado a la nube y eliminado del sistema local exitosamente'
    ]);
    
} catch (PDOException $e) {
    if ($pdo->inTransaction()) {
        $pdo->rollBack();
    }
    log_error('Migration PDO error', [
        'error' => $e->getMessage(),
        'trace' => $e->getTraceAsString(),
        'fs_path' => $fsPath
    ]);
    jsonResponse(500, ['error' => 'Error de base de datos: ' . $e->getMessage()]);
} catch (Throwable $e) {
    if ($pdo->inTransaction()) {
        $pdo->rollBack();
    }
    log_error('Migration unexpected error', [
        'error' => $e->getMessage(),
        'type' => get_class($e),
        'trace' => $e->getTraceAsString(),
        'fs_path' => $fsPath
    ]);
    jsonResponse(500, ['error' => 'Error al migrar: ' . $e->getMessage()]);
}
