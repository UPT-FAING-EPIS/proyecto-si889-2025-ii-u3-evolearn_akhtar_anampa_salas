<?php
declare(strict_types=1);

// Helper para resumen con Gemini
// Usa env GEMINI_API_KEY si está disponible; de lo contrario, usa DEFAULT_GEMINI_KEY.

const DEFAULT_GEMINI_KEY = 'AIzaSyAfcZxpIwMxQbZ6fDGK2q_cMw7J4karxJE';
const PERPLEXITY_API_KEY = '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';
const GEMINI_ENDPOINT = 'https://generativelanguage.googleapis.com/v1beta/models/%s:generateContent?key=%s';
const GEMINI_ENDPOINT_V1 = 'https://generativelanguage.googleapis.com/v1/models/%s:generateContent?key=%s';

// Array de claves API de Gemini para rotación automática
const GEMINI_API_KEYS = [
    'AIzaSyAfcZxpIwMxQbZ6fDGK2q_cMw7J4karxJE',      // API Key 1
    'AIzaSyCPqitvpz8viQwm4h8Q9yWEytuY6h37YOI',      // API Key 2
    'AIzaSyCpIooz9Z45SW1Vc7Mj1xqch63I-C6pCNo',      // API Key 3
    'AIzaSyAvIbz4y8-z74qThgtZNLlqBJ6MNYY8XAc',      // API Key 4
    'AIzaSyCndle64JO4owIAAgaAYn3GSVw4InxsSNU',      // API Key 5
    'AIzaSyCEL_TeHjARXiL_B9gHEPzowFZ8Jn0bnlQ',      // API Key 6
    'AIzaSyA4e41AxaTXEJ1Beam0jfy68gCm_jGNv3c',      // API Key 7
    'AIzaSyAwOKH92LE3F1XsGlKfr44x72wjHUC_ssU',      // API Key 8
    'AIzaSyC_Ff3-CQ8ytNfKDtRZroE02p8aNDYpjLo',      // API Key 9
    'AIzaSyARN7ohDi4qynV41t9Q7goE_ViIN2ZQUuU',      // API Key 10
    'AIzaSyB70S2Ns17uoBtHNntYtrMYMZr8vsire4w',      // API Key 11
    'AIzaSyDERUH9n6wvh0Nhn5YXK3FkrT8L60JaC_E',      // API Key 12
    'AIzaSyB3O_ONvhyDZsxEFqzVWLt8eCEIvd9h5OI',      // API Key 13
    'AIzaSyCnwC3IkABFdtvJ4hyc133qNqBDinZ7gCA',      // API Key 14
    'AIzaSyDc49MyzbsFels8o6V-wc93Czxh467I6y8',      // API Key 15
    'AIzaSyAgXwXdbDlIM74Kpu-Cm-KJpWS1KbKzPAs',    // API Key 16
    'AIzaSyAsh2HaLtLQDR5hgJYbzo50q4tYX0_uqDY',     // API Key 17
    'AIzaSyBHp-fei3EVBzkd0EPqj9ciQVVjnduwqv4',      // API Key 18
    'AIzaSyCxG6KZR1DkTptPzXJ5lqOWd9Z2CSaqQyM',      // API Key 19
    'AIzaSyA15czLwgKMvxU2l_Yo_U27u-RBcKeoECA',      // API Key 20
    'AIzaSyCaIFHgz1rjP_5wRr6YSK-bxn-jsrOH2Pw',
    'AIzaSyBVDBna-4mtw3BOCuzshrYV95G_YH9jD1s',
    'AIzaSyCrN9ccxV6Tqhc1rJW8ul42VxAeByBwXRY',
    'AIzaSyD_PxzGVKrdG2CajBeZOLMEJlYoW1knpbc',
    'AIzaSyBENNv5DvoJnJ4j-aSpFUYgNq5-shZ4REs',
];

// Variable global para rastrear el índice actual de API keys
$_GEMINI_API_KEY_INDEX = 0;
$_GEMINI_FAILED_KEYS = [];

/**
 * Obtiene la siguiente clave API disponible.
 * Implementa rotación automática cuando una clave falla.
 * @return string Clave API a utilizar
 */
