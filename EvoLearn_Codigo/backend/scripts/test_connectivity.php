<?php
/**
 * Quick test to check if backend is reachable from different addresses
 * and if generate_summary.php endpoint works
 */

echo "=== BACKEND CONNECTIVITY TEST ===\n\n";

$backendTests = [
    'http://127.0.0.1:8003' => 'Local loopback (Desktop)',
    'http://10.0.2.2:8003' => 'Android Emulator loopback',
    'http://localhost:8003' => 'Localhost DNS',
];

// Also try localhost and common IP patterns
$hostname = gethostname();
$localIp = gethostbyname($hostname);
if ($localIp && $localIp !== $hostname) {
    $backendTests["http://$localIp:8003"] = "Local machine IP ($localIp)";
}

foreach ($backendTests as $url => $desc) {
    echo "Testing: $desc\n";
    echo "  URL: $url\n";
    
    // Test if we can reach the server
    $testUrl = $url . '/api/generate_summary.php';
    $ch = curl_init($testUrl);
    curl_setopt_array($ch, [
        CURLOPT_RETURNTRANSFER => true,
        CURLOPT_TIMEOUT => 5,
        CURLOPT_NOBODY => true, // HEAD request
    ]);
    
    $result = curl_exec($ch);
    $httpCode = curl_getinfo($ch, CURLINFO_HTTP_CODE);
    $error = curl_error($ch);
    curl_close($ch);
    
    if ($error) {
        echo "  ✗ UNREACHABLE: $error\n";
    } else {
        echo "  ✓ REACHABLE (HTTP $httpCode)\n";
    }
    echo "\n";
}

echo "=== SUGGESTIONS ===\n";
echo "1. Check what IP/port your PHP backend is running on\n";
echo "2. Run: php -S 0.0.0.0:8003 -t backend/ (to make it accessible from all interfaces)\n";
echo "3. Share the correct IP:port with the app via --dart-define=BASE_URL=http://<ip>:<port>\n";
echo "4. Make sure firewall allows the port\n";
