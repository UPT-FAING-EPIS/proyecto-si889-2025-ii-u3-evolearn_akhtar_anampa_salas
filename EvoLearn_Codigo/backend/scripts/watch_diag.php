<?php
/**
 * Real-time diagnostic monitor for generate_summary.php requests
 * Muestra en tiempo real los logs de diagnóstico mientras haces análisis
 */

$diagLog = __DIR__ . '/../logs/generate_summary_diag.log';

if (!file_exists($diagLog)) {
    echo "El archivo de diagnóstico aún no existe. Realizando un análisis...\n";
    echo "Esperando primeras peticiones...\n\n";
} else {
    echo "Leyendo logs anteriores:\n";
    $content = file_get_contents($diagLog);
    echo $content;
}

echo "\n=== MONITOREANDO EN VIVO (Ctrl+C para salir) ===\n\n";

$lastPos = filesize($diagLog) ?: 0;
$checkInterval = 1; // segundos

while (true) {
    sleep($checkInterval);
    
    if (!file_exists($diagLog)) {
        continue;
    }
    
    $currentSize = filesize($diagLog);
    
    if ($currentSize > $lastPos) {
        $handle = fopen($diagLog, 'r');
        if ($handle) {
            fseek($handle, $lastPos);
            while (!feof($handle)) {
                $line = fgets($handle);
                if ($line !== false) {
                    echo $line;
                }
            }
            fclose($handle);
            $lastPos = $currentSize;
        }
    }
}
