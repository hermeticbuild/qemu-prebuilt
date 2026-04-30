#!/usr/bin/env bash
set -euo pipefail

usage() {
    echo "usage: tools/package-qemu-artifacts.sh <install-dir> <out-dir> <os> <exec-arch> <version> <user|img|system|system-data>" >&2
}

INSTALL_DIR="${1:-}"
OUT_DIR="${2:-}"
HOST_OS="${3:-}"
EXEC_ARCH="${4:-}"
ARTIFACT_VERSION="${5:-}"
ARTIFACT_FAMILY="${6:-}"

if [[ -z "${INSTALL_DIR}" || -z "${OUT_DIR}" || -z "${HOST_OS}" || -z "${EXEC_ARCH}" || -z "${ARTIFACT_VERSION}" || -z "${ARTIFACT_FAMILY}" ]]; then
    usage
    exit 1
fi

BIN_DIR="${INSTALL_DIR}/bin"
TAR="${TAR:-tar}"

mkdir -p "${OUT_DIR}"

make_archive() {
    local artifact_basename="${1:?artifact basename}"
    local staging_dir="${2:?staging dir}"

    local tar_gz="${OUT_DIR}/${artifact_basename}.tar.gz"
    local tar_zst="${OUT_DIR}/${artifact_basename}.tar.zst"

    "${TAR}" -czf "${tar_gz}" -C "${staging_dir}" .
    "${TAR}" --zstd -cf "${tar_zst}" -C "${staging_dir}" .

    gzip -t "${tar_gz}"
    zstd -q -t "${tar_zst}"
}

package_user() {
    if [[ ! -d "${BIN_DIR}" ]]; then
        echo "missing QEMU bin directory: ${BIN_DIR}" >&2
        exit 1
    fi

    local artifact_count=0
    for qemu_binary in "${BIN_DIR}"/qemu-*; do
        if [[ ! -f "${qemu_binary}" ]]; then
            continue
        fi

        local binary_name target_arch artifact_binary artifact_basename staging_dir
        binary_name="$(basename "${qemu_binary}")"
        case "${binary_name}" in
            qemu-img | qemu-system-*)
                continue
                ;;
        esac

        target_arch="${binary_name#qemu-}"
        artifact_binary="qemu-user-${HOST_OS}-${EXEC_ARCH}-${target_arch}"
        artifact_basename="${artifact_binary}-${ARTIFACT_VERSION}"
        staging_dir="$(mktemp -d)"

        cp "${qemu_binary}" "${staging_dir}/${artifact_binary}"
        chmod 0755 "${staging_dir}/${artifact_binary}"
        make_archive "${artifact_basename}" "${staging_dir}"
        cmp "${qemu_binary}" <("${TAR}" -xOf "${OUT_DIR}/${artifact_basename}.tar.gz" "./${artifact_binary}")
        cmp "${qemu_binary}" <("${TAR}" -xOf "${OUT_DIR}/${artifact_basename}.tar.zst" "./${artifact_binary}")
        rm -rf "${staging_dir}"
        artifact_count="$((artifact_count + 1))"
    done

    if (( artifact_count == 0 )); then
        echo "no user-mode qemu-* binaries found in ${BIN_DIR}" >&2
        exit 1
    fi
}

package_img() {
    local qemu_img="${BIN_DIR}/qemu-img"
    if [[ ! -f "${qemu_img}" ]]; then
        echo "missing qemu-img binary: ${qemu_img}" >&2
        exit 1
    fi

    local artifact_basename="qemu-img-${HOST_OS}-${EXEC_ARCH}-${ARTIFACT_VERSION}"
    local staging_dir
    staging_dir="$(mktemp -d)"
    mkdir -p "${staging_dir}/bin"
    cp "${qemu_img}" "${staging_dir}/bin/qemu-img"
    chmod 0755 "${staging_dir}/bin/qemu-img"
    make_archive "${artifact_basename}" "${staging_dir}"
    cmp "${qemu_img}" <("${TAR}" -xOf "${OUT_DIR}/${artifact_basename}.tar.gz" "./bin/qemu-img")
    cmp "${qemu_img}" <("${TAR}" -xOf "${OUT_DIR}/${artifact_basename}.tar.zst" "./bin/qemu-img")
    rm -rf "${staging_dir}"
}

package_system() {
    if [[ ! -d "${BIN_DIR}" ]]; then
        echo "missing QEMU bin directory: ${BIN_DIR}" >&2
        exit 1
    fi

    local artifact_count=0
    for qemu_binary in "${BIN_DIR}"/qemu-system-*; do
        if [[ ! -f "${qemu_binary}" ]]; then
            continue
        fi

        local binary_name system_target artifact_basename staging_dir
        binary_name="$(basename "${qemu_binary}")"
        system_target="${binary_name#qemu-system-}-softmmu"
        artifact_basename="qemu-system-bin-${HOST_OS}-${EXEC_ARCH}-${system_target}-${ARTIFACT_VERSION}"
        staging_dir="$(mktemp -d)"
        mkdir -p "${staging_dir}/bin"
        cp "${qemu_binary}" "${staging_dir}/bin/${binary_name}"
        chmod 0755 "${staging_dir}/bin/${binary_name}"
        make_archive "${artifact_basename}" "${staging_dir}"
        cmp "${qemu_binary}" <("${TAR}" -xOf "${OUT_DIR}/${artifact_basename}.tar.gz" "./bin/${binary_name}")
        cmp "${qemu_binary}" <("${TAR}" -xOf "${OUT_DIR}/${artifact_basename}.tar.zst" "./bin/${binary_name}")
        rm -rf "${staging_dir}"
        artifact_count="$((artifact_count + 1))"
    done

    if (( artifact_count == 0 )); then
        echo "no qemu-system-* binaries found in ${BIN_DIR}" >&2
        exit 1
    fi
}

package_system_data() {
    local qemu_data="${INSTALL_DIR}/share/qemu"
    if [[ ! -d "${qemu_data}" ]]; then
        echo "missing QEMU system data directory: ${qemu_data}" >&2
        exit 1
    fi

    local artifact_basename="qemu-system-data-${HOST_OS}-${EXEC_ARCH}-${ARTIFACT_VERSION}"
    local staging_dir
    staging_dir="$(mktemp -d)"
    mkdir -p "${staging_dir}/share"
    cp -a "${qemu_data}" "${staging_dir}/share/qemu"
    make_archive "${artifact_basename}" "${staging_dir}"
    "${TAR}" -tf "${OUT_DIR}/${artifact_basename}.tar.gz" > "${staging_dir}/tar-gz.list"
    "${TAR}" -tf "${OUT_DIR}/${artifact_basename}.tar.zst" > "${staging_dir}/tar-zst.list"
    grep -Eq '(^|/)share/qemu/' "${staging_dir}/tar-gz.list"
    grep -Eq '(^|/)share/qemu/' "${staging_dir}/tar-zst.list"
    rm -rf "${staging_dir}"
}

case "${ARTIFACT_FAMILY}" in
    user)
        package_user
        ;;
    img)
        package_img
        ;;
    system)
        package_system
        package_system_data
        ;;
    system-data)
        package_system_data
        ;;
    *)
        echo "unsupported artifact family: ${ARTIFACT_FAMILY}" >&2
        exit 1
        ;;
esac
