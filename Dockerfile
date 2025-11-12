FROM alpine:latest

RUN apk update && \
    apk add --no-cache bash curl jq

WORKDIR /app

COPY monitor.sh /app/monitor.sh

RUN chmod +x /app/monitor.sh

CMD ["/bin/bash", "/app/monitor.sh"]
