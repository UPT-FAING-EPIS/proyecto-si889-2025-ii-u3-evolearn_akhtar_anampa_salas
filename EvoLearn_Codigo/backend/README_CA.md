tail -n 200 backend/logs/ai.log
Configurar certificados CA para PHP (permanente)

Resumen
-------
Este documento explica cómo configurar un bundle de CA (cacert.pem) de forma permanente para que las llamadas salientes HTTPS desde PHP (cURL/OpenSSL) verifiquen correctamente los certificados remotos.

Escenario objetivo
------------------
Vas a desplegar el backend en una VM Debian. El worker `backend/cron/process_summaries.php` hace llamadas HTTPS a una API de IA (Gemini) y puede fallar con:

  SSL certificate problem: unable to get local issuer certificate

Este README ahora incluye: instrucciones permanentes para Debian, pasos de despliegue completos, y una sección rápida para ejecutar todo localmente durante el desarrollo.

Solución recomendada (Debian, permanente)
-----------------------------------------
1) Ejecuta el script incluido (requiere privilegios root):

```bash
cd backend/scripts
sudo bash setup_cacert_debian.sh
```

Qué hace el script:
- Descarga el bundle oficial desde https://curl.se/ca/cacert.pem y lo copia como `/usr/local/share/ca-certificates/cacert.crt`.
- Ejecuta `update-ca-certificates` para añadirlo al store del sistema y regenerar `/etc/ssl/certs/ca-certificates.crt`.
- Busca los `php.ini` en `/etc/php/*/*/php.ini` (CLI, FPM, Apache) y hace backup (`php.ini.bak`) antes de modificar.
- Inserta/actualiza las directivas `curl.cainfo` y `openssl.cafile` a `/etc/ssl/certs/ca-certificates.crt`.
- Reinicia servicios detectados (php*-fpm, apache2, nginx) si existen.

2) Verificación rápida

```bash
php --ini
php -r "echo ini_get('curl.cainfo') . PHP_EOL;"
php -r "echo ini_get('openssl.cafile') . PHP_EOL;"
# Ejecuta el worker manualmente y revisa el log
php /ruta/a/backend/cron/process_summaries.php
tail -n 200 backend/logs/ai.log
```

Despliegue completo en Debian (paso a paso)
-----------------------------------------
Estas instrucciones asumen una VM Debian/Ubuntu limpia.

1) Actualizar y instalar dependencias básicas

```bash
sudo apt update && sudo apt upgrade -y
# PHP (ajusta la versión si usas 8.1/8.2/8.3)
sudo apt install -y php php-cli php-fpm php-mbstring php-xml php-curl php-zip php-mysql unzip curl git
# Servidor de BD
sudo apt install -y mariadb-server
# Servidor web (elige uno):
sudo apt install -y nginx
```

2) Crear base de datos y usuario

```bash
sudo mysql < ../database.sql
# o, si prefieres manual:
sudo mysql -e "CREATE DATABASE estudiafacil; CREATE USER 'php_user'@'localhost' IDENTIFIED BY 'password'; GRANT ALL ON estudiafacil.* TO 'php_user'@'localhost'; FLUSH PRIVILEGES;"
```

3) Clonar/copy del repo y permisos

```bash
cd /var/www
sudo git clone <tu-repo-url> evolearn
cd evolearn/backend
sudo chown -R www-data:www-data uploads logs
sudo chmod -R 770 uploads logs
```

4) Composer (si el proyecto usa composer)

```bash
sudo apt install -y composer
composer install --no-dev -o
```

5) Configurar PHP y certificados CA

- Ejecuta el `setup_cacert_debian.sh` descrito arriba para asegurar que PHP usa `/etc/ssl/certs/ca-certificates.crt`.
- Revisa `php.ini` si necesitas ajustes extra (timezones, upload_max_filesize, post_max_size). Para el backend este proyecto necesita subir PDFs grandes, por ejemplo:

```ini
upload_max_filesize = 50M
post_max_size = 50M
max_execution_time = 300
```

Aplica esos cambios en `/etc/php/*/cli/php.ini` y `/etc/php/*/fpm/php.ini` según corresponda.

6) Configurar Nginx (ejemplo mínimo)

```nginx
server {
    listen 80;
    server_name tu_dominio_o_ip;
    root /var/www/evolearn/backend;
    index index.php index.html;

    location / {
        try_files $uri $uri/ /index.php?$query_string;
    }

    location ~ \.php$ {
        include snippets/fastcgi-php.conf;
        fastcgi_pass unix:/run/php/php8.3-fpm.sock; # ajusta según tu versión
    }

    access_log /var/log/nginx/evolearn.access.log;
    error_log /var/log/nginx/evolearn.error.log;
}
```

Luego:
```bash
sudo ln -s /etc/nginx/sites-available/evolearn /etc/nginx/sites-enabled/
sudo nginx -t && sudo systemctl reload nginx
```

7) Crear un servicio systemd para el worker (opcional, recomendado)

