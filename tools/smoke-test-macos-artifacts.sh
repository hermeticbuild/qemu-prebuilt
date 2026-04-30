#!/usr/bin/env bash
set -euo pipefail

OUT_DIR="${1:-out}"
ARCH="${2:-}"

if [[ "$(uname -s)" != "Darwin" ]]; then
    echo "macOS smoke tests must run on Darwin" >&2
    exit 1
fi

if [[ -z "${ARCH}" ]]; then
    case "$(uname -m)" in
        x86_64)
            ARCH="amd64"
            ;;
        arm64)
            ARCH="arm64"
            ;;
        *)
            echo "unsupported host architecture: $(uname -m)" >&2
            exit 1
            ;;
    esac
fi

case "${ARCH}" in
    amd64)
        SYSTEM_TARGET="x86_64-softmmu"
        SYSTEM_BINARY="qemu-system-x86_64"
        MACHINE="q35"
        ;;
    arm64)
        SYSTEM_TARGET="aarch64-softmmu"
        SYSTEM_BINARY="qemu-system-aarch64"
        MACHINE="virt"
        ;;
    *)
        echo "unsupported architecture: ${ARCH}" >&2
        exit 1
        ;;
esac

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
    artifact="$(find_one "qemu-img-darwin-${ARCH}-*.tar.gz")"
    img_dir="${TMP_DIR}/qemu-img"
    image="${TMP_DIR}/smoke.qcow2"

    extract_artifact "${artifact}" "${img_dir}"
    otool -L "${img_dir}/bin/qemu-img"
    "${img_dir}/bin/qemu-img" --version
    "${img_dir}/bin/qemu-img" create -f qcow2 "${image}" 1M
    "${img_dir}/bin/qemu-img" info "${image}"
}

smoke_qemu_system() {
    local artifact data_artifact system_dir data_dir accel_help pidfile pid
    artifact="$(find_one "qemu-system-bin-darwin-${ARCH}-${SYSTEM_TARGET}-*.tar.gz")"
    data_artifact="$(find_one "qemu-system-data-darwin-${ARCH}-*.tar.gz")"
    system_dir="${TMP_DIR}/qemu-system"
    data_dir="${TMP_DIR}/qemu-system-data"
    pidfile="${TMP_DIR}/qemu-system.pid"

    extract_artifact "${artifact}" "${system_dir}"
    extract_artifact "${data_artifact}" "${data_dir}"
    otool -L "${system_dir}/bin/${SYSTEM_BINARY}"
    "${system_dir}/bin/${SYSTEM_BINARY}" --version
    accel_help="$("${system_dir}/bin/${SYSTEM_BINARY}" -accel help)"
    grep -q '^tcg$' <<< "${accel_help}"
    grep -q '^hvf$' <<< "${accel_help}"

    "${system_dir}/bin/${SYSTEM_BINARY}" \
        -L "${data_dir}/share/qemu" \
        -machine "${MACHINE},accel=tcg" \
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

smoke_qemu_img
smoke_qemu_system
