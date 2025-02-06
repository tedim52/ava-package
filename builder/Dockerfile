# Build stage
FROM golang:1.22.10 AS builder

WORKDIR /app

COPY subnet-creator-code/go.mod subnet-creator-code/go.sum /app/subnet-creator-code/

RUN cd /app/subnet-creator-code && go mod download

COPY genesis-generator-code/go.mod genesis-generator-code/go.sum /app/genesis-generator-code/

RUN cd /app/genesis-generator-code && go mod download

COPY . .

RUN cd /app/subnet-creator-code && go build  -o ../subnet-creator .

RUN cd /app/genesis-generator-code && go build  -o ../genesis-generator .

# Runtime stage
FROM ubuntu:latest

WORKDIR /app

COPY --from=builder /app/subnet-creator .

COPY --from=builder /app/genesis-generator .