`/etc/systemd/system/evolearn-worker.service`:

```ini
[Unit]
Description=EvoLearn summary worker
After=network.target

[Service]
User=www-data
Group=www-data
WorkingDirectory=/var/www/evolearn/backend/cron
ExecStart=/usr/bin/php -d curl.cainfo=/etc/ssl/certs/ca-certificates.crt -d openssl.cafile=/etc/ssl/certs/ca-certificates.crt process_summaries.php
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
```

```bash
sudo systemctl daemon-reload
sudo systemctl enable --now evolearn-worker.service
```

8) Firewall (ufw) — opcional

```bash
sudo apt install -y ufw
sudo ufw allow OpenSSH
sudo ufw allow 80/tcp
sudo ufw enable
```

Ejecución y pruebas locales (rápido, para desarrollo)
---------------------------------------------------
Si vas a ejecutar localmente en Windows o en la VM sin Nginx/Apache, puedes usar el servidor embebido de PHP para pruebas rápidas.

1) Ejecutar el servidor PHP en puerto 8003 (con límites de subida mayores):

```powershell
# Windows PowerShell (local)
php -d upload_max_filesize=50M -d post_max_size=50M -S 127.0.0.1:8003 -t "C:\ruta\a\repo\backend"
```

```bash
# Linux (en la VM)
php -d upload_max_filesize=50M -d post_max_size=50M -S 0.0.0.0:8003 -t /ruta/al/repo/backend
```

2) Ejecutar el worker manualmente (no permanente):

```bash
php -d curl.cainfo="/ruta/a/cacert.pem" -d openssl.cafile="/ruta/a/cacert.pem" backend/cron/process_summaries.php
```

Si ya ejecutaste `setup_cacert_debian.sh`, puedes ejecutar simplemente:

```bash
php backend/cron/process_summaries.php
```

3) Probar endpoints (ejemplo login + upload con curl)

```bash
# Login
curl -X POST -H "Content-Type: application/json" -d '{"email":"tu_email","password":"tu_pass"}' http://127.0.0.1:8003/api/login.php
# Upload (con token obtenido)
curl -v -X POST -H "Authorization: Bearer <TOKEN>" -F "pdf=@/ruta/al/archivo.pdf" -F "analysis_type=summary_fast" "http://127.0.0.1:8003/api/generate_summary.php"
```

Reprocesado de jobs pendientes
------------------------------
Si algunos jobs fallaron por TLS antes de aplicar la solución permanente, una vez aplicada puedes re-ejecutar el worker para que recoja y reprocesse la cola:

```bash
sudo systemctl restart evolearn-worker.service # si creaste el servicio
# o ejecutar manualmente
php /var/www/evolearn/backend/cron/process_summaries.php
```

Verifica `backend/logs/ai.log` para ver el resultado.

Notas sobre Android y pruebas de cliente
--------------------------------------
- Para el emulador Android (emulador de Google/Android Studio) usa `http://10.0.2.2:8003` como base URL apuntando al host donde corre el backend.
- Para dispositivos físicos en la misma LAN, usa la IP de la VM en la LAN, por ejemplo `http://192.168.1.123:8003` y asegúrate que el firewall permite el puerto.
- El frontend soporta `--dart-define=BASE_URL` para sobreescribir fácilmente la URL base en pruebas.

Solución de problemas rápida
---------------------------
- Si ves `SSL certificate problem` tras aplicar el script, verifica que `/etc/ssl/certs/ca-certificates.crt` existe y que `php -r "echo ini_get('curl.cainfo');"` devuelve esa ruta.
- Si `$_FILES` aparece vacío al subir, revisa `upload_max_filesize` y `post_max_size` en el `php.ini` que usa el servidor (CLI vs FPM) y reinicia el servicio.
- Logs: `backend/logs/ai.log` contiene trazas del worker; `logs/` y `uploads/processing_queue` te ayudarán a diagnosticar.

Nota sobre `GEMINI_SKIP_SSL_VERIFY` (desarrollo)
----------------------------------------------

Este proyecto dispone de una variable de entorno `GEMINI_SKIP_SSL_VERIFY` que, cuando está activa (`1`, `true`, `yes`), desactiva la verificación SSL en las llamadas salientes hacia las APIs de IA (Gemini, Perplexity) desde `backend/includes/ai.php`.

- ¿Por qué existe? En entornos de desarrollo/Windows sin un bundle CA configurado, PHP/cURL puede fallar con `unable to get local issuer certificate`. Para evitar que los jobs queden bloqueados, el código puede desactivar la verificación temporalmente.
- ¿Provoca lentitud en el análisis? No directamente: deshabilitar la verificación SSL evita el error de certificado y por tanto suele hacer la llamada más rápida en esos casos. Sin embargo, si no está deshabilitada y hay problemas de certificado, el worker puede experimentar reintentos y esperas que sí incrementan mucho la duración total del análisis. Puntos clave desde el código:
    - `CURLOPT_TIMEOUT` está a `120` segundos por intento; `CURLOPT_CONNECTTIMEOUT` a `20` segundos.
    - La función de Gemini usa `maxAttempts = 4` y un `baseDelaySec = 5` con backoff exponencial (5s, 10s, 20s, 40s) y jitter. Si la API responde con 429/503/408 o hay fallos de red, esos retrasos se suman y pueden hacer que una llamada tarde decenas de segundos o varios minutos.
    - Además, el proceso realiza una llamada por cada "chunk" de texto. Si el documento se divide en varios chunks y cada uno necesita reintentos, el tiempo total aumenta proporcionalmente.