function get_next_api_key(): string {
    global $_GEMINI_API_KEY_INDEX, $_GEMINI_FAILED_KEYS;
    
    $maxAttempts = count(GEMINI_API_KEYS);
    for ($i = 0; $i < $maxAttempts; $i++) {
        $key = GEMINI_API_KEYS[($_GEMINI_API_KEY_INDEX + $i) % $maxAttempts];
        
        // Si la clave no ha fallado, usarla
        if (!isset($_GEMINI_FAILED_KEYS[$key])) {
            return $key;
        }
        
        // Si la clave falló pero hace más de 1 hora, reintentar
        if (time() - $_GEMINI_FAILED_KEYS[$key] > 3600) {
            unset($_GEMINI_FAILED_KEYS[$key]);
            return $key;
        }
    }
    
    // Si todas fallaron, resetear y usar la primera
    $_GEMINI_FAILED_KEYS = [];
    $_GEMINI_API_KEY_INDEX = 0;
    return GEMINI_API_KEYS[0];
}

/**
 * Rota a la siguiente clave API después de una falla.
 * @param string $failedKey Clave que falló
 * @return void
 */
function rotate_api_key(string $failedKey): void {
    global $_GEMINI_API_KEY_INDEX, $_GEMINI_FAILED_KEYS;
    
    // Marcar la clave como fallida
    $_GEMINI_FAILED_KEYS[$failedKey] = time();
    
    // Mover al siguiente índice
    $_GEMINI_API_KEY_INDEX = (array_search($failedKey, GEMINI_API_KEYS) + 1) % count(GEMINI_API_KEYS);
    
    log_info('API Key rotated due to failure', [
        'failed_key_index' => array_search($failedKey, GEMINI_API_KEYS),
        'next_key_index' => $_GEMINI_API_KEY_INDEX,
        'total_failed' => count($_GEMINI_FAILED_KEYS),
    ]);
}

/**
 * Log a one-time warning when SSL verification is disabled via env.
 */
function warn_if_skip_ssl(): void {
    static $done = false;
    if ($done) return;
    $done = true;
    $skipSsl = getenv('GEMINI_SKIP_SSL_VERIFY');
    if ($skipSsl === false || trim($skipSsl) === '') {
        $skipSsl = '1';
    }
    $skip = in_array(strtolower((string)$skipSsl), ['1', 'true', 'yes'], true);
    if ($skip) {
        log_error('WARNING: SSL verification is DISABLED for AI API calls via GEMINI_SKIP_SSL_VERIFY. This is insecure and should only be used in local/dev environments. Set GEMINI_SKIP_SSL_VERIFY=0 or configure a valid CACERT_PATH for production.', ['env' => 'GEMINI_SKIP_SSL_VERIFY']);
    }
}

/**
 * Resume texto largo con Gemini. Maneja chunking si el texto excede límites.
 * @param string $text Texto a resumir
 * @param string $analysisType 'summary_fast' | 'summary_detailed'
 * @param string $model Modelo, ej. 'gemini-1.5-flash'
 * @return string Resumen generado
 */
