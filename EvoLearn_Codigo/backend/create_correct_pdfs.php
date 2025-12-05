<?php
// Crear PDFs válidos usando una librería o formato correcto
// El problema es que el stream no tiene el length correcto

$pdf_ipv4 = '%PDF-1.0
1 0 obj<</Type/Catalog/Pages 2 0 R>>endobj
2 0 obj<</Type/Pages/Kids[3 0 R]/Count 1>>endobj
3 0 obj<</Type/Page/Parent 2 0 R/Resources<</Font<</F1 4 0 R>>>>/MediaBox[0 0 612 792]/Contents 5 0 R>>endobj
4 0 obj<</Type/Font/Subtype/Type1/BaseFont/Helvetica>>endobj
5 0 obj<</Length 1074>>
stream
BT
/F1 24 Tf
100 700 Td
(IPv4 Addressing) Tj
ET
BT
/F1 12 Tf
100 650 Td
(IPv4 is the fourth version of the Internet Protocol.) Tj
0 -30 Td
(It is one of the core protocols of standards-based internetworking methods.) Tj
0 -30 Td
(IPv4 addresses are 32-bit numbers written in four decimal numbers.) Tj
0 -30 Td
(Example: 192.168.1.1) Tj
0 -60 Td
(Classful Addressing:) Tj
0 -30 Td
(Class A: 1.0.0.0 to 126.255.255.255) Tj
0 -30 Td
(Class B: 128.0.0.0 to 191.255.255.255) Tj
0 -30 Td
(Class C: 192.0.0.0 to 223.255.255.255) Tj
0 -30 Td
(Class D: 224.0.0.0 to 239.255.255.255) Tj
0 -30 Td
(Class E: 240.0.0.0 to 255.255.255.255) Tj
0 -60 Td
(Subnetting) Tj
0 -30 Td
(Subnetting allows dividing an IP address space into networks.) Tj
0 -30 Td
(The subnet mask is used to determine which part is network and host.) Tj
0 -30 Td
(Default subnet masks:) Tj
0 -30 Td
(Class A: 255.0.0.0) Tj
0 -30 Td
(Class B: 255.255.0.0) Tj
0 -30 Td
(Class C: 255.255.255.0) Tj
ET
endstream
endobj
xref
0 6
0000000000 65535 f
0000000009 00000 n
0000000058 00000 n
0000000127 00000 n
0000000260 00000 n
0000000333 00000 n
trailer<</Size 6/Root 1 0 R>>
startxref
1457
%%EOF';

$pdf_ejemplo = '%PDF-1.0
1 0 obj<</Type/Catalog/Pages 2 0 R>>endobj
2 0 obj<</Type/Pages/Kids[3 0 R]/Count 1>>endobj
3 0 obj<</Type/Page/Parent 2 0 R/Resources<</Font<</F1 4 0 R>>>>/MediaBox[0 0 612 792]/Contents 5 0 R>>endobj
4 0 obj<</Type/Font/Subtype/Type1/BaseFont/Helvetica>>endobj
5 0 obj<</Length 600>>
stream
BT
/F1 24 Tf
100 700 Td
(Example Document) Tj
ET
BT
/F1 12 Tf
100 650 Td
(This is an example document for testing purposes.) Tj
0 -60 Td
(Key Concepts:) Tj
0 -30 Td
(1. Documentation is important for understanding systems) Tj
0 -30 Td
(2. Examples help illustrate and clarify concepts) Tj
0 -30 Td
(3. Testing ensures quality and reliability) Tj
0 -60 Td
(Summary:) Tj
0 -30 Td
(Testing systems with valid PDFs helps ensure that the) Tj
0 -30 Td
(processing pipeline works correctly.) Tj
0 -30 Td
(This example demonstrates proper document handling.) Tj
ET
endstream
endobj
xref
0 6
0000000000 65535 f
0000000009 00000 n
0000000058 00000 n
0000000127 00000 n
0000000260 00000 n
0000000333 00000 n
trailer<</Size 6/Root 1 0 R>>
startxref
983
%%EOF';

file_put_contents(__DIR__ . '/uploads/11/ipv4.pdf', $pdf_ipv4);
file_put_contents(__DIR__ . '/uploads/11/ejemplo.pdf', $pdf_ejemplo);

echo "✓ PDFs creados:\n";
echo "  - ipv4.pdf: " . strlen($pdf_ipv4) . " bytes\n";
echo "  - ejemplo.pdf: " . strlen($pdf_ejemplo) . " bytes\n";
?>
