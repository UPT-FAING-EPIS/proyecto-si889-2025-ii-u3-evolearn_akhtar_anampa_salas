<?php
// Crear un PDF válido usando TCPDF
require_once __DIR__ . '/vendor/autoload.php';

// Crear PDF válido para pruebas
$pdf1 = new TCPDF();
$pdf1->AddPage();
$pdf1->SetFont('Helvetica', 'B', 16);
$pdf1->Cell(0, 10, 'IPv4 Addressing', 0, 1, 'C');
$pdf1->SetFont('Helvetica', '', 12);
$pdf1->Ln(5);
$pdf1->MultiCell(0, 5, 'IPv4 (Internet Protocol version 4) is the fourth version of the Internet Protocol (IP). It is one of the core protocols of standards-based internetworking methods in the Internet and other packet-switched networks.

IPv4 addresses are 32-bit numbers written in four decimal numbers separated by periods (dots). For example: 192.168.1.1

Classful Addressing:
- Class A: 1.0.0.0 to 126.255.255.255
- Class B: 128.0.0.0 to 191.255.255.255
- Class C: 192.0.0.0 to 223.255.255.255
- Class D: 224.0.0.0 to 239.255.255.255
- Class E: 240.0.0.0 to 255.255.255.255

Subnetting allows dividing an IP address space into two or more networks. The subnet mask is used to determine which part of the IP address is the network and which part is the host.

Default subnet masks:
- Class A: 255.0.0.0
- Class B: 255.255.0.0
- Class C: 255.255.255.0');

$pdf1->Output(__DIR__ . '/uploads/11/ipv4.pdf', 'F');
echo "Created valid PDF: uploads/11/ipv4.pdf\n";

// Crear otro PDF válido
$pdf2 = new TCPDF();
$pdf2->AddPage();
$pdf2->SetFont('Helvetica', 'B', 16);
$pdf2->Cell(0, 10, 'Example Document', 0, 1, 'C');
$pdf2->SetFont('Helvetica', '', 12);
$pdf2->Ln(5);
$pdf2->MultiCell(0, 5, 'This is an example document for testing purposes.

Key concepts:
1. Documentation is important for understanding systems
2. Examples help illustrate concepts
3. Testing ensures quality

Summary:
Testing systems with valid PDFs helps ensure the processing pipeline works correctly.');

$pdf2->Output(__DIR__ . '/uploads/11/ejemplo.pdf', 'F');
echo "Created valid PDF: uploads/11/ejemplo.pdf\n";
?>
