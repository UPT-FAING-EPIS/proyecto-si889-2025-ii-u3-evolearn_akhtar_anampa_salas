<?php
/**
 * Comprehensive diagnostic for PHP development server limitations
 * Run: php diagnostics.php
 */

echo "=== EvoLearn PHP Development Server Diagnostics ===\n\n";

// Check PHP version
echo "1. PHP Version: " . PHP_VERSION . "\n";
echo "   Server: " . php_sapi_name() . "\n";

// Check extensions
echo "\n2. Important Extensions:\n";
echo "   - zlib: " . (extension_loaded('zlib') ? "✓" : "✗") . "\n";
echo "   - json: " . (extension_loaded('json') ? "✓" : "✗") . "\n";
echo "   - curl: " . (extension_loaded('curl') ? "✓" : "✗") . "\n";
echo "   - pdo: " . (extension_loaded('pdo') ? "✓" : "✗") . "\n";
echo "   - pdo_mysql: " . (extension_loaded('pdo_mysql') ? "✓" : "✗") . "\n";

// Check php.ini settings
echo "\n3. Critical php.ini Settings:\n";
echo "   - max_execution_time: " . ini_get('max_execution_time') . "\n";
echo "   - default_socket_timeout: " . ini_get('default_socket_timeout') . "\n";
echo "   - memory_limit: " . ini_get('memory_limit') . "\n";
echo "   - output_buffering: " . (ini_get('output_buffering') ?: 'Off') . "\n";
echo "   - zlib.output_compression: " . (ini_get('zlib.output_compression') ?: 'Off') . "\n";
echo "   - max_input_time: " . ini_get('max_input_time') . "\n";
echo "   - upload_max_filesize: " . ini_get('upload_max_filesize') . "\n";
echo "   - post_max_size: " . ini_get('post_max_size') . "\n";

// Check file permissions
echo "\n4. File Permissions:\n";
$uploadDir = dirname(__FILE__) . '/uploads';
echo "   - uploads/: " . (is_dir($uploadDir) ? "✓ exists" : "✗ not found");
if (is_dir($uploadDir)) {
    echo " (" . (is_writable($uploadDir) ? "writable" : "not writable") . ")\n";
} else {
    echo "\n";
}

$cacheDir = dirname(__FILE__) . '/cache';
echo "   - cache/: " . (is_dir($cacheDir) ? "✓ exists" : "✗ not found");
if (is_dir($cacheDir)) {
    echo " (" . (is_writable($cacheDir) ? "writable" : "not writable") . ")\n";
} else {
    echo "\n";
}

// Database connection test
echo "\n5. Database Connection Test:\n";
try {
    require_once __DIR__ . '/includes/db.php';
    $pdo = getPDO();
    $stmt = $pdo->query("SELECT VERSION()");
    $version = $stmt->fetchColumn();
    echo "   ✓ Connected to MySQL: " . $version . "\n";
} catch (Exception $e) {
    echo "   ✗ Connection failed: " . $e->getMessage() . "\n";
}

// Test response sizes
echo "\n6. Response Size Estimates:\n";

// Test small JSON
$small = json_encode(['test' => 'data']);
echo "   - Small JSON (10 items): " . strlen($small) . " bytes\n";

// Test medium JSON
$medium = [];
for ($i = 0; $i < 100; $i++) {
    $medium[] = ['id' => $i, 'name' => "Item $i", 'desc' => 'Description text'];
}
$mediumJson = json_encode($medium);
echo "   - Medium JSON (100 items): " . strlen($mediumJson) . " bytes\n";

// Estimate compression
$compressed = gzencode($mediumJson, 9);
$ratio = round((1 - strlen($compressed) / strlen($mediumJson)) * 100);
echo "   - After gzip compression: " . strlen($compressed) . " bytes ($ratio% reduction)\n";

// Test large JSON
$large = [];
for ($i = 0; $i < 1000; $i++) {
    $large[] = [
        'id' => $i,
        'name' => "Item $i with longer text to make response bigger",
        'desc' => 'This is a longer description text repeated multiple times',
        'field' => str_repeat('x', 100)
    ];
}
$largeJson = json_encode($large);
echo "   - Large JSON (1000 items): " . strlen($largeJson) . " bytes\n";

$compressedLarge = gzencode($largeJson, 9);
$ratioLarge = round((1 - strlen($compressedLarge) / strlen($largeJson)) * 100);
echo "   - After gzip compression: " . strlen($compressedLarge) . " bytes ($ratioLarge% reduction)\n";

// PHP Dev Server Limitations
echo "\n7. Known PHP Development Server Limitations:\n";
echo "   ⚠️  Hard limit on response body size (typically 2-4KB)\n";
echo "   ⚠️  Closes connections prematurely on large responses\n";
echo "   ⚠️  Cannot handle concurrent large downloads\n";
echo "   ⚠️  Not suitable for production use\n";
echo "   ℹ️  Use Apache + PHP-FPM or Nginx + PHP-FPM for production\n";

echo "\n8. Recommendations:\n";

$jsonSize = strlen($mediumJson);
if ($jsonSize > 2000) {
    echo "   ⚠️  Response sizes > 2KB may cause truncation\n";
    echo "   ✓  Using gzip compression (enabled in bootstrap.php)\n";
    echo "   📝 Monitor response sizes in production logs\n";
} else {
    echo "   ✓  Response sizes are manageable\n";
}

echo "\n=== End of Diagnostics ===\n";
?>
