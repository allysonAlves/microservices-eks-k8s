FROM golang:1.21-alpine AS builder
WORKDIR /app
COPY go.mod go.sum ./
RUN go mod download
COPY . .
RUN CGO_ENABLED=0 GOOS=linux go build -o auth-service .

FROM alpine:3.18
RUN apk add --no-cache ca-certificates wget
WORKDIR /app
COPY --from=builder /app/auth-service .
EXPOSE 8001
HEALTHCHECK --interval=10s --timeout=5s --retries=3 CMD wget -qO- http://localhost:8001/health || exit 1
CMD ["./auth-service"]
