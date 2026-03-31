# syntax=docker/dockerfile:1.22.0
FROM registry.suse.com/bci/golang:1.26 AS base

ARG TARGETARCH
ARG http_proxy
ARG https_proxy

ENV ARCH=${TARGETARCH}
ENV PROTOC_VER=24.3
ENV PROTOBUF_VER_PY=4.24.3
ENV PROTOC_GEN_GO_VER=v1.31.0
ENV PROTOC_GEN_GO_GRPC_VER=v1.3.0

RUN zypper -n addrepo --refresh https://download.opensuse.org/repositories/system:/snappy/SLE_15/system:snappy.repo && \
    zypper --gpg-auto-import-keys ref

# TODO: replace python311 with python3 if SLE upgrade system python version to python3.10+
RUN zypper -n install wget git unzip python311 python311-devel python311-pip && \
    rm -rf /var/cache/zypp/*

# needed for ${!var} substitution
RUN rm -f /bin/sh && ln -s /bin/bash /bin/sh

# protoc
ENV PROTOC_amd64=https://github.com/protocolbuffers/protobuf/releases/download/v${PROTOC_VER}/protoc-${PROTOC_VER}-linux-x86_64.zip \
    PROTOC_arm64=https://github.com/protocolbuffers/protobuf/releases/download/v${PROTOC_VER}/protoc-${PROTOC_VER}-linux-aarch_64.zip \
    PROTOC=PROTOC_${ARCH}

RUN cd /usr/src && \
    wget ${!PROTOC} -O protoc_${ARCH}.zip && \
    unzip protoc_${ARCH}.zip -d /usr/local/

# protoc-gen-go
RUN mkdir -p /go/src/github.com && \
    cd /go/src/github.com/ && \
    mkdir protocolbuffers/ && \
    cd protocolbuffers && \
    git clone https://github.com/protocolbuffers/protobuf-go.git && \
    cd protobuf-go && \
    git checkout ${PROTOC_GEN_GO_VER} && \
    cd cmd/protoc-gen-go && \
    go build && \
    cp protoc-gen-go /usr/local/bin

# protoc-gen-go-grpc
RUN cd /go/src/github.com/ && \
    mkdir -p grpc/ && \
    cd grpc && \
    git clone https://github.com/grpc/grpc-go.git && \
    cd grpc-go && \
    git checkout cmd/protoc-gen-go-grpc/${PROTOC_GEN_GO_GRPC_VER} && \
    cd cmd/protoc-gen-go-grpc && \
    go build && \
    cp protoc-gen-go-grpc /usr/local/bin

# use python 3.11, so we can install latest grpcio
RUN ln -sf /usr/bin/python3.11 /usr/bin/python3 & \
    ln -sf /usr/bin/pip3.11 /usr/bin/pip3

# python grpc-tools
RUN pip3 install grpcio==1.58.0 grpcio_tools==1.58.0 protobuf==${PROTOBUF_VER_PY}

WORKDIR /go/src/github.com/longhorn/types
COPY . .

FROM base AS generate
RUN ./scripts/generate_grpc

FROM base AS validate
RUN ./scripts/ci && touch /validate.done

FROM scratch AS generate-artifacts
COPY --from=generate /go/src/github.com/longhorn/types/pkg/ /pkg/
COPY --from=generate /go/src/github.com/longhorn/types/generated-py/ /generated-py/

FROM scratch AS ci-artifacts
COPY --from=validate /validate.done /validate.done
