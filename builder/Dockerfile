FROM golang:1.22.10

WORKDIR /app

COPY . .

RUN cd /app/subnet-creator-code && go build  -o ../subnet-creator .

RUN cd /app/genesis-generator-code && go build  -o ../genesis-generator .





