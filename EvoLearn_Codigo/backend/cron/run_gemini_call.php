<?php
require_once __DIR__ . '/../includes/bootstrap.php';
require_once __DIR__ . '/../includes/ai.php';
try {
    $out = call_gemini("Test prompt", 'summary_fast', 'gemini-2.5-flash');
    echo "OK:\n" . substr($out, 0, 1000) . "\n";
} catch (Throwable $e) {
    echo "EXCEPTION: " . $e->getMessage() . "\n";
}