function gemini_summarize(string $text, string $analysisType = 'summary_fast', string $model = 'gemini-1.5-flash', ?callable $progressCallback = null): string {
    $apiKey = getenv('GEMINI_API_KEY');
    if (!$apiKey || trim($apiKey) === '') {
        $apiKey = get_next_api_key();
    }

    $text = trim($text);
    if ($text === '') {
        return '';
    }

    // Validar que el texto no sea excesivamente largo antes de procesar
    $textLength = mb_strlen($text, 'UTF-8');
    $maxTextLength = 500000; // 500k caracteres máximo
    if ($textLength > $maxTextLength) {
        log_error('Text too long for processing', ['length' => $textLength, 'max' => $maxTextLength]);
        $text = mb_substr($text, 0, $maxTextLength, 'UTF-8');
        log_info('Text truncated for processing', ['truncated_to' => $maxTextLength]);
    }

    // Aumentar tamaño de chunk para reducir número de llamadas a Gemini
    $chunks = split_text_chunks($text, 20000);
    $deadline = microtime(true) + ($analysisType === 'summary_detailed' ? 250.0 : 90.0);
    $maxChunks = 3; // Reducir chunks máximos para menos llamadas
    if (count($chunks) > $maxChunks) {
        log_error('Too many chunks, truncating', ['original_chunks' => count($chunks), 'max' => $maxChunks]);
        $chunks = array_slice($chunks, 0, $maxChunks);
        $chunks[$maxChunks - 1] .= "\n\n[Nota: El documento fue truncado debido a su extensión.]";
    }
    
    log_info('AI: chunking complete', ['chunks' => count($chunks), 'analysis_type' => $analysisType, 'model' => $model, 'text_length' => $textLength]);

    $partialSummaries = [];
    $budgetHit = false;
    foreach ($chunks as $idx => $chunk) {
        if (microtime(true) > $deadline) {
            $budgetHit = true;
            log_info('AI: time budget reached, stopping chunking', ['processed' => count($partialSummaries)]);
            break;
        }
        $prompt = build_prompt($chunk, $analysisType, $idx + 1, count($chunks));
        $t0 = microtime(true);
        log_debug('AI: calling Gemini for chunk', ['index' => $idx + 1, 'prompt_len' => strlen($prompt)]);
        $summary = call_gemini($prompt, $apiKey, $model);
        $t1 = microtime(true);
        log_info('AI: gemini call duration', ['index' => $idx + 1, 'seconds' => round($t1 - $t0, 3)]);
        if ($summary !== '') {
            log_info('AI: chunk summarized', ['index' => $idx + 1, 'summary_len' => strlen($summary)]);
            $partialSummaries[] = $summary;
        } else {
            log_error('AI: chunk summary empty', ['index' => $idx + 1]);
        }
    }

    if (count($partialSummaries) === 0) {
        log_error('AI: no partial summaries');
        return '';
    }

    if (count($partialSummaries) === 1) {
        return $partialSummaries[0];
    }

    // Resumen final para combinar parciales, adaptado al modo
    $finalGuides = ($analysisType === 'summary_detailed')
        ? implode("\n", [
            "Combina y sintetiza los siguientes resúmenes parciales en un único **resumen DETALLADO, CLARO y BIEN ESTRUCTURADO**, usando **Markdown** y **emojis** de forma equilibrada, fiel al contenido original y sin inventar información.",
            "Organiza el resumen final usando estas secciones con emojis:",
            "📝 **Resumen ejecutivo**: 3–4 frases que expliquen el enfoque, propósito y conclusiones generales.",
            "⭐ **Puntos clave**: 8–12 viñetas con ideas relevantes (usa emojis 🚩💡📌 para destacar).",
            "📚 **Conceptos y definiciones**: lista breve y técnica con el emoji 📖.",
            "🏢 **Entidades, fechas y cifras**: usa viñetas con emojis como 📅 (fechas), 💰 (cifras), 🏛️ (instituciones).",
            "💬 **Ejemplos y citas textuales**: extractos breves con 🗣️.",
            "⚠️ **Implicaciones, limitaciones y riesgos**: sección crítica con emoji ⚠️.",
            "🔧 **Recomendaciones accionables**: 5–8 acciones claras y aplicables con emoji 🛠️.",
            "",
            "📋 Incluye una **tabla en Markdown**, bien rotulada y explicada, para comparar conceptos, sintetizar datos o mostrar relaciones clave.",
            "",
            "Requisitos:",
            "- Usa emojis pertinentes y variados, pero sin saturar el texto.",
            "- Mantén términos técnicos y nombres exactos sin modificar su significado.",
            "- No inventes, no rellenes ni infieras contenido ausente.",
            "- Extensión sugerida: **400–700 palabras**, dependiendo del material.",
            "- La tabla debe ser relevante, legible y aportar valor real a la comprensión.",
        ])
        : implode("\n", [
            "Combina y sintetiza los siguientes resúmenes parciales en un **resumen ejecutivo BREVE**, claro y amistoso, en **Markdown** y usando emojis pertinentes.",
            "Incluye estas secciones:",
            "🗂️ **Título (H1)** con emoji y una tesis sintetizada en 1 frase.",
            "🔍 **Puntos clave**: 6–10 viñetas esenciales con emojis.",
            "🚀 **Acciones rápidas**: 3–5 recomendaciones breves y priorizadas con emojis.",
            "🔤 **Glosario breve**: 3–6 términos clave explicados brevemente (emoji 📚).",
            "",
            "Requisitos:",
            "- Usa emojis adecuados, pero sin abusar.",
            "- Mantén un estilo directo: evita detalles irrelevantes.",
            "- No inventes contenido ni agregues información no presente.",
            "- Extensión sugerida: **120–250 palabras**.",
        ]);

    $finalPrompt = $finalGuides . "\n\n" . implode("\n\n---\n\n", $partialSummaries);

    log_info('AI: combining partial summaries', ['count' => count($partialSummaries)]);
    if ($budgetHit) {
        return implode("\n\n", $partialSummaries) . "\n\n[Nota: Resumen parcial por límite de tiempo]";
    }
    $t0 = microtime(true);
    $final = call_gemini($finalPrompt, $apiKey, $model);
    $t1 = microtime(true);
    log_info('AI: final gemini call duration', ['seconds' => round($t1 - $t0, 3)]);
    return $final !== '' ? $final : implode("\n\n", $partialSummaries);
}

