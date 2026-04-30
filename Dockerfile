ARG ALPINE_VERSION=3.23.4
FROM alpine:${ALPINE_VERSION}

ARG ARTIFACT_SERIAL=
ARG QEMU_REF=
ARG QEMU_REPO=https://gitlab.com/qemu-project/qemu.git
ARG QEMU_VERSION=

ENV ARTIFACT_SERIAL="${ARTIFACT_SERIAL}"
ENV QEMU_REF="${QEMU_REF}"
ENV QEMU_REPO="${QEMU_REPO}"
ENV QEMU_VERSION="${QEMU_VERSION}"

RUN apk update
RUN apk upgrade

# required by qemu
RUN apk add\
 make\
 samurai\
 perl\
 python3\
 gcc\
 libc-dev\
 pkgconf\
 linux-headers\
 glib-dev glib-static\
 zlib-dev zlib-static\
 pcre2-dev pcre2-static\
 flex\
 bison

# required by build
RUN apk add bash gzip git tar zstd

WORKDIR /work
COPY build build
COPY tools/package-qemu-artifacts.sh tools/package-qemu-artifacts.sh
RUN /work/build
