#!/usr/bin/env bash
set -euo pipefail

ARCH="${1:?usage: tools/build-qemu.sh <amd64|arm64> [qemu-version]}"
QEMU_VERSION="${2:-${QEMU_VERSION:-}}"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT_DIR="${OUT_DIR:-${ROOT_DIR}/out}"
IMAGE="qemu-static-${ARCH}:build"
CONTAINER="qemu-static-${ARCH}-copy-$$"

case "${ARCH}" in
    amd64)
        PLATFORM="linux/amd64"
        ;;
    arm64)
        PLATFORM="linux/arm64"
        ;;
    *)
        echo "unsupported architecture: ${ARCH}" >&2
        exit 1
        ;;
esac

cleanup() {
    docker container rm "${CONTAINER}" >/dev/null 2>&1 || true
}

trap cleanup EXIT

mkdir -p "${OUT_DIR}"
find "${OUT_DIR}" -maxdepth 1 -type f -name "qemu-user-linux-${ARCH}-*" -delete

docker build \
    --platform "${PLATFORM}" \
    --build-arg "ALPINE_VERSION=${ALPINE_VERSION:-3.23.4}" \
    --build-arg "QEMU_REPO=${QEMU_REPO:-https://gitlab.com/qemu-project/qemu.git}" \
    --build-arg "QEMU_REF=${QEMU_REF:-${QEMU_VERSION:+v${QEMU_VERSION#v}}}" \
    --build-arg "QEMU_VERSION=${QEMU_VERSION#v}" \
    --build-arg "ARTIFACT_SERIAL=${ARTIFACT_SERIAL:-}" \
    --tag "${IMAGE}" \
    "${ROOT_DIR}"

docker create --name "${CONTAINER}" "${IMAGE}" true >/dev/null
docker cp "${CONTAINER}:/work/artifact/." "${OUT_DIR}/"

tar_gz_count="$(find "${OUT_DIR}" -maxdepth 1 -type f -name "qemu-user-linux-${ARCH}-*.tar.gz" | wc -l | tr -d ' ')"
tar_zst_count="$(find "${OUT_DIR}" -maxdepth 1 -type f -name "qemu-user-linux-${ARCH}-*.tar.zst" | wc -l | tr -d ' ')"
if [[ "${tar_gz_count}" == "0" ]] || [[ "${tar_gz_count}" != "${tar_zst_count}" ]]; then
    echo "expected matching non-empty qemu-user-linux-${ARCH}-<target>.tar.gz and .tar.zst archives; found ${tar_gz_count} gzip and ${tar_zst_count} zstd" >&2
    find "${OUT_DIR}" -maxdepth 1 -type f -print >&2
    exit 1
fi

unexpected_count="$(find "${OUT_DIR}" -maxdepth 1 -type f -name "qemu-user-linux-${ARCH}-*" ! -name "*.tar.gz" ! -name "*.tar.zst" ! -name "*.sha256" | wc -l | tr -d ' ')"
if [[ "${unexpected_count}" != "0" ]]; then
    echo "unexpected non-tar qemu-user-linux-${ARCH} artifacts found" >&2
    find "${OUT_DIR}" -maxdepth 1 -type f -print >&2
    exit 1
fi

mapfile -t artifacts < <(find "${OUT_DIR}" -maxdepth 1 -type f \( -name "qemu-user-linux-${ARCH}-*.tar.gz" -o -name "qemu-user-linux-${ARCH}-*.tar.zst" \) | sort)

for artifact in "${artifacts[@]}"; do
    artifact_name="$(basename "${artifact}")"
    case "${artifact_name}" in
        *.tar.gz)
            expected_member="${artifact_name%.tar.gz}"
            gzip -t "${artifact}"
            ;;
        *.tar.zst)
            expected_member="${artifact_name%.tar.zst}"
            zstd -q -t "${artifact}"
            ;;
        *)
            echo "unexpected artifact extension: ${artifact_name}" >&2
            exit 1
            ;;
    esac

    actual_members="$(tar -tf "${artifact}")"
    if [[ "${actual_members}" != "${expected_member}" ]]; then
        echo "expected ${artifact_name} to contain exactly ${expected_member}, got:" >&2
        printf '%s\n' "${actual_members}" >&2
        exit 1
    fi

    if command -v sha256sum >/dev/null 2>&1; then
        (cd "${OUT_DIR}" && sha256sum "${artifact_name}" > "${artifact_name}.sha256")
    else
        (cd "${OUT_DIR}" && shasum -a 256 "${artifact_name}" > "${artifact_name}.sha256")
    fi

    echo "Artifact: ${artifact}"
    echo "Checksum: ${artifact}.sha256"
done

if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
    echo "attestation_name=qemu-user-linux-${ARCH}.attestation.jsonl" >> "${GITHUB_OUTPUT}"
fi
