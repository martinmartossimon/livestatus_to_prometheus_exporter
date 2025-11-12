#!/usr/bin/env bash
set -euo pipefail

######################################################################
# Script: generate_metrics.sh
# Descripción: consulta Livestatus en varios hosts, genera métricas
#              Prometheus con procesamiento paralelo.
# Autor original: Martin Martos Simon
######################################################################

# === Configuración ===
ARCHIVO_SALIDA="${ARCHIVO_SALIDA:-/app/data/MetricReport.csv}"
ARCHIVO_SALIDA_LIMPIO="${ARCHIVO_SALIDA_LIMPIO:-/app/data/MetricReportLimpio.csv}"
OUTPUT_FILE="${OUTPUT_FILE:-/app/data/metrics.prom}"
SCRAPE_INTERVAL="${SCRAPE_INTERVAL:-420}"
LIVEHOSTS="${LIVESTATUS_HOSTS:-}"

# === Función auxiliar para esperar procesos ===
anywait() {
    for pid in "$@"; do
        while kill -0 "$pid" 2>/dev/null; do
            sleep 0.3
        done
    done
}

# === Función que consulta una colectora ===
query_livestatus() {
    local colectora="$1"
    local tmpfile="/tmp/${colectora}_query.txt"

    # Construir la query en un archivo temporal
    cat > "$tmpfile" <<'EOF'
GET services
Columns: host_name description perf_data
Filter: service_description ~~ ^Memory
Filter: service_description ~~ ^CPU
Filter: service_description ~~ ^Filesystem
Filter: service_description = PING
Or: 4
OutputFormat: csv

EOF

    echo "[$(date '+%H:%M:%S')] Consultando $colectora ..."
    # Enviar asegurando los saltos finales y esperar 1s antes de cerrar
    lines=$( (cat "$tmpfile"; echo; echo) | nc "$colectora" 6557 | tee -a "$ARCHIVO_SALIDA" | wc -l )
    echo "[$(date '+%H:%M:%S')] $colectora → $lines líneas recibidas"
    rm -f "$tmpfile"
}



# === Main ===
mkdir -p "$(dirname "$ARCHIVO_SALIDA")"
> "$ARCHIVO_SALIDA"

if [ -z "$LIVEHOSTS" ]; then
    echo "❌ Variable LIVESTATUS_HOSTS no definida en el entorno (.env)"
    exit 1
fi

# Ejecutar consultas en paralelo
PIDS=()
for colectora in $LIVEHOSTS; do
    query_livestatus "$colectora" &
    PIDS+=("$!")
done
anywait "${PIDS[@]}"

# Limpieza de resultados
date_epoch=$(date +%s)
awk -v fecha="$date_epoch" 'NF>0 {print fecha";"$0}' "$ARCHIVO_SALIDA" > "$ARCHIVO_SALIDA_LIMPIO"

# === Generar métricas Prometheus ===
awk -F';' '
BEGIN {
    print "# HELP system_resource_usage Resource usage percentage"
    print "# TYPE system_resource_usage gauge"
}
{
    hostname=$2
    service=$3
    details=$0

    if (service == "CPU utilization") {
    cpu_val = ""
    # Windows
    if (match(details, /util=([0-9.]+)/, w)) {
        cpu_val = w[1]
    }
    # Linux
    else if (match(details, /user=([0-9.]+)/, u) && match(details, /system=([0-9.]+)/, s)) {
        cpu_val = u[1] + s[1]
    }

    if (cpu_val != "")
        printf "system_resource_usage{hostname=\"%s\",resource=\"cpu\"} %.3f\n", hostname, cpu_val
}

    # --- CPU Load ---
    else if (service == "CPU load") {
        if (match(details, /load1=([0-9.]+)/, l1))
            printf "system_resource_usage{hostname=\"%s\",resource=\"load\",period=\"1\"} %s\n", hostname, l1[1]
        if (match(details, /load5=([0-9.]+)/, l5))
            printf "system_resource_usage{hostname=\"%s\",resource=\"load\",period=\"5\"} %s\n", hostname, l5[1]
        if (match(details, /load15=([0-9.]+)/, l15))
            printf "system_resource_usage{hostname=\"%s\",resource=\"load\",period=\"15\"} %s\n", hostname, l15[1]
    }

    # --- Filesystem ---
    else if (service ~ /^Filesystem/) {
        sub(/Filesystem /, "", service)
        sub(/:/, "", service)
        disk=service
        if (match(details, disk"=([0-9.]+)MB", used) && match(details, /fs_size=([0-9.]+)MB/, total)) {
            perc = (used[1]/total[1])*100
            printf "system_resource_usage{hostname=\"%s\",resource=\"filesystem\",disk=\"%s\"} %.3f\n", hostname, disk, perc
        }
    }

    # --- Memory (Windows y Linux) ---
    else if (service == "Memory and pagefile") {
        if (match(details, /memory=([0-9.]+)/, m1) && match(details, /mem_total=([0-9.]+)/, m2)) {
            perc = (m1[1]/m2[1])*100
            printf "system_resource_usage{hostname=\"%s\",resource=\"memory\"} %.3f\n", hostname, perc
        }
    }
    else if (service == "Memory") {
        if (match(details, /mem_used=([0-9.]+)/, m1) && match(details, /mem_total=([0-9.]+)/, m2)) {
            perc = (m1[1]/m2[1])*100
            printf "system_resource_usage{hostname=\"%s\",resource=\"memory\"} %.3f\n", hostname, perc
        }
    }

    # --- PING ---
    else if (service == "PING") {
        if (match(details, /pl=([0-9.]+)%/, pl))
            printf "system_resource_usage{hostname=\"%s\",resource=\"ping_loss\"} %s\n", hostname, pl[1]
        if (match(details, /rta=([0-9.]+)ms/, rta))
            printf "system_resource_usage{hostname=\"%s\",resource=\"ping_rta\"} %s\n", hostname, rta[1]
    }
}' "$ARCHIVO_SALIDA_LIMPIO" > "$OUTPUT_FILE"

echo "[$(date '+%H:%M:%S')] ✅ Métricas Prometheus generadas en $OUTPUT_FILE"
