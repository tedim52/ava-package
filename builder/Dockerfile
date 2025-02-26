FROM golang:1.22.10

WORKDIR /app

COPY subnet-creator-code/go.mod subnet-creator-code/go.sum /app/subnet-creator-code/

RUN cd /app/subnet-creator-code && go mod download

COPY genesis-generator-code/go.mod genesis-generator-code/go.sum /app/genesis-generator-code/

RUN cd /app/genesis-generator-code && go mod download

COPY . .

RUN cd /app/subnet-creator-code && go build  -o ../subnet-creator .

RUN cd /app/genesis-generator-code && go build  -o ../genesis-generator .





