<?php
/**
 * Test get_cloud_directories.php to see actual response size
 * Helps identify where truncation occurs
 */

declare(strict_types=1);
require_once 'includes/bootstrap.php';

$pdo = getPDO();

try {
    // Get a test share
    $shareStmt = $pdo->query('SELECT id, name, owner_user_id FROM directory_shares LIMIT 1');
    $share = $shareStmt->fetch(PDO::FETCH_ASSOC);
    
    if (!$share) {
        echo "No shares found in database\n";
        exit;
    }
    
    echo "Testing share: " . $share['name'] . " (ID: " . $share['id'] . ")\n\n";
    
    // Get root directories
    $rootStmt = $pdo->prepare('
        SELECT 
            id,
            display_name,
            include_subtree
        FROM cloud_directories
        WHERE share_id = ? AND parent_id IS NULL
        ORDER BY display_name
    ');
    $rootStmt->execute([$share['id']]);
    $roots = $rootStmt->fetchAll(PDO::FETCH_ASSOC);
    
    echo "Root directories: " . count($roots) . "\n";
    
    // Calculate response size
    $totalSize = 0;
    $docCount = 0;
    $dirCount = 0;
    
    // Count documents
    $countStmt = $pdo->prepare('
        SELECT COUNT(*) as cnt FROM documents 
        WHERE directory_id IN (
            SELECT id FROM cloud_directories WHERE share_id = ?
        )
    ');
    $countStmt->execute([$share['id']]);
    $result = $countStmt->fetch(PDO::FETCH_ASSOC);
    $docCount = $result['cnt'];
    
    // Count directories
    $dirStmt = $pdo->prepare('
        SELECT COUNT(*) as cnt FROM cloud_directories WHERE share_id = ?
    ');
    $dirStmt->execute([$share['id']]);
    $result = $dirStmt->fetch(PDO::FETCH_ASSOC);
    $dirCount = $result['cnt'];
    
    echo "Total documents: $docCount\n";
    echo "Total directories: $dirCount\n";
    
    // Estimate response size
    $estimatedSize = strlen(json_encode(['share_id' => 1, 'share_name' => $share['name'], 'owner_name' => 'test', 'your_role' => 'owner', 'directories' => []]));
    $estimatedSize += ($docCount * 250); // ~250 bytes per document
    $estimatedSize += ($dirCount * 200); // ~200 bytes per directory
    
    echo "\nEstimated response size: " . number_format($estimatedSize) . " bytes\n";
    echo "If > 2KB, may cause truncation in PHP dev server\n";
    
} catch (Exception $e) {
    echo "Error: " . $e->getMessage() . "\n";
}
?>