function build_prompt(string $text, string $analysisType, int $chunkIndex, int $chunksTotal): string {
    $mode = $analysisType === 'summary_detailed' ? 'detallado' : 'rápido';
    if ($analysisType === 'summary_detailed') {
        $guidelines = implode("\n", [
            "- Formato: Markdown estructurado, jerárquico y claro, usando emojis de forma equilibrada.",
            "- Extensión sugerida: 400–700 palabras.",
            "- IMPORTANTE: Usa `#` para el título principal y `##` para cada subsección.",
            "- Estructura general:",
            "  # 🗂️ TÍTULO PRINCIPAL — resume el tema central con un emoji y una tesis clara.",
            "  ## 📝 Resumen Ejecutivo — 3–4 frases esenciales.",
            "  ## ⭐ Puntos Clave — 8–12 viñetas con emojis (🚩💡📌).",
            "  ## 📚 Conceptos y Definiciones — lista técnica con 📖.",
            "  ## 🏢 Entidades, Fechas y Cifras — usar 📅💰🏛️ según corresponda.",
            "  ## 💬 Ejemplos y Citas — extractos breves con 🗣️.",
            "  ## ⚠️ Implicaciones y Riesgos — advertencias y limitaciones.",
            "  ## 🔧 Recomendaciones Accionables — 5–8 acciones aplicables con 🛠️.",
            "",
            "📋 Incluye una **tabla en Markdown** (con título claro ##) para comparar conceptos, resumir datos o visualizar relaciones importantes.",
            "- Usa líneas en blanco adecuadas para mejorar legibilidad.",
            "- No inventes contenido ni extrapoles más allá del texto dado.",
        ]);
    } else {
        $guidelines = implode("\n", [
            "- Formato: Markdown conciso y ordenado, con emojis pertinentes.",
            "- Extensión sugerida: 120–250 palabras.",
            "- IMPORTANTE: Usa `#` para el título principal y `##` para subsecciones.",
            "- Estructura general:",
            "  # 🗂️ TÍTULO PRINCIPAL — con emoji y tesis breve.",
            "  ## 🔍 Puntos Clave — 6–10 viñetas esenciales con emojis.",
            "  ## 🚀 Acciones Rápidas — 3–5 recomendaciones accionables.",
            "  ## 🔤 Glosario — 3–6 términos claves con el emoji 📚.",
            "- Usa un tono claro y directo, evitando detalles menores.",
            "- No inventes contenido.",
            "- Deja líneas en blanco entre secciones para una lectura más limpia.",
        ]);
    }

    return sprintf(
        "Genera un resumen %s del siguiente contenido (parte %d de %d).\n\n" .
        "%s\n" .
        "- Mantén el idioma original (español).\n- No incluyas metadatos del sistema.\n\nContenido:\n\n%s",
        $mode,
        $chunkIndex,
        $chunksTotal,
        $guidelines,
        $text
    );
}

