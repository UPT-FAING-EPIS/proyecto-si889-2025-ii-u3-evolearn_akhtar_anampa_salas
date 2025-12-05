<?php
// Crear PDFs válidos directamente como bytes

$pdf_content_ipv4 = <<<'EOF'
%PDF-1.4
1 0 obj
<< /Type /Catalog /Pages 2 0 R >>
endobj
2 0 obj
<< /Type /Pages /Kids [3 0 R] /Count 1 >>
endobj
3 0 obj
<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Contents 4 0 R /Resources << /Font << /F1 5 0 R >> >> >>
endobj
4 0 obj
<< /Length 600 >>
stream
BT
/F1 12 Tf
50 750 Td
(IPv4 Addressing and Subnetting) Tj
0 -20 Td
(IPv4 is the fourth version of the Internet Protocol.) Tj
0 -15 Td
(IPv4 addresses are 32-bit numbers written in four decimal numbers separated by periods.) Tj
0 -15 Td
(For example: 192.168.1.1) Tj
0 -20 Td
(Classful Addressing:) Tj
0 -15 Td
(Class A: 1.0.0.0 to 126.255.255.255) Tj
0 -15 Td
(Class B: 128.0.0.0 to 191.255.255.255) Tj
0 -15 Td
(Class C: 192.0.0.0 to 223.255.255.255) Tj
0 -15 Td
(Class D: 224.0.0.0 to 239.255.255.255) Tj
0 -15 Td
(Class E: 240.0.0.0 to 255.255.255.255) Tj
0 -20 Td
(Subnetting allows dividing an IP address space into networks.) Tj
0 -15 Td
(Default subnet masks for classes:) Tj
0 -15 Td
(Class A: 255.0.0.0) Tj
0 -15 Td
(Class B: 255.255.0.0) Tj
0 -15 Td
(Class C: 255.255.255.0) Tj
ET
endstream
endobj
5 0 obj
<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>
endobj
xref
0 6
0000000000 65535 f 
0000000009 00000 n 
0000000058 00000 n 
0000000115 00000 n 
0000000247 00000 n 
0000000907 00000 n 
trailer
<< /Size 6 /Root 1 0 R >>
startxref
986
%%EOF
EOF;

$pdf_content_ejemplo = <<<'EOF'
%PDF-1.4
1 0 obj
<< /Type /Catalog /Pages 2 0 R >>
endobj
2 0 obj
<< /Type /Pages /Kids [3 0 R] /Count 1 >>
endobj
3 0 obj
<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Contents 4 0 R /Resources << /Font << /F1 5 0 R >> >> >>
endobj
4 0 obj
<< /Length 400 >>
stream
BT
/F1 12 Tf
50 750 Td
(Example Document for Testing) Tj
0 -20 Td
(This is an example document for testing purposes.) Tj
0 -20 Td
(Key Concepts:) Tj
0 -15 Td
(1. Documentation is important for understanding systems) Tj
0 -15 Td
(2. Examples help illustrate and clarify concepts) Tj
0 -15 Td
(3. Testing ensures quality and reliability) Tj
0 -20 Td
(Summary:) Tj
0 -15 Td
(Testing systems with valid PDFs helps ensure the processing pipeline works correctly.) Tj
0 -15 Td
(This example demonstrates proper document handling in the system.) Tj
ET
endstream
endobj
5 0 obj
<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>
endobj
xref
0 6
0000000000 65535 f 
0000000009 00000 n 
0000000058 00000 n 
0000000115 00000 n 
0000000247 00000 n 
0000000707 00000 n 
trailer
<< /Size 6 /Root 1 0 R >>
startxref
786
%%EOF
EOF;

// Escribir los archivos
file_put_contents(__DIR__ . '/uploads/11/ipv4.pdf', $pdf_content_ipv4);
file_put_contents(__DIR__ . '/uploads/11/ejemplo.pdf', $pdf_content_ejemplo);

echo "PDFs creados exitosamente:\n";
echo "- uploads/11/ipv4.pdf (" . strlen($pdf_content_ipv4) . " bytes)\n";
echo "- uploads/11/ejemplo.pdf (" . strlen($pdf_content_ejemplo) . " bytes)\n";
?>
