#!/usr/bin/env bash
# setup_cacert_debian.sh
# Descarga el bundle de CA de curl.se y configura php.ini (CLI, FPM, Apache) para usarlo.
# Uso: sudo bash setup_cacert_debian.sh
set -euo pipefail
CURL_CA_URL="https://curl.se/ca/cacert.pem"
LOCAL_CRT_DIR="/usr/local/share/ca-certificates"
LOCAL_CRT_PATH="$LOCAL_CRT_DIR/cacert.crt"
PHP_INIS=()

echo "1) Comprobando entorno..."
if ! command -v php >/dev/null 2>&1; then
  echo "php no está instalado o no está en PATH. Instala php antes de continuar." >&2
  exit 1
fi

echo "2) Descargando cacert.pem a $LOCAL_CRT_PATH"
mkdir -p "$LOCAL_CRT_DIR"
curl -fsSL "$CURL_CA_URL" -o "$LOCAL_CRT_PATH"
if [ $? -ne 0 ]; then
  echo "Fallo al descargar $CURL_CA_URL" >&2
  exit 1
fi

# update-ca-certificates espera archivos .crt en /usr/local/share/ca-certificates
echo "3) Actualizando store de certificados del sistema (update-ca-certificates)"
update-ca-certificates

# Buscar php.ini files en /etc/php/*/*/php.ini
while IFS= read -r ini; do
  PHP_INIS+=("$ini")
done < <(find /etc/php -type f -name php.ini 2>/dev/null || true)

if [ ${#PHP_INIS[@]} -eq 0 ]; then
  echo "No se encontraron php.ini en /etc/php. Mostrando php --ini:" 
  php --ini
  echo "Si usas otra ruta, edita el php.ini manualmente para definir curl.cainfo y openssl.cafile" 
  exit 0
fi

echo "4) Editando php.ini encontrados:"
for ini in "${PHP_INIS[@]}"; do
  echo " - $ini"
  cp -v "$ini" "$ini.bak"
  # Añadir o reemplazar directivas
  if grep -q "^\s*curl.cainfo\s*=\s*" "$ini"; then
    sed -ri "s|^\s*curl.cainfo\s*=.*|curl.cainfo = /etc/ssl/certs/ca-certificates.crt|" "$ini"
  else
    echo "curl.cainfo = /etc/ssl/certs/ca-certificates.crt" >> "$ini"
  fi

  if grep -q "^\s*openssl.cafile\s*=\s*" "$ini"; then
    sed -ri "s|^\s*openssl.cafile\s*=.*|openssl.cafile = /etc/ssl/certs/ca-certificates.crt|" "$ini"
  else
    echo "openssl.cafile = /etc/ssl/certs/ca-certificates.crt" >> "$ini"
  fi

done

# Reiniciar servicios si es necesario
echo "5) Reiniciando servicios PHP/WEB detectados (si existen)"
# Reiniciar php*-fpm services
for svc in $(systemctl list-units --type=service --no-legend | awk '{print $1}' | grep -E '^php[0-9\.\-]+-fpm\.service$' || true); do
  echo "Restarting $svc"
  systemctl restart "$svc" || echo "Advertencia: fallo al reiniciar $svc"
done

# Reiniciar apache2 / nginx si están instalados
if systemctl is-enabled --quiet apache2 2>/dev/null; then
  echo "Restarting apache2"
  systemctl restart apache2 || echo "Advertencia: fallo al reiniciar apache2"
fi

if systemctl is-enabled --quiet nginx 2>/dev/null; then
  echo "Restarting nginx"
  systemctl restart nginx || echo "Advertencia: fallo al reiniciar nginx"
fi

echo "Hecho. Verifica con: php --ini y php -r 'echo ini_get(\"curl.cainfo\");'"
exit 0
