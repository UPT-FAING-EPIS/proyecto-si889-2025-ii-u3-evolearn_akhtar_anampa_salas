<?php
$ch = curl_init('https://api.perplexity.ai/v1/answers');
curl_setopt_array($ch, [
  CURLOPT_RETURNTRANSFER => true,
  CURLOPT_POST => true,
  CURLOPT_POSTFIELDS => json_encode(["model"=>"llama-3","messages"=>[["role"=>"user","content"=>"ping"]]]),
  CURLOPT_HTTPHEADER => ["Content-Type: application/json", "Authorization: Bearer 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"],
  CURLOPT_TIMEOUT => 15,
  CURLOPT_CONNECTTIMEOUT => 5,
  // Nota: ruta de cacert específica de Windows; en Debian usa /etc/ssl/certs/ca-certificates.crt u otra ruta válida
  // Este script es solo de prueba, pero hacemos la ruta configurable por entorno.
  CURLOPT_CAINFO => getenv('CACERT_PATH') ?: '/etc/ssl/certs/ca-certificates.crt',
]);
$resp = curl_exec($ch);
$err = curl_error($ch);
$no = curl_errno($ch);
curl_close($ch);
var_dump($no, $err, substr((string)$resp, 0, 500));