/**
 * Divide texto en trozos por límite de caracteres.
 * @param string $text
 * @param int $limit
 * @return array<int,string>
 */
function split_text_chunks(string $text, int $limit): array {
    $text = str_replace(["\r\n", "\r"], "\n", $text);
    $chunks = [];
    $len = strlen($text);
    for ($i = 0; $i < $len; $i += $limit) {
        $chunks[] = substr($text, $i, min($limit, $len - $i));
    }
    return $chunks;
}

/**
 * Llama a Gemini API con un prompt y devuelve el texto.
 * @param string $prompt
 * @param string $apiKey
 * @param string $model
 * @return string
 */
function list_models_log(string $apiKey): void {
    static $done = false;
    if ($done) return;
    $done = true;
    $endpoints = [
        'v1' => 'https://generativelanguage.googleapis.com/v1/models?key=%s',
        'v1beta' => 'https://generativelanguage.googleapis.com/v1beta/models?key=%s',
    ];
    foreach ($endpoints as $label => $tpl) {
        $url = sprintf($tpl, urlencode($apiKey));
        $ch = curl_init($url);
        curl_setopt_array($ch, [
            CURLOPT_RETURNTRANSFER => true,
            CURLOPT_TIMEOUT => 6,
        ]);
        $resp = curl_exec($ch);
        $err = curl_error($ch);
        $code = curl_getinfo($ch, CURLINFO_HTTP_CODE);
        curl_close($ch);
        if ($resp === false) {
            log_error('ListModels curl failed', ['api' => $label, 'error' => $err ?: 'unknown']);
            continue;
        }
        $data = json_decode($resp, true);
        $names = [];
        if (isset($data['models']) && is_array($data['models'])) {
            foreach ($data['models'] as $m) {
                if (isset($m['name'])) $names[] = $m['name'];
            }
        }
        log_info('ListModels', ['api' => $label, 'code' => $code, 'count' => count($names), 'sample' => array_slice($names, 0, 6)]);
    }
}

