#!/usr/bin/env bash
set -euo pipefail

usage() {
    echo "usage: tools/smoke-test-linux-artifacts.sh <amd64|arm64> <qemu-version> [artifact-serial] [out-dir]" >&2
}

ARCH="${1:-}"
QEMU_VERSION="${2:-}"
ARTIFACT_SERIAL="${3:-}"
OUT_DIR="${4:-out}"

if [[ -z "${ARCH}" || -z "${QEMU_VERSION}" ]]; then
    usage
    exit 1
fi

case "${ARCH}" in
    amd64)
        USER_TARGET="x86_64"
        SYSTEM_TARGET="x86_64-softmmu"
        SYSTEM_BINARY="qemu-system-x86_64"
        ;;
    arm64)
        USER_TARGET="aarch64"
        SYSTEM_TARGET="aarch64-softmmu"
        SYSTEM_BINARY="qemu-system-aarch64"
        ;;
    *)
        echo "unsupported architecture: ${ARCH}" >&2
        exit 1
        ;;
esac

ARTIFACT_VERSION="${QEMU_VERSION#v}${ARTIFACT_SERIAL:+.${ARTIFACT_SERIAL}}"
WORK_DIR="$(mktemp -d)"

cleanup() {
    rm -rf "${WORK_DIR}"
}

trap cleanup EXIT

extract_archive() {
    local archive="${1:?archive}"
    local destination="${2:?destination}"

    mkdir -p "${destination}"
    tar -xzf "${archive}" -C "${destination}"
}

run_smoke() {
    local binary="${1:?binary}"

    "${binary}" --version >/dev/null
}

user_archive="${OUT_DIR}/qemu-user-linux-${ARCH}-${USER_TARGET}-${ARTIFACT_VERSION}.tar.gz"
img_archive="${OUT_DIR}/qemu-img-linux-${ARCH}-${ARTIFACT_VERSION}.tar.gz"
system_archive="${OUT_DIR}/qemu-system-bin-linux-${ARCH}-${SYSTEM_TARGET}-${ARTIFACT_VERSION}.tar.gz"

for archive in "${user_archive}" "${img_archive}" "${system_archive}"; do
    if [[ ! -f "${archive}" ]]; then
        echo "missing smoke-test artifact: ${archive}" >&2
        exit 1
    fi
done

extract_archive "${user_archive}" "${WORK_DIR}/user"
extract_archive "${img_archive}" "${WORK_DIR}/img"
extract_archive "${system_archive}" "${WORK_DIR}/system"

run_smoke "${WORK_DIR}/user/qemu-user-linux-${ARCH}-${USER_TARGET}"
run_smoke "${WORK_DIR}/img/bin/qemu-img"
run_smoke "${WORK_DIR}/system/bin/${SYSTEM_BINARY}"
