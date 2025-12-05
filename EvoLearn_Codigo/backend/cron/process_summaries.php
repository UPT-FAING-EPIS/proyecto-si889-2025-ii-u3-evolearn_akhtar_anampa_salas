<?php
/**
 * Worker para procesar resúmenes en segundo plano.
 * 
 * Este script está diseñado para ser ejecutado por un cron job (p. ej., cada minuto).
 * Uso: php /ruta/a/tu/proyecto/backend/cron/process_summaries.php
 * 
 * Se recomienda configurar un bloqueo (lock) para evitar ejecuciones simultáneas.
 */
declare(strict_types=1);

// Aumentar el límite de tiempo de ejecución para este script, ya que es una tarea pesada.
// 5 minutos (300 segundos) debería ser suficiente para la mayoría de los PDFs.
set_time_limit(300);

require_once __DIR__ . '/../includes/bootstrap.php';
require_once __DIR__ . '/../includes/ai.php';
require_once __DIR__ . '/../includes/fs.php';
require_once __DIR__ . '/../vendor/autoload.php';

use Smalot\PdfParser\Parser as PdfParser;

$pdo = getPDO();

log_info('[CRON] Starting summary processing worker.');

try {
    // --- 1. Obtener trabajos pendientes ---
    // Limitar a 1 job por ciclo para reducir consumo de cuota de Gemini
    $stmt = $pdo->prepare("SELECT * FROM summary_jobs WHERE status = 'pending' ORDER BY created_at ASC LIMIT 1");
    $stmt->execute();
    $jobs = $stmt->fetchAll(PDO::FETCH_ASSOC);

    if (count($jobs) === 0) {
        log_info('[CRON] No pending jobs found.');
        exit;
    }

    log_info(sprintf('[CRON] Found %d pending jobs.', count($jobs)));

    // --- 2. Procesar cada trabajo ---
    foreach ($jobs as $job) {
        $jobId = $job['id'];
        $filePath = $job['file_path'];
        $keepFileForRetry = false;

        // --- a. Marcar como 'processing' y progreso inicial ---
        $updateStmt = $pdo->prepare("UPDATE summary_jobs SET status = 'processing', progress = 10, updated_at = NOW() WHERE id = ?");
        $updateStmt->execute([$jobId]);

        log_info(sprintf('[CRON] Processing job %d for file: %s', $jobId, basename($filePath)));

        try {
            // Si la tarea fue cancelada inmediatamente después de ser tomada
            $chk = $pdo->prepare("SELECT status FROM summary_jobs WHERE id = ?");
            $chk->execute([$jobId]);
            $cur = (string)($chk->fetchColumn() ?: '');
            if ($cur === 'canceled') {
                log_info(sprintf('[CRON] Job %d canceled before start. Skipping.', $jobId));
                throw new Exception('CANCELED');
            }

            // --- b. Extraer texto del PDF ---
            $updateStmt = $pdo->prepare("UPDATE summary_jobs SET progress = 25, updated_at = NOW() WHERE id = ?");
            $updateStmt->execute([$jobId]);

            // Construir el path absoluto del archivo
            // file_path puede ser:
            // 1. Ruta absoluta (comienza con / o tiene :)
            // 2. Ruta al processing_queue (FS mode)
            // 3. Ruta relativa al usuario (Cloud mode - usa file_rel_path)
            
            $absoluteFilePath = '';
            $userId = (int)$job['user_id'];
            $fileRelPath = (string)($job['file_rel_path'] ?? '');
            
            if (strpos($filePath, '/') === 0 || (strlen($filePath) > 1 && $filePath[1] === ':')) {
                // Ya es absoluto (Unix o Windows)
                $absoluteFilePath = $filePath;
            } elseif (strpos($filePath, 'uploads/processing_queue') !== false || strpos($filePath, 'processing_queue') === 0) {
                // Es una ruta de la cola de procesamiento (FS mode)
                $absoluteFilePath = __DIR__ . '/../' . $filePath;
            } elseif ($fileRelPath !== '' && $userId > 0) {
                // Cloud mode: usar la ruta relativa del usuario
                $absoluteFilePath = absPathForUser($userId, $fileRelPath);
                log_info(sprintf('[CRON] Cloud mode: userId=%d, fileRelPath=%s, absolutePath=%s', $userId, $fileRelPath, $absoluteFilePath));
            } else {
                // Fallback: relativo a backend/
                $absoluteFilePath = __DIR__ . '/../' . $filePath;
            }
            
            // Normalizar el path
            $absoluteFilePath = str_replace('\\', '/', $absoluteFilePath);
            $absoluteFilePath = preg_replace('#/+#', '/', $absoluteFilePath);
            $absoluteFilePath = str_replace('/', DIRECTORY_SEPARATOR, $absoluteFilePath);

            if (!file_exists($absoluteFilePath)) {
                log_error(sprintf('[CRON] File not found: filePath=%s, absolutePath=%s', $filePath, $absoluteFilePath));
                throw new Exception('El archivo PDF no fue encontrado en la cola de procesamiento.');
            }
            $parser = new PdfParser();
            $pdf = $parser->parseFile($absoluteFilePath);
            $text = (string)$pdf->getText();

            $updateStmt = $pdo->prepare("UPDATE summary_jobs SET progress = 50, updated_at = NOW() WHERE id = ?");
            $updateStmt->execute([$jobId]);

            // Verificar cancelación tras extracción
            $chk = $pdo->prepare("SELECT status FROM summary_jobs WHERE id = ?");
            $chk->execute([$jobId]);
            $cur = (string)($chk->fetchColumn() ?: '');
            if ($cur === 'canceled') {
                log_info(sprintf('[CRON] Job %d canceled after parse. Aborting.', $jobId));
                throw new Exception('CANCELED');
            }

            if (trim($text) === '') {
                throw new Exception('El PDF no contiene texto extraíble.');
            }
            
            // Aplicar los mismos límites que en la versión síncrona
            $maxTextLength = 500000;
            if (mb_strlen($text, 'UTF-8') > $maxTextLength) {
                $text = mb_substr($text, 0, $maxTextLength, 'UTF-8');
            }

            // --- c. Generar resumen ---
            $updateStmt = $pdo->prepare("UPDATE summary_jobs SET progress = 75, updated_at = NOW() WHERE id = ?");
            $updateStmt->execute([$jobId]);

            // Revisión de cancelación antes de IA
            $chk = $pdo->prepare("SELECT status FROM summary_jobs WHERE id = ?");
            $chk->execute([$jobId]);
            $cur = (string)($chk->fetchColumn() ?: '');
            if ($cur === 'canceled') {
                log_info(sprintf('[CRON] Job %d canceled before AI. Aborting.', $jobId));
                throw new Exception('CANCELED');
            }

            // Normalizar modelo: evitar 1.5 en API v1 y preferir 2.5
            $jobAnalysisType = (string)$job['analysis_type'];
            $jobModel = (string)$job['model'];
            if ($jobModel === '' || preg_match('/^gemini-1\.5/', $jobModel)) {
                $jobModel = ($jobAnalysisType === 'summary_detailed') ? 'gemini-2.5-pro' : 'gemini-2.5-flash';
                try {
                    $updModel = $pdo->prepare("UPDATE summary_jobs SET model = ?, updated_at = NOW() WHERE id = ?");
                    $updModel->execute([$jobModel, $jobId]);
                } catch (Throwable $e) {
                    // Si no se puede actualizar el modelo en BD, continuar con el modelo normalizado en memoria
                }
            }

            $summary = gemini_summarize($text, $jobAnalysisType, $jobModel);

            if ($summary === '') {
                throw new Exception('El servicio de IA no pudo generar un resumen.');
            }

            // --- d. Marcar como 'completed' ---
            $updateStmt = $pdo->prepare("UPDATE summary_jobs SET status = 'completed', progress = 100, summary_text = ?, updated_at = NOW() WHERE id = ?");
            $updateStmt->execute([$summary, $jobId]);

            // --- d2. Guardar archivo TXT del resumen en el mismo directorio que el PDF (cloud mode) ---
            $fileRelPath = (string)$job['file_rel_path'];
            if ($fileRelPath !== '') {
                try {
                    // Obtener el user_id del job
                    $userId = (int)$job['user_id'];
                    
                    // Buscar el documento original por file_rel_path para obtener directory_id
                    $docLookup = $pdo->prepare('
                        SELECT d.id, d.directory_id, dir.cloud_managed
                        FROM documents d
                        LEFT JOIN directories dir ON d.directory_id = dir.id
                        WHERE d.user_id = ? AND d.file_rel_path = ? AND d.mime_type = ?
                        LIMIT 1
                    ');
                    $docLookup->execute([$userId, $fileRelPath, 'application/pdf']);
                    $pdfDoc = $docLookup->fetch(PDO::FETCH_ASSOC);
                    
                    // Obtener el directorio padre del PDF
                    $dirRel = normalizeRelativePath(dirname($fileRelPath));
                    $dirAbs = absPathForUser($userId, $dirRel);
                    
                    // Crear el nombre del archivo de resumen
                    $pdfBaseName = basename($fileRelPath, '.pdf');
                    $summaryFileName = 'Resumen_' . sanitizeName($pdfBaseName) . '.txt';
                    $summaryPath = $dirAbs . DIRECTORY_SEPARATOR . $summaryFileName;
                    
                    // Asegurar que el directorio existe
                    if (!is_dir($dirAbs)) {
                        mkdir($dirAbs, 0777, true);
                    }
                    
                    // Guardar el archivo TXT con el resumen
                    if (@file_put_contents($summaryPath, $summary) !== false) {
                        log_info(sprintf('[CRON] Summary file saved for job %d: %s', $jobId, $summaryPath));
                        
                        // Registrar el archivo TXT en la tabla documents (si está en cloud mode)
                        if ($pdfDoc && $pdfDoc['cloud_managed']) {
                            try {
                                $dirId = (int)$pdfDoc['directory_id'];
                                
                                // Construir el file_rel_path para el resumen
                                $summaryRelPath = $dirRel !== '' ? ($dirRel . '/' . $summaryFileName) : $summaryFileName;
                                
                                $insertSummary = $pdo->prepare('
                                    INSERT IGNORE INTO documents 
                                    (user_id, directory_id, original_filename, display_name, stored_filename, file_rel_path, mime_type, size_bytes, text_content, model_used)
                                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                                ');
                                $insertSummary->execute([
                                    $userId,
                                    $dirId,
                                    $summaryFileName,
                                    'Resumen: ' . $pdfBaseName,
                                    $summaryFileName,
                                    $summaryRelPath,
                                    'text/plain',
                                    strlen($summary),
                                    $summary,
                                    'system'
                                ]);
                                
                                log_info(sprintf('[CRON] Summary document entry created for job %d, file_rel_path=%s', $jobId, $summaryRelPath));
                            } catch (Throwable $docErr) {
                                // No fallar el job si no se puede crear la entrada de BD
                                log_error(sprintf('[CRON] Error creating document entry for summary job %d: %s', $jobId, $docErr->getMessage()));
                            }
                        }
                    } else {
                        log_error(sprintf('[CRON] Failed to save summary file for job %d: %s', $jobId, $summaryPath));
                    }
                } catch (Throwable $fileErr) {
                    // No fallar el job si no se puede guardar el archivo TXT
                    log_error(sprintf('[CRON] Error saving summary file for job %d: %s', $jobId, $fileErr->getMessage()));
                }
            }

            log_info(sprintf('[CRON] Job %d completed successfully.', $jobId));

        } catch (Throwable $e) {
            // --- e. Manejo de errores ---
            $msg = $e->getMessage();
            if ($msg === 'AI_RATE_LIMIT') {
                // Reencolar el trabajo debido a límite de cuota y no borrar el archivo
                log_error(sprintf('[CRON] Job %d deferred due to AI rate limit. Will retry soon.', $jobId));
                $updateStmt = $pdo->prepare("UPDATE summary_jobs SET status = 'pending', progress = 5, error_message = 'Rate limited; retrying soon', updated_at = NOW() WHERE id = ?");
                $updateStmt->execute([$jobId]);
                // No unlink del archivo para reintentar en el próximo ciclo
                $keepFileForRetry = true;
            } else {
                log_error(sprintf('[CRON] Job %d failed: %s', $jobId, $msg));
                $errorMsg = $msg;
                // No sobreescribir si fue cancelado durante el proceso
                $chk = $pdo->prepare("SELECT status FROM summary_jobs WHERE id = ?");
                $chk->execute([$jobId]);
                $cur = (string)($chk->fetchColumn() ?: '');
                if ($msg === 'CANCELED') {
                    log_info(sprintf('[CRON] Job %d was canceled; not marking failed.', $jobId));
                } elseif ($cur !== 'canceled') {
                    $updateStmt = $pdo->prepare("UPDATE summary_jobs SET status = 'failed', error_message = ?, updated_at = NOW() WHERE id = ?");
                    $updateStmt->execute([$errorMsg, $jobId]);
                } else {
                    log_info(sprintf('[CRON] Job %d marked canceled, skipping failure overwrite.', $jobId));
                }
            }
        } finally {
            // --- f. Limpiar archivo temporal ---
            if (!$keepFileForRetry && file_exists($filePath)) {
                unlink($filePath);
            }
            
            // Delay para no saturar la cuota de Gemini
            sleep(10);
        }
    }

} catch (Throwable $e) {
    log_error('[CRON] Worker script encountered a fatal error: ' . $e->getMessage());
}

log_info('[CRON] Summary processing worker finished.');