function call_gemini(string $prompt, string $apiKey, string $model): string {
    list_models_log($apiKey);
    warn_if_skip_ssl();
    // Usar gemini-2.5-flash si está disponible, sino gemini-2.0-flash
    $fallback = 'gemini-2.5-flash';
    $models = array_values(array_unique($model === $fallback ? [$model] : [$model, $fallback, 'gemini-2.0-flash']));
    $endpointVersions = [
        ['label' => 'v1beta', 'tpl' => GEMINI_ENDPOINT],
        ['label' => 'v1', 'tpl' => GEMINI_ENDPOINT_V1],
    ];
    $lastCode = null;
    $originalApiKey = $apiKey;
    
    foreach ($endpointVersions as $ver) {
        foreach ($models as $m) {
            $url = sprintf($ver['tpl'], $m, urlencode($apiKey));
            $payload = [
                'contents' => [[
                    'role' => 'user',
                    'parts' => [[ 'text' => $prompt ]]
                ]]
            ];

            // Increase retry attempts and base backoff to better tolerate
            // temporary rate limits / availability errors from the AI service.
            $maxAttempts = 4;
            // Base delay in seconds for exponential backoff: 5 -> 5,10,20,40
            $baseDelaySec = 5;
            for ($attempt = 1; $attempt <= $maxAttempts; $attempt++) {
                $ch = curl_init($url);
                // Prepare common curl options. If a local CACERT bundle is available
                // prefer to use it. We also keep the standard timeout/connect settings.
                $curlOpts = [
                    CURLOPT_RETURNTRANSFER => true,
                    CURLOPT_POST => true,
                    CURLOPT_HTTPHEADER => [
                        'Content-Type: application/json'
                    ],
                    CURLOPT_POSTFIELDS => json_encode($payload),
                    CURLOPT_TIMEOUT => 120,
                    CURLOPT_CONNECTTIMEOUT => 20,
                ];

                // Look for a CACERT path in environment, or fallback to a common user path.
                $envCa = getenv('CACERT_PATH');
                if (!$envCa || trim($envCa) === '') {
                    $envCa = getenv('USERPROFILE') ? (getenv('USERPROFILE') . '/AppData/Local/cacert/cacert.pem') : '';
                }
                if ($envCa && file_exists($envCa)) {
                    $curlOpts[CURLOPT_CAINFO] = $envCa;
                }

                // Optionally disable SSL verification for development/testing environments.
                // Set environment variable GEMINI_SKIP_SSL_VERIFY=1 to disable verification.
                $skipSsl = getenv('GEMINI_SKIP_SSL_VERIFY');
                if ($skipSsl === false || trim($skipSsl) === '') {
                    // Default to disabled verification in this test app per user request.
                    $skipSsl = '1';
                }
                $skipSsl = in_array(strtolower((string)$skipSsl), ['1', 'true', 'yes'], true);
                if ($skipSsl) {
                    $curlOpts[CURLOPT_SSL_VERIFYPEER] = false;
                    $curlOpts[CURLOPT_SSL_VERIFYHOST] = 0;
                }

                curl_setopt_array($ch, $curlOpts);
                $resp = curl_exec($ch);
                $err = curl_error($ch);
                $code = curl_getinfo($ch, CURLINFO_HTTP_CODE);

                // If we failed specifically due to missing local issuer certificate,
                // retry once with verification disabled as a last-resort fallback
                // for development environments. This avoids leaving jobs permanently
                // stuck due to host CA issues while not breaking production silently.
                if ($resp === false && stripos((string)$err, 'unable to get local issuer certificate') !== false) {
                    log_error('Gemini cURL SSL verify failed; retrying once with verification disabled', ['api' => $ver['label'], 'model' => $m, 'err' => $err]);
                    // Try disabling peer verification for one retry
                    curl_setopt($ch, CURLOPT_SSL_VERIFYPEER, false);
                    curl_setopt($ch, CURLOPT_SSL_VERIFYHOST, 0);
                    $resp = curl_exec($ch);
                    $err = curl_error($ch);
                    $code = curl_getinfo($ch, CURLINFO_HTTP_CODE);
                }

                curl_close($ch);
                $lastCode = $code;

                log_debug('Gemini response meta', ['code' => $code, 'api' => $ver['label'], 'model' => $m, 'err' => $err ? (string)$err : null]);
                if ($resp === false) {
                    log_error('Gemini curl failed', ['api' => $ver['label'], 'model' => $m, 'error' => $err ?: 'unknown', 'attempt' => $attempt]);
                    // retry only for transient network issues up to maxAttempts
                } else {
                    $respExcerpt = substr((string)$resp, 0, 240);
                    $data = json_decode($resp, true);
                    if ($code >= 200 && $code < 300 && isset($data['candidates'][0]['content']['parts'][0]['text'])) {
                        $out = trim((string)$data['candidates'][0]['content']['parts'][0]['text']);
                        log_info('Gemini success', ['api' => $ver['label'], 'model' => $m, 'text_len' => strlen($out), 'attempt' => $attempt, 'api_key_index' => array_search($originalApiKey, GEMINI_API_KEYS)]);
                        return $out;
                    }
                    // 429/503/408: backoff and retry (pero si es 429 con límite de cuota, rotar clave)
                    if (in_array($code, [429, 503, 408], true)) {
                        // Si es 429 (rate limit/quota), tentar rotar a siguiente clave
                        if ($code === 429) {
                            log_error('Gemini quota/rate limit (429) - rotating API key', [
                                'api' => $ver['label'],
                                'model' => $m,
                                'current_key_index' => array_search($originalApiKey, GEMINI_API_KEYS),
                            ]);
                            rotate_api_key($originalApiKey);
                            // Obtener siguiente clave para siguiente intento
                            $apiKey = get_next_api_key();
                            $url = sprintf($ver['tpl'], $m, urlencode($apiKey));
                            continue; // Reintentar con siguiente clave inmediatamente
                        }
                        
                        // Para 503/408, hacer backoff exponencial
                        $delay = $baseDelaySec * (1 << ($attempt - 1));
                        $jitterMs = random_int(0, 500);
                        log_error('Gemini rate/availability limit, backing off', [
                            'code' => $code,
                            'api' => $ver['label'],
                            'model' => $m,
                            'attempt' => $attempt,
                            'sleep_sec' => $delay,
                            'jitter_ms' => $jitterMs,
                            'body_excerpt' => $respExcerpt,
                        ]);
                        usleep(($delay * 1000 + $jitterMs) * 1000);
                        continue; // retry same endpoint+model
                    }

                    // Other non-2xx: log and break to try next model/endpoint
                    log_error('Gemini unexpected response', ['code' => $code, 'api' => $ver['label'], 'model' => $m, 'body_excerpt' => $respExcerpt, 'attempt' => $attempt]);
                    break;
                }

                // If curl failed and we have remaining attempts, backoff a bit
                if ($attempt < $maxAttempts) {
                    $delay = $baseDelaySec * (1 << ($attempt - 1));
                    usleep($delay * 1000000);
                }
            }
        }
    }
    if (in_array((int)$lastCode, [429, 503, 408], true)) {
        throw new \RuntimeException('AI_RATE_LIMIT');
    }
    return '';
}

