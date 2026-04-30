#!/usr/bin/env bash
set -euo pipefail

OUT_DIR="${1:-out}"
ARCH="${2:-amd64}"

TMP_DIR="$(mktemp -d)"
cleanup() {
    rm -rf "${TMP_DIR}"
}
trap cleanup EXIT

find_one() {
    local pattern="${1:?pattern}"
    local result_count
    result_count="$(find "${OUT_DIR}" -maxdepth 1 -type f -name "${pattern}" | wc -l | tr -d ' ')"
    if [[ "${result_count}" != "1" ]]; then
        echo "expected exactly one artifact matching ${pattern}; found ${result_count}" >&2
        find "${OUT_DIR}" -maxdepth 1 -type f -name "${pattern}" -print >&2
        exit 1
    fi

    find "${OUT_DIR}" -maxdepth 1 -type f -name "${pattern}" -print -quit
}

extract_artifact() {
    local artifact="${1:?artifact}"
    local dest="${2:?dest}"
    mkdir -p "${dest}"
    tar -xzf "${artifact}" -C "${dest}"
}

smoke_qemu_img() {
    local artifact img_dir image
    artifact="$(find_one "qemu-img-linux-${ARCH}-*.tar.gz")"
    img_dir="${TMP_DIR}/qemu-img"
    image="${TMP_DIR}/smoke.qcow2"

    extract_artifact "${artifact}" "${img_dir}"
    "${img_dir}/bin/qemu-img" --version
    "${img_dir}/bin/qemu-img" create -f qcow2 "${image}" 1M
    "${img_dir}/bin/qemu-img" info "${image}"
}

smoke_qemu_system() {
    local artifact system_dir netdev_help pidfile pid
    artifact="$(find_one "qemu-system-bin-linux-${ARCH}-x86_64-softmmu-*.tar.gz")"
    system_dir="${TMP_DIR}/qemu-system"
    pidfile="${TMP_DIR}/qemu-system.pid"

    extract_artifact "${artifact}" "${system_dir}"
    "${system_dir}/bin/qemu-system-x86_64" --version
    netdev_help="$("${system_dir}/bin/qemu-system-x86_64" -netdev help)"
    grep -q 'user' <<< "${netdev_help}"
    timeout 10 "${system_dir}/bin/qemu-system-x86_64" \
        -machine none \
        -nodefaults \
        -display none \
        -monitor none \
        -serial none \
        -S \
        -daemonize \
        -pidfile "${pidfile}"

    pid="$(cat "${pidfile}")"
    kill "${pid}"
    wait "${pid}" 2>/dev/null || true
}

compile_aarch64_smoke_program() {
    local source_file="${1:?source}"
    local output_file="${2:?output}"

    if command -v aarch64-linux-musl-gcc >/dev/null 2>&1; then
        aarch64-linux-musl-gcc -static "${source_file}" -o "${output_file}"
        return 0
    fi

    if command -v docker >/dev/null 2>&1; then
        docker run --rm \
            -v "${TMP_DIR}:/work" \
            -w /work \
            debian:bookworm-slim \
            sh -ceu 'apt-get update >/dev/null && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends gcc-aarch64-linux-gnu libc6-dev-arm64-cross >/dev/null && aarch64-linux-gnu-gcc -static smoke.c -o smoke-aarch64'
        return 0
    fi

    echo "missing aarch64-linux-musl-gcc and docker; cannot compile cross smoke program" >&2
    exit 1
}

smoke_qemu_user_cross() {
    local artifact user_dir source_file binary_file output
    artifact="$(find_one "qemu-user-linux-${ARCH}-aarch64-*.tar.gz")"
    user_dir="${TMP_DIR}/qemu-user"
    source_file="${TMP_DIR}/smoke.c"
    binary_file="${TMP_DIR}/smoke-aarch64"

    extract_artifact "${artifact}" "${user_dir}"
    cat > "${source_file}" <<'C'
#include <stdio.h>

int main(void) {
    puts("qemu-user-cross-smoke:ok");
    return 0;
}
C

    compile_aarch64_smoke_program "${source_file}" "${binary_file}"
    output="$("${user_dir}/qemu-user-linux-${ARCH}-aarch64" "${binary_file}")"
    if [[ "${output}" != "qemu-user-cross-smoke:ok" ]]; then
        echo "unexpected qemu-user smoke output: ${output}" >&2
        exit 1
    fi
}

smoke_system_data() {
    local artifact data_dir file_count
    artifact="$(find_one "qemu-system-data-linux-${ARCH}-*.tar.gz")"
    data_dir="${TMP_DIR}/qemu-system-data"

    extract_artifact "${artifact}" "${data_dir}"
    file_count="$(find "${data_dir}/share/qemu" -type f | wc -l | tr -d ' ')"
    if [[ "${file_count}" == "0" ]]; then
        echo "qemu-system-data artifact contains no files under share/qemu" >&2
        exit 1
    fi
}

smoke_qemu_img
smoke_qemu_system
smoke_qemu_user_cross
smoke_system_data
