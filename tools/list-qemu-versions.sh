#!/usr/bin/env bash
set -euo pipefail

QEMU_REPO="${QEMU_REPO:-https://gitlab.com/qemu-project/qemu.git}"
MIN_MAJOR=0
MAX_MAJOR=

usage() {
    cat >&2 <<'EOF'
usage: tools/list-qemu-versions.sh [--min-major N] [--max-major N]

Lists stable upstream QEMU versions from qemu-project/qemu, selecting only the
latest patch release for each major.minor line. Output is ordered for backfill:
major descending, minor ascending.
EOF
}

while (( $# > 0 )); do
    case "$1" in
        --min-major)
            MIN_MAJOR="${2:?--min-major requires a value}"
            shift 2
            ;;
        --max-major)
            MAX_MAJOR="${2:?--max-major requires a value}"
            shift 2
            ;;
        -h | --help)
            usage
            exit 0
            ;;
        *)
            usage
            exit 1
            ;;
    esac
done

declare -A latest_patch

while IFS=$'\t' read -r _sha ref; do
    if [[ ! "${ref}" =~ ^refs/tags/v([0-9]+)\.([0-9]+)\.([0-9]+)(\^\{\})?$ ]]; then
        continue
    fi

    major="${BASH_REMATCH[1]}"
    minor="${BASH_REMATCH[2]}"
    patch="${BASH_REMATCH[3]}"

    if (( major < MIN_MAJOR )); then
        continue
    fi
    if [[ -n "${MAX_MAJOR}" ]] && (( major > MAX_MAJOR )); then
        continue
    fi

    key="${major}.${minor}"
    if [[ -z "${latest_patch[${key}]:-}" ]] || (( patch > latest_patch[${key}] )); then
        latest_patch["${key}"]="${patch}"
    fi
done < <(git ls-remote --tags "${QEMU_REPO}" 'refs/tags/v*')

for key in "${!latest_patch[@]}"; do
    major="${key%%.*}"
    minor="${key#*.}"
    patch="${latest_patch[${key}]}"

    printf "%05d %05d %05d %s.%s.%s\n" \
        "$((99999 - major))" "${minor}" "${patch}" \
        "${major}" "${minor}" "${patch}"
done | sort -n -k1,1 -k2,2 -k3,3 | cut -d' ' -f4
