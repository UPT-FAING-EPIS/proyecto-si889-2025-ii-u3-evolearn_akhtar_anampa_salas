<?php
/**
 * Test PDF streaming with detailed debugging
 * GET /backend/test_pdf_debug.php?file=path/to/pdf.pdf
 * 
 * This endpoint streams a PDF with extensive logging to debug the rendering issue
 */

declare(strict_types=1);

$filePath = isset($_GET['file']) ? trim($_GET['file']) : '';

if (empty($filePath)) {
    http_response_code(400);
    echo json_encode([
        'error' => 'file parameter required',
        'example' => '/backend/test_pdf_debug.php?file=uploads/11/Sistema_Binario.pdf'
    ]);
    exit;
}

// Prevent directory traversal
$filePath = str_replace(['../', '..\\'], '', $filePath);
$basePath = __DIR__ . '/uploads/';
$fullPath = realpath($basePath . $filePath);

if (!$fullPath || strpos($fullPath, realpath($basePath)) !== 0) {
    http_response_code(403);
    echo json_encode(['error' => 'Invalid file path']);
    exit;
}

if (!is_file($fullPath)) {
    http_response_code(404);
    echo json_encode(['error' => 'File not found: ' . $fullPath]);
    exit;
}

// Get file info
$fileSize = filesize($fullPath);
$mimeType = mime_content_type($fullPath) ?: 'application/octet-stream';
$fileName = basename($fullPath);

// Log to file
$logMsg = sprintf(
    "[%s] Serving PDF: %s (Size: %d bytes, Type: %s)" . PHP_EOL,
    date('Y-m-d H:i:s'),
    $fileName,
    $fileSize,
    $mimeType
);
error_log($logMsg, 3, __DIR__ . '/logs/pdf_debug.log');

// Set headers - CRITICAL for binary data integrity
header('Content-Type: application/pdf');
header('Content-Disposition: inline; filename="' . $fileName . '"');
header('Content-Length: ' . $fileSize);
header('Cache-Control: no-cache, must-revalidate, max-age=0');
header('Pragma: public');
header('Expires: 0');
header('Accept-Ranges: bytes');

// CRITICAL: Disable any compression or encoding that might corrupt binary data
header('Content-Encoding: identity');
header('Content-Transfer-Encoding: binary');

// Add debug headers to verify reception
header('X-File-Name: ' . $fileName);
header('X-File-Size: ' . $fileSize);
header('X-Debug-Mode: enabled');

// Disable output buffering completely
while (ob_get_level()) {
    ob_end_flush();
}

// Ensure no timeouts during streaming
set_time_limit(0);
ignore_user_abort(false);

// Open file
$handle = fopen($fullPath, 'rb');
if (!$handle) {
    http_response_code(500);
    error_log("[ERROR] Failed to open file: $fullPath" . PHP_EOL, 3, __DIR__ . '/logs/pdf_debug.log');
    exit;
}

$sentBytes = 0;
$chunkSize = 8192; // 8KB chunks
$lastLogSize = 0;

try {
    while (!feof($handle) && !connection_aborted()) {
        $chunk = fread($handle, $chunkSize);
        if ($chunk === false || $chunk === '') {
            break;
        }
        
        echo $chunk;
        $sentBytes += strlen($chunk);
        flush();
        
        // Log every 100KB
        if ($sentBytes - $lastLogSize >= 102400) {
            $progress = ($sentBytes / $fileSize * 100);
            error_log(sprintf(
                "[STREAM] Progress: %d / %d bytes (%.1f%%)" . PHP_EOL,
                $sentBytes,
                $fileSize,
                $progress
            ), 3, __DIR__ . '/logs/pdf_debug.log');
            $lastLogSize = $sentBytes;
        }
    }
    
    error_log(sprintf(
        "[COMPLETE] Sent %d / %d bytes (%.1f%%)" . PHP_EOL,
        $sentBytes,
        $fileSize,
        ($sentBytes / $fileSize * 100)
    ), 3, __DIR__ . '/logs/pdf_debug.log');
    
} catch (Exception $e) {
    error_log("[EXCEPTION] " . $e->getMessage() . PHP_EOL, 3, __DIR__ . '/logs/pdf_debug.log');
} finally {
    fclose($handle);
}

exit;
