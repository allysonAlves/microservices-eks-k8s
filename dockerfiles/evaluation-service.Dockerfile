FROM golang:1.21-alpine AS builder
WORKDIR /app
COPY go.mod go.sum ./
RUN go mod download
COPY . .
RUN go mod tidy && CGO_ENABLED=0 GOOS=linux go build -o evaluation-service .

FROM alpine:3.23.4
RUN apk add --no-cache ca-certificates wget
RUN addgroup -S appgroup && adduser -S -G appgroup -H -s /sbin/nologin appuser
WORKDIR /app
COPY --from=builder --chown=appuser:appgroup /app/evaluation-service .
USER appuser
EXPOSE 8004
HEALTHCHECK --interval=10s --timeout=5s --retries=3 CMD wget -qO- http://localhost:8004/health || exit 1
CMD ["./evaluation-service"]
