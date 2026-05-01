ARG ALPINE_VERSION=3.23.4
FROM alpine:${ALPINE_VERSION}

ARG ARTIFACT_SERIAL=
ARG QEMU_REF=
ARG QEMU_REPO=https://gitlab.com/qemu-project/qemu.git
ARG QEMU_VERSION=
ARG TARGET_LIST=
ARG LIBSLIRP_REF=v4.9.1
ARG LIBSLIRP_REPO=https://gitlab.com/qemu-project/libslirp.git

ENV ARTIFACT_SERIAL="${ARTIFACT_SERIAL}"
ENV QEMU_REF="${QEMU_REF}"
ENV QEMU_REPO="${QEMU_REPO}"
ENV QEMU_VERSION="${QEMU_VERSION}"
ENV TARGET_LIST="${TARGET_LIST}"
ENV LIBSLIRP_REF="${LIBSLIRP_REF}"
ENV LIBSLIRP_REPO="${LIBSLIRP_REPO}"

RUN apk update
RUN apk upgrade

# required by qemu
RUN apk add\
 make\
 meson\
 samurai\
 perl\
 python3\
 gcc\
 libc-dev\
 pkgconf\
 linux-headers\
 glib-dev glib-static\
 zlib-dev zlib-static\
 ncurses-dev ncurses-static\
 pcre2-dev pcre2-static\
 pixman-dev pixman-static\
 libaio-dev\
 liburing-dev\
 bzip2-dev bzip2-static\
 util-linux-static\
 flex\
 bison

# required by build
RUN apk add bash gzip git tar zstd

WORKDIR /work
COPY build build
COPY tools/package-qemu-artifacts.sh tools/package-qemu-artifacts.sh
RUN /work/build
