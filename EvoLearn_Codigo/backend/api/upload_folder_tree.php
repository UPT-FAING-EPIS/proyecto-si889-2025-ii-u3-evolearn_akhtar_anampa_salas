<?php
declare(strict_types=1);

require_once 'cors.php';
require_once __DIR__ . '/../includes/db.php';
require_once __DIR__ . '/../includes/auth.php';
require_once __DIR__ . '/../includes/logger.php';
require_once __DIR__ . '/../includes/fs.php';

/**
 * Upload entire folder tree from mobile device to server filesystem
 * before migrating to cloud/database
 * 
 * Expected JSON payload:
 * {
 *   "folder_name": "Soluciones Moviles",
 *   "items": [
 *     {
 *       "type": "directory",
 *       "path": "Soluciones Moviles/Subdir1",
 *       "name": "Subdir1"
 *     },
 *     {
 *       "type": "file",
 *       "path": "Soluciones Moviles/doc.pdf",
 *       "name": "doc.pdf",
 *       "content": "base64_encoded_file_content"
 *     },
 *     {
 *       "type": "file",
 *       "path": "Soluciones Moviles/resumen_doc_fast.txt",
 *       "name": "resumen_doc_fast.txt",
 *       "content": "base64_encoded_text_content"
 *     }
 *   ]
 * }
 * 
 * This will recreate the folder structure in backend/uploads/{user_id}/
 */

if ($_SERVER['REQUEST_METHOD'] !== 'POST') {
    jsonResponse(405, ['error' => 'Method not allowed']);
    exit;
}

// Initialize variables outside try-catch for cleanup
$userId = null;
$folderName = null;
$rootPath = null;
$user = null;

