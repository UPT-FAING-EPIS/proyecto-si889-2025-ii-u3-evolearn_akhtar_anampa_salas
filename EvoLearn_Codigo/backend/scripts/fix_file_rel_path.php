<?php
/**
 * Fix file_rel_path in documents table
 * Removes the uploads/userid/ prefix from file_rel_path that was incorrectly stored
 * 
 * Run: php backend/scripts/fix_file_rel_path.php
 */

declare(strict_types=1);
require_once __DIR__ . '/../includes/bootstrap.php';

$pdo = getPDO();

try {
    echo "Starting fix_file_rel_path script...\n";
    
    // Get all documents with file_rel_path containing uploads/
    $stmt = $pdo->prepare('
        SELECT id, user_id, file_rel_path
        FROM documents
        WHERE file_rel_path LIKE "uploads/%"
        ORDER BY user_id, file_rel_path
    ');
    $stmt->execute();
    $docs = $stmt->fetchAll(PDO::FETCH_ASSOC);
    
    echo "Found " . count($docs) . " documents with uploads/ prefix in file_rel_path\n";
    
    $updatedCount = 0;
    foreach ($docs as $doc) {
        $docId = $doc['id'];
        $userId = $doc['user_id'];
        $oldPath = $doc['file_rel_path'];
        
        // Remove uploads/userid/ prefix
        $userPrefix = 'uploads/' . $userId . '/';
        if (strpos($oldPath, $userPrefix) === 0) {
            $newPath = substr($oldPath, strlen($userPrefix));
            
            // Update the document
            $updateStmt = $pdo->prepare('UPDATE documents SET file_rel_path = ? WHERE id = ?');
            $updateStmt->execute([$newPath, $docId]);
            
            echo "✓ Doc $docId: '$oldPath' -> '$newPath'\n";
            $updatedCount++;
        }
    }
    
    echo "\nCompleted: Updated $updatedCount documents\n";
    
} catch (Exception $e) {
    echo "ERROR: " . $e->getMessage() . "\n";
    exit(1);
}