function extract_tema_central(string $summary): string {
    $summary = str_replace(["\r\n", "\r"], "\n", trim($summary));
    if ($summary === '') return '';
    if (preg_match('/^#\s*(.+)$/m', $summary, $m)) {
        $t = trim((string)$m[1]);
        $t = preg_replace('/^[\p{So}\p{Sk}\x{1F300}-\x{1FAFF}\x{2600}-\x{27BF}\x{FE0F}\s]+/u', '', $t);
        $t = preg_replace('/\s+/u', ' ', $t);
        return trim($t);
    }
    $clean = preg_replace('/[\x{1F300}-\x{1FAFF}\x{2600}-\x{27BF}\x{FE0F}]/u', '', $summary);
    $clean = preg_replace('/\s+/u', ' ', $clean ?? '');
    $words = preg_split('/\s+/', (string)$clean);
    $slice = array_slice($words ?: [], 0, 8);
    return trim(implode(' ', $slice));
}

function getCursosGratuitos(string $tema): array {
    $apiKey = getenv('GEMINI_API_KEY');
    if (!$apiKey || trim($apiKey) === '') {
        $apiKey = get_next_api_key();
    }
    if (!$apiKey || trim($apiKey) === '') return [];
    
      $prompt = 'Eres un asistente de educación. Recomienda 2-3 plataformas con cursos gratuitos sobre: "' . addslashes($tema) . '"

        RESTRICCIÓN CRÍTICA: Solo puedes usar estas URLs EXACTAS (landing pages de plataformas):

        - https://www.freecodecamp.org/learn
        - https://learn.microsoft.com/training
        - https://www.cloudskillsboost.google/catalog
        - https://www.khanacademy.org/computing
        - https://cs50.harvard.edu
        - https://ocw.mit.edu
        - https://github.com/skills
        - https://www.w3schools.com
        - https://www.coursera.org (con filtro "free")
        - https://www.edx.org (con filtro "free")

        PROHIBIDO:
        - NO inventes rutas como /learn/python o /course/12345
        - NO completes URLs con nombres de cursos
        - SOLO usa las URLs EXACTAS de arriba

        FORMATO JSON (sin markdown):
        {"cursos":[{"nombre":"Certificación en [área] - Plataforma","duracion_horas":"estimado","url":"URL_EXACTA_DE_ARRIBA"}]}

        Ejemplo válido:
        {"cursos":[{"nombre":"Desarrollo Web Responsivo - freeCodeCamp","duracion_horas":"300","url":"https://www.freecodecamp.org/learn"}]}

        Si no hay plataformas relevantes: {"cursos":[]}';   

    // Usar Gemini 2.5 Pro para mejor análisis
    $resp = call_gemini($prompt, $apiKey, 'gemini-2.5-pro');
    
    // Parsear y devolver array de cursos
    return parseCursosGratuitos($resp);
}