Recomendaciones prácticas
-------------------------

- Desarrollo rápido (local): si estás probando en Windows y quieres evitar bloqueos, puedes establecer `GEMINI_SKIP_SSL_VERIFY=1` en tu sesión de PowerShell:

```powershell
$env:GEMINI_SKIP_SSL_VERIFY = '1'
```

- Entorno de pruebas controlado: mejor alternativa es usar un bundle CA válido y apuntar `CACERT_PATH` a `cacert.pem` (o instalarlo en el store del sistema). El repo incluye `scripts/setup_cacert_debian.sh` para Debian.

- Producción (recomendado): NO desactivar la verificación. Asegura un bundle CA instalado o que PHP use el store del sistema y establece `GEMINI_SKIP_SSL_VERIFY=0` o elimina la variable.

- Para reducir latencias en desarrollo si quieres intentar mantener verificación activa: reduce `CURLOPT_TIMEOUT`, reduce `maxAttempts` o baja `baseDelaySec` en `call_gemini` (archivo `backend/includes/ai.php`) mientras debugueas.

Si quieres, aplico alguno de estos cambios ahora (por ejemplo: revertir el comportamiento por defecto para que la verificación esté activada, añadir instrucciones en `backend/.user.ini`, o bajar `maxAttempts`/timeouts para desarrollo). Indica qué prefieres.

Ajustes del tamaño de subida (upload_max_filesize) — `.user.ini` y edición de `php.ini`
--------------------------------------------------------------------------
Para desarrollo rápido normalmente usamos `-d upload_max_filesize=50M -d post_max_size=50M` al arrancar PHP. Si prefieres una solución por proyecto (útil para PHP-FPM) o una solución permanente, aquí tienes las opciones.

1) Opción por proyecto: crear un archivo `.user.ini` dentro de la carpeta `backend/` (válido para PHP-FPM/CGI):

Contenido recomendado para `backend/.user.ini`:

```
upload_max_filesize = 50M
post_max_size = 50M
```

Notas:
- PHP-FPM lee `.user.ini` por directorio; el refresco depende de `user_ini.cache_ttl` (valor por defecto en segundos). Puedes cambiar ese valor en `php.ini` si necesitas que los cambios se detecten más rápido.

2) Opción permanente: editar `php.ini` (Linux / Debian ejemplo)

Encuentra los `php.ini` que importan con:

```bash
php --ini
find /etc/php -type f -name php.ini
```

Modificar (ejemplo con sed — ajusta la ruta y la versión PHP):

```bash
sudo cp /etc/php/8.3/fpm/php.ini /etc/php/8.3/fpm/php.ini.bak
sudo sed -ri "s/^\s*upload_max_filesize\s*=.*/upload_max_filesize = 50M/" /etc/php/8.3/fpm/php.ini || echo "upload_max_filesize = 50M" | sudo tee -a /etc/php/8.3/fpm/php.ini
sudo sed -ri "s/^\s*post_max_size\s*=.*/post_max_size = 50M/" /etc/php/8.3/fpm/php.ini || echo "post_max_size = 50M" | sudo tee -a /etc/php/8.3/fpm/php.ini
sudo systemctl restart php8.3-fpm
```

3) Opción pool PHP-FPM (por servicio/pool)

En `/etc/php/8.3/fpm/pool.d/www.conf` puedes forzar valores por pool:

```
php_admin_value[upload_max_filesize] = 50M
php_admin_value[post_max_size] = 50M
```

Luego reinicia `php8.3-fpm`.

4) Windows (edición de `php.ini`)

Localiza el `php.ini` (por ejemplo en `C:\php\php.ini` o `C:\xampp\php\php.ini`) y modifica o añade las líneas:

```ini
upload_max_filesize = 50M
post_max_size = 50M
```

Reinicia el servicio web o la instancia de PHP si procede (o reinicia la terminal si usas el servidor embebido).

Comprobación rápida de valores activos

```bash
php -r "echo ini_get('upload_max_filesize') . PHP_EOL;"
php -r "echo ini_get('post_max_size') . PHP_EOL;"
```

Si quieres, puedo añadir ahora un `backend/.user.ini` al repo con los valores recomendados para que lo tengas listo para desplegar.

Si quieres, puedo añadir también:
- Un script que reprocese sólo los jobs con estado `failed` en la base de datos.
- Instrucciones Dockerfile + docker-compose para producción.

Fin.