# livestatus_to_prometheus_exporter
![Basic Diagram](images/Basic_Diagram.png)

A lightweight Prometheus exporter for Check_MK / Livestatus metrics.  
It collects CPU (load and utilization), Memory, Filesystems, and PING metrics and exposes them for Prometheus scraping.  
The exporter is extensible via the AWK section and the Livestatus query.

![Data From Livestatus](images/DetalleCSV.png)

---

## Get Started
```bash
# Clone the repository
git clone https://github.com/martinmartossimon/livestatus_to_prometheus_exporter
cd livestatus_to_prometheus_exporter

# Customize your environment
cp .env.example .env
# Edit .env as needed

# Launch the Docker container
docker run -d --rm --name livestatus-metrics \
    --env-file .env \
    -v $(pwd)/data:/app/data \
    -p 9501:9100 livestatus-metrics

# Validate metrics endpoint
curl http://hostname:9501/metrics.prom

```

---

## Build & Run with Custom Options
```bash
# Build Docker image
docker build -t livestatus-metrics .

# Run interactively for testing/debugging
docker run -it --rm --name livestatus-metrics \
    --env-file .env \
    -v $(pwd)/data:/app/data \
    -p 9501:9100 livestatus-metrics

# Run detached
docker run -d --rm --name livestatus-metrics \
    --env-file .env \
    -v $(pwd)/data:/app/data \
    -p 9501:9100 livestatus-metrics

# Follow logs in real-time
docker logs -f livestatus-metrics
```
---

## Prometheus Configuration Example
Edit as needed for your environment:
```yml
global:
  scrape_interval: 15s
  scrape_timeout: 10s


scrape_configs:
  - job_name: 'livestatus-metrics'
    scrape_interval: 7m # Customize as you need
    static_configs:
      - targets:
          - 'hostname:port'   # Customize as you need
    metrics_path: /metrics.prom

```

---

## Verification & Logs
```bash
# Verify metrics endpoint
curl http://hostname:9501/metrics.prom

# Follow logs
docker logs -f livestatus-metrics
```
![Logs Output Example](images/LogsOutput.png)

---

## Extending for Additional Services
Currently, this exporter collects metrics for CPU (load and utilization), Memory, Filesystems, and PING. To add new services:
1. Update the Livestatus Query
Edit the query embedded in generate_metrics.sh to include the new services you want. For example, add new Filter: lines for your service descriptions:
```bash
cat > "$tmpfile" <<'EOF'
GET services
Columns: host_name description perf_data
Filter: service_description ~~ ^Memory
Filter: service_description ~~ ^CPU
Filter: service_description ~~ ^Filesystem
Filter: service_description = PING
Filter: service_description ~~ ^NewService    # <-- Add your new service here
Or: 4
OutputFormat: csv

EOF
```

![Customize livestatus query](images/livestatusQuery.png)


2. Parse the New Service Output:
The exporter generates Prometheus metrics in the awk section of generate_metrics.sh. Add a new else if block to parse your new service output and convert it into Prometheus metrics:

![Parser Section](images/awk_parser.png)

Example to add:
```awk
else if (service == "NewService") {
    if (match(details, /value=([0-9.]+)/, m))
        printf "system_resource_usage{hostname=\"%s\",resource=\"new_service\"} %s\n", hostname, m[1]
}
```

3. Verify Your Metrics:
After updating the script, rebuild the container and run it. Check /metrics.prom to confirm your new service metrics are being generated:
```bash
curl http://hostname:9501/metrics.prom | grep new_service
```