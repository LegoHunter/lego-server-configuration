# syntax = docker/dockerfile:1
FROM ghcr.io/actions/actions-runner:2.336.0

ARG KUBECTL_VERSION=v1.32.8

USER root
RUN apt-get update && apt-get install -y \
    ca-certificates \
    curl \
    jq \
    && curl -LO "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/arm64/kubectl" \
    && chmod +x kubectl \
    && mv kubectl /usr/local/bin/ \
    && rm -rf /var/lib/apt/lists/*

USER runner

