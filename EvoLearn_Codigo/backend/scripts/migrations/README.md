# Migraciones de Base de Datos

## Orden de ejecución

Las migraciones deben ejecutarse en orden cronológico:

1. **20251101_initial_schema.sql** - Esquema base inicial (users, directories, documents, topics, flashcards, ai_results)
2. **20251110_add_summary_jobs.sql** - Tabla para procesamiento asíncrono de resúmenes
3. **20251113_add_canceled_status.sql** - Añade estado 'canceled' a summary_jobs
4. **20251113_add_file_rel_path.sql** - Añade columna file_rel_path e índice compuesto

## Cómo ejecutar migraciones SQL

### Opción 1: MySQL CLI
```bash
mysql -u php_user -p estudiafacil < backend/scripts/migrations/20251101_initial_schema.sql
mysql -u php_user -p estudiafacil < backend/scripts/migrations/20251110_add_summary_jobs.sql
mysql -u php_user -p estudiafacil < backend/scripts/migrations/20251113_add_canceled_status.sql
mysql -u php_user -p estudiafacil < backend/scripts/migrations/20251113_add_file_rel_path.sql
```

### Opción 2: Desde PowerShell (Windows)
```powershell
Get-Content "backend\scripts\migrations\20251101_initial_schema.sql" | mysql -u php_user -p estudiafacil
Get-Content "backend\scripts\migrations\20251110_add_summary_jobs.sql" | mysql -u php_user -p estudiafacil
Get-Content "backend\scripts\migrations\20251113_add_canceled_status.sql" | mysql -u php_user -p estudiafacil
Get-Content "backend\scripts\migrations\20251113_add_file_rel_path.sql" | mysql -u php_user -p estudiafacil
```

### Opción 3: Ejecutar todas las migraciones (PowerShell)
```powershell
cd backend\scripts\migrations
Get-ChildItem -Filter "*.sql" | Sort-Object Name | ForEach-Object {
    Write-Host "Ejecutando migración: $($_.Name)" -ForegroundColor Cyan
    Get-Content $_.FullName | mysql -u php_user -p estudiafacil
}
```

## Migraciones PHP disponibles

Las migraciones PHP incluyen validaciones adicionales:

- **20251113_add_canceled_status.php** - Versión PHP con validaciones
- **20251113_add_file_rel_path.php** - Versión PHP con validaciones

Ejecutar con:
```bash
php backend/scripts/migrations/20251113_add_canceled_status.php
php backend/scripts/migrations/20251113_add_file_rel_path.php
```

## Verificar estado de la base de datos

```sql
-- Ver todas las tablas
SHOW TABLES;

-- Ver estructura de summary_jobs
DESCRIBE summary_jobs;

-- Ver índices de summary_jobs
SHOW INDEX FROM summary_jobs;

-- Verificar datos de demo
SELECT * FROM users WHERE email = 'demo@estudiafacil.com';
```

## Rollback

Si necesitas revertir cambios, ejecuta en orden inverso:

```sql
-- Revertir file_rel_path
DROP INDEX idx_summary_jobs_user_path_status ON summary_jobs;
ALTER TABLE summary_jobs DROP COLUMN file_rel_path;

-- Revertir canceled status
ALTER TABLE summary_jobs 
MODIFY COLUMN status ENUM('pending', 'processing', 'completed', 'failed') 
NOT NULL DEFAULT 'pending';

-- Revertir summary_jobs
DROP TABLE summary_jobs;

-- Revertir esquema inicial (⚠️ CUIDADO: elimina todo)
DROP DATABASE estudiafacil;
```

## Notas importantes

- **Siempre hacer backup** antes de ejecutar migraciones en producción
- Las migraciones SQL usan `IF NOT EXISTS` / `IF EXISTS` para ser idempotentes
- El usuario demo tiene contraseña: `123456`
- Charset: `utf8mb4_unicode_ci` para soporte completo de Unicode