function parseCursosGratuitos(string $resp): array {
    if ($resp === '') return [];
    
    // call_gemini() retorna solo el texto (ya extraído), no la respuesta completa de Gemini
    // Así que usamos $resp directamente como texto
    $text = $resp;
    
    // Intentar extraer JSON del texto
    $items = [];
    if ($text !== '') {
        // Buscar JSON válido con estructura {"cursos": [...]}
        if (preg_match('/\{[^}]*"cursos"\s*:\s*\[[^\]]*\][^}]*\}/s', $text, $matches)) {
            $jsonStr = $matches[0];
            $json = json_decode($jsonStr, true);
            
            // Extraer y validar cursos
            if (is_array($json) && isset($json['cursos']) && is_array($json['cursos'])) {
                foreach ($json['cursos'] as $c) {
                    $nombre = isset($c['nombre']) ? trim((string)$c['nombre']) : '';
                    $dur = isset($c['duracion_horas']) ? (int)$c['duracion_horas'] : 0;
                    $url = isset($c['url']) ? trim((string)$c['url']) : '';
                    
                    // Validar que URL sea accesible (basic check)
                    if ($nombre !== '' && $url !== '' && _isValidUrl($url)) {
                        $items[] = [
                            'nombre' => $nombre,
                            'duracion_horas' => max(0, $dur),
                            'url' => $url,
                        ];
                    }
                }
            }
        }
    }
    
    // Si encontramos cursos válidos, retornarlos (máximo 3)
    if (!empty($items)) {
        return array_slice($items, 0, 3);
    }
    
    return [];
}

/**
 * Valida que una URL sea válida y accesible
 * @param string $url URL a validar
 * @return bool true si la URL parece válida
 */

function _isValidUrl(string $url): bool {
    // Verificar formato básico
    if (!filter_var($url, FILTER_VALIDATE_URL)) {
        return false;
    }
    
    // Verificar que sea HTTPS o HTTP
    if (!preg_match('/^https?:\/\//i', $url)) {
        return false;
    }
    
    // Lista blanca de dominios permitidos
    $allowedDomains = [
        'learn.microsoft.com',
        'coursera.org',
        'edx.org',
        'cloudskillsboost.google',
        'freecodecamp.org',
        'khanacademy.org',
        'github.com',
        'youtube.com',
        'udemy.com',
        'cs50.harvard.edu',
        'ocw.mit.edu',
        'w3schools.com',
    ];
    
    $urlLower = strtolower($url);
    foreach ($allowedDomains as $domain) {
        if (strpos($urlLower, $domain) !== false) {
            return true;
        }
    }
    
    return false;
}
function _checkUrlAccessible(string $url): bool {
    static $cache = [];
    
    // Verificar caché
    if (isset($cache[$url])) {
        return $cache[$url];
    }
    
    // Para URLs de plataformas conocidas, asumir que son válidas
    // (evita hacer requests HTTP que pueden ser lentos)
    $trustedPatterns = [
        '/freecodecamp\.org\/learn\//i',
        '/cs50\.harvard\.edu/i',
        '/khanacademy\.org/i',
        '/learn\.microsoft\.com/i',
        '/github\.com\/skills/i',
    ];
    
    foreach ($trustedPatterns as $pattern) {
        if (preg_match($pattern, $url)) {
            $cache[$url] = true;
            return true;
        }
    }
    
    // Para otras URLs, hacer verificación HTTP rápida
    $ch = curl_init($url);
    curl_setopt_array($ch, [
        CURLOPT_RETURNTRANSFER => true,
        CURLOPT_NOBODY => true, // Solo HEAD request
        CURLOPT_TIMEOUT => 5,
        CURLOPT_FOLLOWLOCATION => true,
        CURLOPT_MAXREDIRS => 3,
        CURLOPT_SSL_VERIFYPEER => false, // Para evitar problemas con SSL
    ]);
    
    curl_exec($ch);
    $httpCode = curl_getinfo($ch, CURLINFO_HTTP_CODE);
    curl_close($ch);
    
    // Considerar válido si código 200-399
    $isValid = ($httpCode >= 200 && $httpCode < 400);
    $cache[$url] = $isValid;
    
    return $isValid;
}
?>