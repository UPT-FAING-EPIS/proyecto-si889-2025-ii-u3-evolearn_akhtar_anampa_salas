<?php
$url = 'https://generativelanguage.googleapis.com/v1/models?key=INVALID_KEY';
$ch = curl_init($url);
curl_setopt_array($ch, [
    CURLOPT_RETURNTRANSFER => true,
    CURLOPT_TIMEOUT => 15,
    CURLOPT_CONNECTTIMEOUT => 10,
    CURLOPT_SSL_VERIFYPEER => false,
    CURLOPT_SSL_VERIFYHOST => 0,
]);
$resp = curl_exec($ch);
$err = curl_error($ch);
$code = curl_getinfo($ch, CURLINFO_HTTP_CODE);
curl_close($ch);
echo "CURL_CODE={$code}\n";
echo "CURL_ERR=" . ($err ?: '<none>') . "\n";
echo "RESP=" . substr(($resp ?: ''), 0, 2000) . "\n";
