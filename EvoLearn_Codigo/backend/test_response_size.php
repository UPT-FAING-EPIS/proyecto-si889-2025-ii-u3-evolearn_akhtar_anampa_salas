<?php
/**
 * Test response size limits on PHP dev server
 * Tests how large a response can be before truncation occurs
 */

declare(strict_types=1);
require_once 'includes/db.php';

// Test 1: Small JSON response (should work)
echo "\n=== TEST 1: Small JSON (100 bytes) ===\n";
$small = [];
for ($i = 0; $i < 10; $i++) {
    $small[] = "item_$i";
}
$json1 = json_encode(['data' => $small]);
echo "Size: " . strlen($json1) . " bytes\n";
echo "Content: " . substr($json1, 0, 100) . "...\n";

// Test 2: Medium JSON response (1KB)
echo "\n=== TEST 2: Medium JSON (1KB) ===\n";
$medium = [];
for ($i = 0; $i < 100; $i++) {
    $medium[] = [
        'id' => $i,
        'name' => "Item Item Item $i",
        'description' => "This is a test description for item $i with some content"
    ];
}
$json2 = json_encode(['data' => $medium]);
echo "Size: " . strlen($json2) . " bytes\n";
echo "First part: " . substr($json2, 0, 100) . "\n";
echo "Last part: " . substr($json2, -100) . "\n";

// Test 3: Large JSON response (100KB)
echo "\n=== TEST 3: Large JSON (100KB) ===\n";
$large = [];
for ($i = 0; $i < 1000; $i++) {
    $large[] = [
        'id' => $i,
        'name' => "Item Item Item $i",
        'description' => "This is a test description for item $i with some content that is repeated to make the response larger and test the server limits",
        'long_field' => str_repeat("x", 50)
    ];
}
$json3 = json_encode(['data' => $large]);
echo "Size: " . strlen($json3) . " bytes\n";
echo "First part: " . substr($json3, 0, 100) . "\n";
echo "Last part: " . substr($json3, -100) . "\n";

// Test 4: Simulate directory structure (similar to get_cloud_directories)
echo "\n=== TEST 4: Directory Structure Response ===\n";
$dirs = [];
for ($d = 0; $d < 5; $d++) {
    $dir = [
        'id' => $d,
        'name' => "Directory_$d",
        'documents' => [],
        'subdirectories' => []
    ];
    
    // Add some documents
    for ($doc = 0; $doc < 20; $doc++) {
        $dir['documents'][] = [
            'id' => $d * 1000 + $doc,
            'display_name' => "Document_$doc.pdf",
            'size_bytes' => 1024000 + rand(0, 100000),
            'created_at' => date('Y-m-d H:i:s'),
            'type' => 'pdf'
        ];
    }
    
    // Add subdirectories
    for ($sub = 0; $sub < 3; $sub++) {
        $dir['subdirectories'][] = [
            'id' => $d * 100 + $sub,
            'name' => "Subdirectory_$sub",
            'documents' => array_slice($dir['documents'], 0, 5),
            'subdirectories' => []
        ];
    }
    
    $dirs[] = $dir;
}

$json4 = json_encode([
    'share_id' => 1,
    'share_name' => 'Test Share',
    'owner_name' => 'Test Owner',
    'your_role' => 'owner',
    'directories' => $dirs
]);
echo "Size: " . strlen($json4) . " bytes\n";
echo "First part: " . substr($json4, 0, 100) . "\n";
echo "Last part: " . substr($json4, -100) . "\n";

echo "\n=== SUMMARY ===\n";
echo "If responses > 2KB fail, PHP dev server has buffer issues\n";
echo "Character 1881 truncation suggests ~2KB limit or similar\n";
?>
