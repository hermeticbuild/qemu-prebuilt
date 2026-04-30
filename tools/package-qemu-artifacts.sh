#!/usr/bin/env bash
set -euo pipefail

INSTALL_DIR="${1:?usage: tools/package-qemu-artifacts.sh <install-dir> <out-dir> <os> <exec-arch>}"
OUT_DIR="${2:?usage: tools/package-qemu-artifacts.sh <install-dir> <out-dir> <os> <exec-arch>}"
HOST_OS="${3:?usage: tools/package-qemu-artifacts.sh <install-dir> <out-dir> <os> <exec-arch>}"
EXEC_ARCH="${4:?usage: tools/package-qemu-artifacts.sh <install-dir> <out-dir> <os> <exec-arch>}"

BIN_DIR="${INSTALL_DIR}/bin"

if [[ ! -d "${BIN_DIR}" ]]; then
    echo "missing QEMU bin directory: ${BIN_DIR}" >&2
    exit 1
fi

mkdir -p "${OUT_DIR}"

artifact_count=0
for qemu_binary in "${BIN_DIR}"/qemu-*; do
    if [[ ! -f "${qemu_binary}" ]]; then
        continue
    fi

    target_arch="$(basename "${qemu_binary}")"
    target_arch="${target_arch#qemu-}"
    artifact_binary="qemu-user-${HOST_OS}-${EXEC_ARCH}-${target_arch}"
    staging_dir="$(mktemp -d)"

    cp "${qemu_binary}" "${staging_dir}/${artifact_binary}"
    chmod 0755 "${staging_dir}/${artifact_binary}"

    tar_gz="${OUT_DIR}/${artifact_binary}.tar.gz"
    tar_zst="${OUT_DIR}/${artifact_binary}.tar.zst"

    tar -czf "${tar_gz}" -C "${staging_dir}" "${artifact_binary}"
    tar --zstd -cf "${tar_zst}" -C "${staging_dir}" "${artifact_binary}"

    gzip -t "${tar_gz}"
    zstd -q -t "${tar_zst}"
    cmp "${qemu_binary}" <(tar -xOf "${tar_gz}" "${artifact_binary}")
    cmp "${qemu_binary}" <(tar -xOf "${tar_zst}" "${artifact_binary}")

    rm -rf "${staging_dir}"
    artifact_count="$((artifact_count + 1))"
done

if (( artifact_count == 0 )); then
    echo "no qemu-* binaries found in ${BIN_DIR}" >&2
    exit 1
fi
