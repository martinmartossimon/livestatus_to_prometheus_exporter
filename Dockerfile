FROM alpine:3.20

RUN apk add --no-cache bash gawk netcat-openbsd python3 curl

WORKDIR /app

COPY generate_metrics.sh entrypoint.sh query_servicios_metricas_csv.lq ./
RUN chmod +x *.sh

RUN mkdir -p /app/data

# Can be overwriten on .env)
ENV PORT=9100
ENV SCRAPE_INTERVAL=420

EXPOSE ${PORT}

ENTRYPOINT ["./entrypoint.sh"]
