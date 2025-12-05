<?php
/**
 * Test the polling endpoint manually
 */

// Simulated auth (in real app, this comes from token)
$_SERVER['HTTP_AUTHORIZATION'] = 'Bearer test';
$_SERVER['REQUEST_METHOD'] = 'GET';
$_GET['share_id'] = 6;
$_GET['since'] = null;

require_once __DIR__ . '/includes/bootstrap.php';

// Mock requireAuth to use test user
$pdo = getPDO();

// Get test user (ID 11 from our checks)
$testUser = $pdo->query("SELECT * FROM users LIMIT 1")->fetch(PDO::FETCH_ASSOC);
error_log("Test user: " . json_encode($testUser));

// Now call the actual endpoint
require_once __DIR__ . '/api/get_share_updates.php';
