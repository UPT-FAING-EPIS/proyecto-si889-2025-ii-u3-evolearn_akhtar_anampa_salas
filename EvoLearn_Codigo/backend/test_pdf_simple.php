<?php
/**
 * Test endpoint: Create a simple PDF with text
 * GET /backend/test_pdf_simple.php
 * 
 * This creates a minimal valid PDF with text content
 * Use to test if PDF rendering issue is specific to certain PDF types
 */

// Create a minimal PDF with text
function generateSimplePDF() {
    $pdf = '%PDF-1.4
1 0 obj
<< /Type /Catalog /Pages 2 0 R >>
endobj
2 0 obj
<< /Type /Pages /Kids [3 0 R] /Count 1 >>
endobj
3 0 obj
<< /Type /Page /Parent 2 0 R /Resources 4 0 R /MediaBox [0 0 612 792] /Contents 5 0 R >>
endobj
4 0 obj
<< /Font << /F1 6 0 R >> >>
endobj
5 0 obj
<< /Length 100 >>
stream
BT
/F1 24 Tf
50 750 Td
(Hola Mundo - Test PDF) Tj
0 -50 Td
(Este es un PDF de prueba) Tj
0 -50 Td
(Con contenido de texto) Tj
ET
endstream
endobj
6 0 obj
<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>
endobj
xref
0 7
0000000000 65535 f 
0000000009 00000 n 
0000000058 00000 n 
0000000115 00000 n 
0000000217 00000 n 
0000000274 00000 n 
0000000429 00000 n 
trailer
<< /Size 7 /Root 1 0 R >>
startxref
0
%%EOF';
    
    // Replace '%%EOF' with actual offset
    $parts = explode('startxref', $pdf);
    $offset = strlen($parts[0]);
    $pdf = str_replace('startxref' . PHP_EOL . '0' . PHP_EOL . '%%EOF', 
                      'startxref' . PHP_EOL . $offset . PHP_EOL . '%%EOF', $pdf);
    
    return $pdf;
}

// Set headers for PDF download
header('Content-Type: application/pdf');
header('Content-Disposition: inline; filename="test.pdf"');
header('Cache-Control: no-cache, must-revalidate, max-age=0');
header('Pragma: public');
header('Expires: 0');
header('Content-Encoding: identity');
header('Content-Transfer-Encoding: binary');

// Disable output buffering
while (ob_get_level()) {
    ob_end_flush();
}

// Output the PDF
$pdf = generateSimplePDF();
header('Content-Length: ' . strlen($pdf));
echo $pdf;
exit;
