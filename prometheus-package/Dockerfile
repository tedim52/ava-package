FROM ubuntu:latest

RUN apt-get update && apt-get install -y wget && rm -rf /var/lib/apt/lists/*

RUN wget https://github.com/prometheus/node_exporter/releases/download/v1.2.2/node_exporter-1.2.2.linux-amd64.tar.gz

RUN tar xvfz node_exporter-*.*-amd64.tar.gz

WORKDIR /node_exporter-1.2.2.linux-amd64 
