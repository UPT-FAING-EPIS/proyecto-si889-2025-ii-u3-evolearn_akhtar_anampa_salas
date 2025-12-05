<?php
$pdo = new PDO('mysql:host=161.132.49.24;dbname=estudiafacil;charset=utf8mb4', 'php_user', 'psswdphp8877');
$result = $pdo->query('SHOW CREATE TABLE users');
$row = $result->fetch(PDO::FETCH_ASSOC);
echo $row['Create Table'] . "\n";
?>
