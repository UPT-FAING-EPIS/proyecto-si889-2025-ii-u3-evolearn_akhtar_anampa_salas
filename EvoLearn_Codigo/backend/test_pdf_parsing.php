<?php
require_once 'vendor/autoload.php';

use Smalot\PdfParser\Parser as PdfParser;

$filePath = __DIR__ . '/uploads/11/ipv4.pdf';

echo "Verificando PDF: $filePath\n\n";

if (!file_exists($filePath)) {
    echo "ERROR: File does not exist\n";
    exit;
}

echo "File size: " . filesize($filePath) . " bytes\n";
echo "File readable: " . (is_readable($filePath) ? "YES" : "NO") . "\n\n";

try {
    $parser = new PdfParser();
    $pdf = $parser->parseFile($filePath);
    echo "✓ PDF parsed successfully\n";
    
    $text = (string)$pdf->getText();
    echo "✓ Text extracted: " . strlen($text) . " characters\n";
    echo "\nExtracted text preview (first 300 chars):\n";
    echo substr($text, 0, 300) . "\n";
} catch (Exception $e) {
    echo "ERROR: " . $e->getMessage() . "\n";
    echo "Exception class: " . get_class($e) . "\n";
}
?>
