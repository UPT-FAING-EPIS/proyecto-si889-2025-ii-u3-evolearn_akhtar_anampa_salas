<?php
declare(strict_types=1);
require_once 'cors.php';
require_once '../includes/db.php';
require_once '../includes/auth.php';
require_once __DIR__ . '/../includes/fs.php';
// Preflight CORS
if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') { http_response_code(204); exit; }
// Allow GET or POST
if ($_SERVER['REQUEST_METHOD'] !== 'GET' && $_SERVER['REQUEST_METHOD'] !== 'POST') jsonResponse(405, ['error' => 'Method not allowed']);

$pdo = getPDO();
$user = requireAuth($pdo);

// Always use FS mode
$root = userStorageRoot((int)$user['id']);
if (!is_dir($root)) mkdir($root, 0777, true);
$fsTree = listDirectoryNode((int)$user['id'], $root, '');
jsonResponse(200, ['success' => true, 'mode' => 'fs', 'fs_tree' => $fsTree]);



