#!/usr/bin/env bash
#set -e

PORT="${PORT:-9100}"
INTERVAL="${SCRAPE_INTERVAL:-420}"

echo "🚀 Iniciando servidor HTTP que expone metricas a prometheus en puerto $PORT..."

# Lanzar el bucle del generador en segundo plano
while true; do
    echo "[$(date '+%F %T')] Ejecutando generate_metrics.sh..."
    if ./generate_metrics.sh; then
        echo "[$(date '+%F %T')] 🟢 Métricas actualizadas Correctamente 🟢."
    else
        echo "[$(date '+%F %T')] ⚠️ Error ejecutando generate_metrics.sh (continuando...)" >&2
    fi
    sleep "$SCRAPE_INTERVAL"
done &

# Servidor HTTP que entrega el archivo con tipo correcto
cat << 'EOF' > /app/serve_metrics.py
import http.server, socketserver, os

PORT = int(os.getenv("PORT", "9100"))
FILE = "/app/data/metrics.prom"

class MetricsHandler(http.server.SimpleHTTPRequestHandler):
    def do_GET(self):
        if self.path == "/metrics.prom":
            self.send_response(200)
            self.send_header("Content-type", "text/plain; version=0.0.4")
            self.end_headers()
            try:
                with open(FILE, "r") as f:
                    self.wfile.write(f.read().encode("utf-8"))
            except FileNotFoundError:
                self.wfile.write(b"# No metrics yet\n")
        else:
            self.send_response(404)
            self.end_headers()

if __name__ == "__main__":
    with socketserver.TCPServer(("", PORT), MetricsHandler) as httpd:
        print(f"🌍 Servidor HTTP corriendo en puerto {PORT}")
        httpd.serve_forever()
EOF

python3 /app/serve_metrics.py
