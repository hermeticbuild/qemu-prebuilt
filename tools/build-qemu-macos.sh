#!/usr/bin/env bash
set -euo pipefail

usage() {
    echo "usage: tools/build-qemu-macos.sh <amd64|arm64> [qemu-version] [img|system|system-data] [target-list]" >&2
}

ARCH="${1:-}"
if [[ -z "${ARCH}" ]]; then
    usage
    exit 1
fi

if [[ "$(uname -s)" != "Darwin" ]]; then
    echo "macOS builds must run on Darwin" >&2
    exit 1
fi

QEMU_VERSION="${2:-${QEMU_VERSION:-}}"
ARTIFACT_FAMILY="${3:-${ARTIFACT_FAMILY:-img}}"
TARGET_LIST="${4:-${TARGET_LIST:-}}"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT_DIR="${OUT_DIR:-${ROOT_DIR}/out}"
BUILD_ROOT="${BUILD_ROOT:-${RUNNER_TEMP:-${ROOT_DIR}/.tmp}/qemu-macos-${ARCH}-${ARTIFACT_FAMILY}-$$}"
QEMU_VERSION="${QEMU_VERSION#v}"
QEMU_VERSION="${QEMU_VERSION:-11.0.0}"
ARTIFACT_SERIAL="${ARTIFACT_SERIAL:-}"
ARTIFACT_VERSION="${QEMU_VERSION}${ARTIFACT_SERIAL:+.${ARTIFACT_SERIAL}}"
QEMU_REPO="${QEMU_REPO:-https://gitlab.com/qemu-project/qemu.git}"
QEMU_REF="${QEMU_REF:-v${QEMU_VERSION}}"
MACOS_LINK_MODE="${MACOS_LINK_MODE:-dynamic}"

case "${ARCH}" in
    amd64)
        EXPECTED_UNAME="x86_64"
        DEFAULT_SYSTEM_TARGET="x86_64-softmmu"
        ;;
    arm64)
        EXPECTED_UNAME="arm64"
        DEFAULT_SYSTEM_TARGET="aarch64-softmmu"
        ;;
    *)
        echo "unsupported architecture: ${ARCH}" >&2
        exit 1
        ;;
esac

HOST_UNAME="$(uname -m)"
if [[ "${HOST_UNAME}" != "${EXPECTED_UNAME}" ]]; then
    echo "requested darwin-${ARCH}, but host architecture is ${HOST_UNAME}" >&2
    exit 1
fi

case "${ARTIFACT_FAMILY}" in
    img)
        ARTIFACT_PREFIXES=("qemu-img-darwin-${ARCH}-")
        ;;
    system)
        ARTIFACT_PREFIXES=("qemu-system-bin-darwin-${ARCH}-" "qemu-system-data-darwin-${ARCH}-")
        ;;
    system-data)
        ARTIFACT_PREFIXES=("qemu-system-data-darwin-${ARCH}-")
        ;;
    user)
        echo "macOS qemu-user artifacts are not supported" >&2
        exit 1
        ;;
    *)
        echo "unsupported artifact family: ${ARTIFACT_FAMILY}" >&2
        exit 1
        ;;
esac

install_deps() {
    if ! command -v brew >/dev/null 2>&1; then
        echo "Homebrew is required for macOS builds" >&2
        exit 1
    fi

    local deps dep missing
    deps=(glib gnu-tar libslirp ninja pkg-config pixman zstd)
    missing=()
    for dep in "${deps[@]}"; do
        if ! brew list --versions "${dep}" >/dev/null 2>&1; then
            missing+=("${dep}")
        fi
    done

    if (( ${#missing[@]} > 0 )); then
        brew install "${missing[@]}"
    fi
}

run() {
    echo "run: $*"
    "$@"
}

install_deps

export TAR="${TAR:-gtar}"
MAKE_JOBS="$(sysctl -n hw.ncpu)"
PREFIX="${BUILD_ROOT}/dst/qemu-darwin-${ARCH}-${ARTIFACT_VERSION}"
SRC_DIR="${BUILD_ROOT}/src/qemu-${ARTIFACT_VERSION}"
BUILD_DIR="${BUILD_ROOT}/out/qemu-${ARTIFACT_VERSION}"

mkdir -p "${OUT_DIR}" "${BUILD_ROOT}/src" "${BUILD_ROOT}/out" "${BUILD_ROOT}/artifact"
for artifact_prefix in "${ARTIFACT_PREFIXES[@]}"; do
    find "${OUT_DIR}" -maxdepth 1 -type f -name "${artifact_prefix}*" -delete
done

run git init "${SRC_DIR}"
cd "${SRC_DIR}"
run git remote add origin "${QEMU_REPO}"
run git fetch --depth=1 origin "${QEMU_REF}"
run git checkout --detach FETCH_HEAD

configure_args=(
    --prefix="${PREFIX}"
    --disable-debug-info
    --disable-werror
    --disable-guest-agent
    --disable-docs
    --disable-gtk
    --disable-sdl
    --disable-vnc
    --disable-opengl
    --disable-curses
    --disable-spice
    --disable-brlapi
    --disable-dbus-display
    --disable-curl
    --disable-cocoa
    --enable-hvf
    --enable-tcg
)

case "${MACOS_LINK_MODE}" in
    static)
        configure_args+=(--static)
        ;;
    dynamic)
        ;;
    *)
        echo "unsupported MACOS_LINK_MODE: ${MACOS_LINK_MODE}" >&2
        exit 1
        ;;
