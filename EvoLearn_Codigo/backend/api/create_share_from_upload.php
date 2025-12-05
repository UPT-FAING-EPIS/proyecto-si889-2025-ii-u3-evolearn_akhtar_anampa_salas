<?php
/**
 * Create a share directly from uploaded folder content
 * POST /api/create_share_from_upload.php
 * Body: { 
 *   "folder_name": "Soluciones_Moviles",
 *   "share_name": "Compartir_Soluciones_Moviles"
 * }
 * 
 * This is used after uploadFolderTree to migrate the uploaded folder
 * directly to cloud (database) without checking FS paths
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
$folderName = sanitizeName((string)($data['folder_name'] ?? ''));
$shareName = trim($data['share_name'] ?? '');

log_info('create_share_from_upload request', [
    'folder_name' => $folderName,
    'share_name' => $shareName,
    'user_id' => $user['id']
]);

if ($folderName === '') {
    log_error('create_share_from_upload: folder_name is empty');
    jsonResponse(400, ['error' => 'folder_name es requerido']);
}

if ($shareName === '') {
    log_error('create_share_from_upload: share_name is empty');
    jsonResponse(400, ['error' => 'share_name es requerido']);
}

$absPath = absPathForUser((int)$user['id'], $folderName);

log_info('create_share_from_upload: resolved absolute path', [
    'abs_path' => $absPath,
    'exists' => is_dir($absPath),
]);

if (!is_dir($absPath)) {
    log_error('create_share_from_upload: uploaded directory does not exist', [
        'abs_path' => $absPath,
        'folder_name' => $folderName
    ]);
    jsonResponse(404, ['error' => 'El directorio subido no existe: ' . $folderName]);
}

try {
    $pdo->beginTransaction();
    
    // Recursive migration function - same as migrate_to_cloud but simpler
    $migrateTree = function($currentFsPath, $parentDbId = null) use ($pdo, $user, &$migrateTree, $absPath) {
        $parts = array_filter(explode('/', $currentFsPath), fn($p) => $p !== '');
        $dirName = empty($parts) ? basename($absPath) : array_pop($parts);
        $currentAbs = absPathForUser((int)$user['id'], $currentFsPath);
        
        log_info('Migrating uploaded directory', [
            'fs_path' => $currentFsPath,
            'dir_name' => $dirName,
            'parent_id' => $parentDbId
        ]);
        
        // Read metadata if exists
        $meta = @readDirMeta($currentAbs) ?? ['color' => '#1565C0'];
        $color = $meta['color'] ?? '#1565C0';
        
        // Insert directory
        $stmt = $pdo->prepare('
            INSERT INTO directories (user_id, parent_id, name, color_hex, cloud_managed)
            VALUES (?, ?, ?, ?, 1)
        ');
        $stmt->execute([(int)$user['id'], $parentDbId, $dirName, $color]);
        $dirId = (int)$pdo->lastInsertId();
        
        log_info('Uploaded directory inserted to DB', [
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
                
                log_info('Found uploaded subdirectory', ['name' => $itemName, 'path' => $itemPath]);
                $subdirCount++;
                
                // Recursive migration
                $migrateTree($itemPath, $dirId);
            } elseif ($item->isFile()) {
                // Migrate PDF and TXT documents
                $ext = strtolower(pathinfo($itemName, PATHINFO_EXTENSION));
                $isSummary = strpos($itemName, 'resumen_') === 0 && $ext === 'txt';
                
                if ($ext === 'pdf' || $isSummary) {
                    log_info('Found uploaded document', [
                        'name' => $itemName,
                        'is_summary' => $isSummary
                    ]);
                    $pdfCount++;
                    
                    // Get file info
                    $filePath = $currentAbs . DIRECTORY_SEPARATOR . $itemName;
                    $fileSize = filesize($filePath);
                    $displayName = pathinfo($itemName, PATHINFO_FILENAME);
                    
                    // Extract text if PDF
                    $textContent = '';
                    if ($ext === 'pdf') {
                        try {
                            require_once __DIR__ . '/../vendor/autoload.php';
                            $parser = new \Smalot\PdfParser\Parser();
                            $pdf = $parser->parseFile($filePath);
                            $textContent = $pdf->getText();
                        } catch (\Throwable $e) {
                            log_error('PDF parsing failed in create_share_from_upload', [
                                'file' => $itemName,
                                'error' => $e->getMessage()
                            ]);
                            $textContent = '';
                        }
                    } else {
                        // For TXT files (summaries), read as-is
                        $textContent = file_get_contents($filePath) ?? '';
                    }
                    
                    // Sanitize text content to remove invalid UTF-8 sequences
                    // This fixes "Incorrect string value" errors with surrogate pairs
                    if (!empty($textContent)) {
                        // Convert to UTF-8, replacing invalid sequences
                        $textContent = mb_convert_encoding($textContent, 'UTF-8', 'UTF-8');
                        // Remove null bytes and control characters except tab, newline, carriage return
                        $textContent = preg_replace('/[\x00-\x08\x0B\x0C\x0E-\x1F\x7F]/', '', $textContent);
                        // Use iconv to strip invalid UTF-8 sequences more aggressively
                        $textContent = @iconv('UTF-8', 'UTF-8//IGNORE', $textContent);
                        // If all else fails, use empty string
                        if ($textContent === false || $textContent === null) {
                            $textContent = '';
                        }
                    }
                    
                    // Insert document into database
                    // NOTE: file_rel_path must be relative to user root WITHOUT the uploads/userid/ prefix
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
                    $mimeType = $ext === 'pdf' ? 'application/pdf' : 'text/plain';
                    $docStmt->execute([
                        (int)$user['id'], 
                        $dirId, 
                        $itemName,
                        $displayName, 
                        $itemName,
                        $fileRelPath,
                        $mimeType,
                        $fileSize,
                        $textContent
                    ]);
                    
                    $documentId = (int)$pdo->lastInsertId();
                    
                    log_info('Uploaded document inserted', [
                        'document_id' => $documentId,
                        'filename' => $itemName,
                        'directory_id' => $dirId,
                        'is_summary' => $isSummary
                    ]);
                }
            }
        }
        
        log_info('Uploaded directory migration completed', [
            'directory_id' => $dirId,
            'name' => $dirName,
            'subdirs_found' => $subdirCount,
            'docs_found' => $pdfCount
        ]);
        
        return $dirId;
    };
    
    // Start migration
    log_info('Starting upload→cloud migration', [
        'folder_name' => $folderName,
        'user_id' => $user['id']
    ]);
    $rootDirId = $migrateTree($folderName, null);
    
    // Create new share
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
        'created_from_upload' => $folderName
    ]);
    
    $pdo->commit();
    
    // NOTE: We keep the uploaded files in the filesystem
    // The files need to remain accessible for download via get_document_content.php
    // The "cloud" migration means metadata is in DB, but files stay on disk
    log_info('Upload→cloud migration completed (files kept on disk)', [
        'abs_path' => $absPath,
        'folder_name' => $folderName,
        'share_id' => $shareId,
        'root_directory_id' => $rootDirId
    ]);
    
    jsonResponse(201, [
        'success' => true,
        'share_id' => $shareId,
        'root_directory_id' => $rootDirId,
        'share_name' => $shareName,
        'message' => 'Share creado desde carpeta subida exitosamente'
    ]);
    
} catch (PDOException $e) {
    if ($pdo->inTransaction()) {
        $pdo->rollBack();
    }
    log_error('create_share_from_upload PDO error', [
        'error' => $e->getMessage(),
        'folder_name' => $folderName
    ]);
    jsonResponse(500, ['error' => 'Error de base de datos: ' . $e->getMessage()]);
} catch (Throwable $e) {
    if ($pdo->inTransaction()) {
        $pdo->rollBack();
    }
    log_error('create_share_from_upload unexpected error', [
        'error' => $e->getMessage(),
        'type' => get_class($e),
        'folder_name' => $folderName
    ]);
    jsonResponse(500, ['error' => 'Error al crear share: ' . $e->getMessage()]);
}
