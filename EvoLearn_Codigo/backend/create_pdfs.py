from fpdf import FPDF
import os

# Crear directorios si no existen
os.makedirs("uploads/11", exist_ok=True)

# Crear PDF para ipv4
pdf = FPDF()
pdf.add_page()
pdf.set_font("Arial", "B", 16)
pdf.cell(0, 10, "IPv4 Addressing and Subnetting", 0, 1)

pdf.set_font("Arial", "", 12)
pdf.cell(0, 10, "IPv4 is the fourth version of the Internet Protocol.", 0, 1)
pdf.cell(0, 10, "IPv4 addresses are 32-bit numbers written in four decimal numbers.", 0, 1)
pdf.cell(0, 10, "Example: 192.168.1.1", 0, 1)
pdf.ln(5)

pdf.set_font("Arial", "B", 12)
pdf.cell(0, 10, "Classful Addressing:", 0, 1)
pdf.set_font("Arial", "", 12)

classful = [
    "Class A: 1.0.0.0 to 126.255.255.255",
    "Class B: 128.0.0.0 to 191.255.255.255",
    "Class C: 192.0.0.0 to 223.255.255.255",
    "Class D: 224.0.0.0 to 239.255.255.255",
    "Class E: 240.0.0.0 to 255.255.255.255"
]

for item in classful:
    pdf.cell(0, 10, "  " + item, 0, 1)

pdf.ln(5)
pdf.set_font("Arial", "B", 12)
pdf.cell(0, 10, "Subnetting:", 0, 1)
pdf.set_font("Arial", "", 12)
pdf.cell(0, 10, "Subnetting allows dividing an IP address space into multiple networks.", 0, 1)
pdf.cell(0, 10, "The subnet mask determines the network and host portions.", 0, 1)
pdf.ln(5)

pdf.set_font("Arial", "B", 12)
pdf.cell(0, 10, "Default Subnet Masks:", 0, 1)
pdf.set_font("Arial", "", 12)

masks = [
    "Class A: 255.0.0.0",
    "Class B: 255.255.0.0",
    "Class C: 255.255.255.0"
]

for mask in masks:
    pdf.cell(0, 10, "  " + mask, 0, 1)

pdf.output("uploads/11/ipv4.pdf")
print("✓ Created: uploads/11/ipv4.pdf")

# Crear PDF para ejemplo
pdf2 = FPDF()
pdf2.add_page()
pdf2.set_font("Arial", "B", 16)
pdf2.cell(0, 10, "Example Document for Testing", 0, 1)

pdf2.set_font("Arial", "", 12)
pdf2.cell(0, 10, "This is an example document for testing the cloud analysis system.", 0, 1)
pdf2.ln(5)

pdf2.set_font("Arial", "B", 12)
pdf2.cell(0, 10, "Key Concepts:", 0, 1)
pdf2.set_font("Arial", "", 12)

concepts = [
    "1. Documentation is important for understanding systems",
    "2. Examples help illustrate and clarify complex concepts",
    "3. Testing ensures quality and reliability",
    "4. Cloud systems provide scalability"
]

for concept in concepts:
    pdf2.cell(0, 10, "  " + concept, 0, 1)

pdf2.ln(5)
pdf2.set_font("Arial", "B", 12)
pdf2.cell(0, 10, "Summary:", 0, 1)
pdf2.set_font("Arial", "", 12)
pdf2.cell(0, 10, "Testing with valid PDFs ensures the pipeline works correctly.", 0, 1)
pdf2.cell(0, 10, "This example demonstrates proper document handling.", 0, 1)

pdf2.output("uploads/11/ejemplo.pdf")
print("✓ Created: uploads/11/ejemplo.pdf")