esac

case "${ARTIFACT_FAMILY}" in
    img)
        configure_args+=(
            --disable-system
            --disable-user
            --enable-tools
            --disable-slirp
        )
        ;;
    system | system-data)
        configure_args+=(
            --enable-system
            --disable-user
            --disable-tools
            --enable-slirp
        )
        TARGET_LIST="${TARGET_LIST:-${DEFAULT_SYSTEM_TARGET}}"
        ;;
esac

if [[ -n "${TARGET_LIST}" ]]; then
    configure_args+=("--target-list=${TARGET_LIST}")
fi

mkdir -p "${BUILD_DIR}"
cd "${BUILD_DIR}"
run "${SRC_DIR}/configure" "${configure_args[@]}"
run make "-j${MAKE_JOBS}"
run make "-j${MAKE_JOBS}" install
run "${ROOT_DIR}/tools/package-qemu-artifacts.sh" \
    "${PREFIX}" \
    "${BUILD_ROOT}/artifact" \
    darwin \
    "${ARCH}" \
    "${ARTIFACT_VERSION}" \
    "${ARTIFACT_FAMILY}"

cp "${BUILD_ROOT}/artifact"/qemu-* "${OUT_DIR}/"

artifacts=()
for artifact_prefix in "${ARTIFACT_PREFIXES[@]}"; do
    tar_gz_count="$(find "${OUT_DIR}" -maxdepth 1 -type f -name "${artifact_prefix}*.tar.gz" | wc -l | tr -d ' ')"
    tar_zst_count="$(find "${OUT_DIR}" -maxdepth 1 -type f -name "${artifact_prefix}*.tar.zst" | wc -l | tr -d ' ')"
    if [[ "${tar_gz_count}" == "0" ]] || [[ "${tar_gz_count}" != "${tar_zst_count}" ]]; then
        echo "expected matching non-empty ${artifact_prefix}*.tar.gz and .tar.zst archives; found ${tar_gz_count} gzip and ${tar_zst_count} zstd" >&2
        find "${OUT_DIR}" -maxdepth 1 -type f -print >&2
        exit 1
    fi

    unexpected_count="$(find "${OUT_DIR}" -maxdepth 1 -type f -name "${artifact_prefix}*" ! -name "*.tar.gz" ! -name "*.tar.zst" ! -name "*.sha256" | wc -l | tr -d ' ')"
    if [[ "${unexpected_count}" != "0" ]]; then
        echo "unexpected non-tar ${artifact_prefix} artifacts found" >&2
        find "${OUT_DIR}" -maxdepth 1 -type f -print >&2
        exit 1
    fi

    while IFS= read -r artifact; do
        artifacts+=("${artifact}")
    done < <(find "${OUT_DIR}" -maxdepth 1 -type f \( -name "${artifact_prefix}*.tar.gz" -o -name "${artifact_prefix}*.tar.zst" \) | sort)
done

for artifact in "${artifacts[@]}"; do
    artifact_name="$(basename "${artifact}")"
    case "${artifact_name}" in
        *.tar.gz)
            gzip -t "${artifact}"
            ;;
        *.tar.zst)
            zstd -q -t "${artifact}"
            ;;
        *)
            echo "unexpected artifact extension: ${artifact_name}" >&2
            exit 1
            ;;
    esac

    actual_member_count="$("${TAR}" -tf "${artifact}" | wc -l | tr -d ' ')"
    if [[ "${actual_member_count}" == "0" ]]; then
        echo "expected ${artifact_name} to contain at least one member" >&2
        exit 1
    fi

    (cd "${OUT_DIR}" && shasum -a 256 "${artifact_name}" > "${artifact_name}.sha256")
    echo "Artifact: ${artifact}"
    echo "Checksum: ${artifact}.sha256"
done

if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
    echo "attestation_name=qemu-${ARTIFACT_FAMILY}-darwin-${ARCH}.attestation.jsonl" >> "${GITHUB_OUTPUT}"
fi
