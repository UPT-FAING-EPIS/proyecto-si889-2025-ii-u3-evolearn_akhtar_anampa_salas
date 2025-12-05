# Script para instalar tarea programada en Windows Task Scheduler
# Ejecutar como administrador

$taskName = "EvoLearn_ProcessSummaries"
$backendPath = "C:\Users\USUARIO\Documents\walter\PATRONES\EvoLearn_Patrones\backend"
$workerScript = "$backendPath\cron\process_summaries.php"
$phpPath = "php"  # Asume que php está en PATH

# Eliminar tarea si existe
$existingTask = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
if ($existingTask) {
    Write-Host "Eliminando tarea existente: $taskName"
    Unregister-ScheduledTask -TaskName $taskName -Confirm:$false
}

# Crear trigger (cada 1 minuto)
$trigger = New-ScheduledTaskTrigger -RepetitionInterval (New-TimeSpan -Minutes 1) -At (Get-Date)

# Crear acción (ejecutar PHP)
$action = New-ScheduledTaskAction `
    -Execute $phpPath `
    -Argument $workerScript `
    -WorkingDirectory $backendPath

# Crear settings
$settings = New-ScheduledTaskSettingsSet `
    -MultipleInstances IgnoreNew `
    -StartWhenAvailable `
    -ExecutionTimeLimit (New-TimeSpan -Minutes 5)

# Registrar tarea
Register-ScheduledTask `
    -TaskName $taskName `
    -Trigger $trigger `
    -Action $action `
    -Settings $settings `
    -Description "Procesa automaticamente jobs de analisis cada minuto"

Write-Host "Tarea '$taskName' instalada exitosamente"
Write-Host "Se ejecutara automaticamente cada minuto"