try {
    $pdo = getPDO();
    $user = requireAuth($pdo);
    $userId = (int)$user['id'];

    // Log request details for debugging
    $rawInput = file_get_contents('php://input');
    log_info('upload_folder_tree: raw request received', [
        'user_id' => $userId,
        'raw_length' => strlen($rawInput),
        'content_type' => $_SERVER['CONTENT_TYPE'] ?? 'unknown',
    ]);

    // Parse JSON body
    $input = json_decode($rawInput, true);
    if ($input === null) {
        $jsonError = json_last_error_msg();
        log_error('upload_folder_tree: JSON parse error', [
            'user_id' => $userId,
            'error' => $jsonError,
            'raw_length' => strlen($rawInput),
        ]);
        jsonResponse(400, ['error' => "JSON parse error: $jsonError"]);
        exit;
    }

    if (!isset($input['folder_name']) || !isset($input['items'])) {
        log_error('upload_folder_tree: missing folder_name or items', [
            'user_id' => $userId,
            'has_folder_name' => isset($input['folder_name']),
            'has_items' => isset($input['items']),
        ]);
        jsonResponse(400, ['error' => 'Missing folder_name or items in request body']);
        exit;
    }

    $folderName = sanitizeName((string)$input['folder_name']);
    if (empty($folderName)) {
        jsonResponse(400, ['error' => 'Invalid folder_name']);
        exit;
    }

    $items = $input['items'];
    if (!is_array($items)) {
        jsonResponse(400, ['error' => 'items must be an array']);
        exit;
    }

    log_info('upload_folder_tree: validation started', [
        'user_id' => $userId,
        'folder_name' => $folderName,
        'total_items' => count($items),
    ]);

    // Validate and limit upload size (max 100MB total)
    $totalSize = 0;
    $maxTotalSize = 100 * 1024 * 1024; // 100MB

    foreach ($items as $idx => $item) {
        if (!isset($item['type']) || !isset($item['path']) || !isset($item['name'])) {
            log_error('upload_folder_tree: invalid item structure', [
                'user_id' => $userId,
                'item_index' => $idx,
                'has_type' => isset($item['type']),
                'has_path' => isset($item['path']),
                'has_name' => isset($item['name']),
                'keys' => array_keys($item),
            ]);
            jsonResponse(400, ['error' => "Item #$idx: Each item must have type, path, and name"]);
            exit;
        }
        
        if ($item['type'] === 'file') {
            if (!isset($item['content'])) {
                log_error('upload_folder_tree: file without content', [
                    'user_id' => $userId,
                    'item_index' => $idx,
                    'file_name' => $item['name'] ?? 'unknown',
                ]);
                jsonResponse(400, ['error' => "Item #$idx: File items must have content (base64)"]);
                exit;
            }
            // Estimate decoded size (base64 is ~33% larger than binary)
            $encodedSize = strlen($item['content']);
            $decodedSize = (int)($encodedSize * 0.75);
            $totalSize += $decodedSize;
            
            if ($totalSize > $maxTotalSize) {
                jsonResponse(413, ['error' => 'Total upload size exceeds 100MB limit']);
                exit;
            }
        }
    }

    // Create root folder in user's uploads directory
    $rootPath = absPathForUser($userId, $folderName);

    // Make operation idempotent: if root exists, proceed without error
    if (!file_exists($rootPath)) {
        if (!mkdir($rootPath, 0777, true)) {
            throw new RuntimeException('Failed to create root folder');
        }
    }
    
    log_info('upload_folder_tree', [
        'user_id' => $userId,
        'folder_name' => $folderName,
        'root_path' => $rootPath,
        'item_count' => count($items),
        'total_size_mb' => round($totalSize / 1024 / 1024, 2)
    ]);
    
    $stats = [
        'directories_created' => 0,
        'files_uploaded' => 0,
        'pdfs_uploaded' => 0,
        'txt_uploaded' => 0,
        'total_bytes' => 0
    ];
    
    // Process items in order (directories first, then files)
    usort($items, function($a, $b) {
        if ($a['type'] === 'directory' && $b['type'] === 'file') return -1;
        if ($a['type'] === 'file' && $b['type'] === 'directory') return 1;
        return 0;
    });
    
    foreach ($items as $item) {
        $itemPath = (string)$item['path'];
        $itemName = sanitizeName((string)$item['name']);
        
        // Normalize path: convert any backslashes to forward slashes
        $itemPath = str_replace('\\', '/', $itemPath);
        
        // Security: ensure path starts with folder_name (or is exactly folder_name for root files)
        $validPath = str_starts_with($itemPath, $folderName . '/') || $itemPath === $folderName;
        if (!$validPath) {
            log_error('upload_folder_tree: Invalid path detected', [
                'user_id' => $userId,
                'folder_name' => $folderName,
                'item_path' => $itemPath,
                'starts_with_folder' => str_starts_with($itemPath, $folderName . '/'),
            ]);
            continue; // Skip suspicious paths
        }
        
        // Convert to relative path from user root
        $relativePath = $itemPath;
        $absolutePath = absPathForUser($userId, $relativePath);
        
        if ($item['type'] === 'directory') {
            if (!file_exists($absolutePath)) {
                if (mkdir($absolutePath, 0777, true)) {
                    $stats['directories_created']++;
                    log_info('upload_folder_tree: directory created', [
                        'user_id' => $userId,
                        'path' => $relativePath
                    ]);
                }
            }
        } elseif ($item['type'] === 'file') {
            // Decode base64 content
            $content = base64_decode($item['content'], true);
            if ($content === false) {
                log_error('upload_folder_tree: Invalid base64 content', [
                    'user_id' => $userId,
                    'file' => $itemName
                ]);
                continue;
            }
            
            // Ensure parent directory exists
            $parentDir = dirname($absolutePath);
            if (!is_dir($parentDir)) {
                mkdir($parentDir, 0777, true);
            }
            
            // Write file
            $bytesWritten = file_put_contents($absolutePath, $content);
            if ($bytesWritten === false) {
                log_error('upload_folder_tree: Failed to write file', [
                    'user_id' => $userId,
                    'file' => $itemName,
                    'path' => $absolutePath
                ]);
                continue;
            }
            
            $stats['files_uploaded']++;
            $stats['total_bytes'] += $bytesWritten;
            
            // Track file types
            $ext = strtolower(pathinfo($itemName, PATHINFO_EXTENSION));
            if ($ext === 'pdf') {
                $stats['pdfs_uploaded']++;
            } elseif ($ext === 'txt') {
                $stats['txt_uploaded']++;
            }
            
            log_info('upload_folder_tree: file uploaded', [
                'user_id' => $userId,
                'file' => $itemName,
                'path' => $relativePath,
                'size_kb' => round($bytesWritten / 1024, 2)
            ]);
        }
    }
    
    log_info('upload_folder_tree: completed', [
        'user_id' => $userId,
        'folder_name' => $folderName,
        'stats' => $stats
    ]);
    
    jsonResponse(200, [
        'success' => true,
        'folder_name' => $folderName,
        'stats' => $stats,
        'message' => 'Folder tree uploaded successfully to server'
    ]);
    
} catch (Throwable $e) {
    // Cleanup on failure (safe check)
    if ($rootPath && is_string($rootPath) && file_exists($rootPath)) {
        try {
            @deleteDirectory($rootPath);
        } catch (Throwable $cleanupEx) {
            // Silently ignore cleanup errors
        }
    }
    
    jsonResponse(500, [
        'error' => 'Failed to upload folder tree',
        'details' => $e->getMessage()
    ]);
}
