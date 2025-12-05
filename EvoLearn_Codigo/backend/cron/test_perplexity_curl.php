<?php
// Test Perplexity connectivity (no key) - we expect 401/400 or SSL error; used for diagnostics
$ch = curl_init('https://api.perplexity.ai/v1/answers');
curl_setopt_array($ch, [
    CURLOPT_RETURNTRANSFER => true,
    CURLOPT_POST => true,
    CURLOPT_POSTFIELDS => json_encode(["model"=>"dummy","messages"=>[]]),
    CURLOPT_HTTPHEADER => [ 'Content-Type: application/json', 'Authorization: Bearer INVALID' ],
    CURLOPT_TIMEOUT => 15,
    CURLOPT_CONNECTTIMEOUT => 10,
]);
$resp = curl_exec($ch);
$err = curl_error($ch);
$code = curl_getinfo($ch, CURLINFO_HTTP_CODE);
curl_close($ch);
echo "CURL_CODE={$code}\n";
echo "CURL_ERR=" . ($err ?: '<none>') . "\n";
echo "RESP=" . substr(($resp?:''),0,1200) . "\n";
