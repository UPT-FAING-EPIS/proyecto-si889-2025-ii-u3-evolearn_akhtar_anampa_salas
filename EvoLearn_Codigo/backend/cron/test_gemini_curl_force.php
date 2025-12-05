<?php
$ca = getenv('USERPROFILE') . '\\AppData\\Local\\cacert\\cacert.pem';
$url = 'https://generativelanguage.googleapis.com/v1/models?key=INVALID_KEY';
$ch = curl_init($url);
curl_setopt_array($ch, [
    CURLOPT_RETURNTRANSFER => true,
    CURLOPT_TIMEOUT => 15,
    CURLOPT_CONNECTTIMEOUT => 10,
]);
// Force CA file explicitly
curl_setopt($ch, CURLOPT_CAINFO, $ca);
$resp = curl_exec($ch);
$err = curl_error($ch);
$code = curl_getinfo($ch, CURLINFO_HTTP_CODE);
curl_close($ch);
echo "CA used: $ca\n";
echo "CURL_CODE={$code}\n";
echo "CURL_ERR=" . ($err ?: '<none>') . "\n";
echo "RESP=" . substr(($resp ?: ''), 0, 2000) . "\n";
