#!/usr/bin/env bash
set -euo pipefail

TAG="${1:?usage: tools/create-release.sh <tag> <asset>...}"
shift

if (( $# == 0 )); then
    echo "at least one release asset is required" >&2
    exit 1
fi

TITLE="qemu-static ${TAG}"
NOTES="Static Linux user-mode QEMU builds for amd64 and arm64."
UPLOAD_BATCH_SIZE="${UPLOAD_BATCH_SIZE:-20}"
UPLOAD_MAX_ATTEMPTS="${UPLOAD_MAX_ATTEMPTS:-6}"
UPLOAD_RETRY_DELAY_SECONDS="${UPLOAD_RETRY_DELAY_SECONDS:-60}"
UPLOAD_CLOBBER="${UPLOAD_CLOBBER:-false}"

if gh release view "${TAG}" >/dev/null 2>&1; then
    :
else
    gh release create "${TAG}" --title "${TITLE}" --notes "${NOTES}"
fi

declare -A existing_assets=()
while IFS= read -r asset_name; do
    existing_assets["${asset_name}"]=1
done < <(gh release view "${TAG}" --json assets --jq '.assets[].name')

upload_batch() {
    local attempt=1
    local delay="${UPLOAD_RETRY_DELAY_SECONDS}"
    local upload_args=("$@")

    if [[ "${UPLOAD_CLOBBER}" == "true" ]]; then
        upload_args+=(--clobber)
    fi

    while true; do
        if gh release upload "${TAG}" "${upload_args[@]}"; then
            return 0
        fi

        if (( attempt == UPLOAD_MAX_ATTEMPTS )); then
            echo "release upload failed after ${attempt} attempts" >&2
            return 1
        fi

        echo "release upload failed; retrying in ${delay}s (attempt ${attempt}/${UPLOAD_MAX_ATTEMPTS})" >&2
        sleep "${delay}"
        attempt=$((attempt + 1))
        delay=$((delay + UPLOAD_RETRY_DELAY_SECONDS))
    done
}

batch=()
for asset in "$@"; do
    asset_name="${asset##*/}"
    if [[ "${UPLOAD_CLOBBER}" != "true" && -n "${existing_assets[${asset_name}]:-}" ]]; then
        echo "skipping existing release asset: ${asset_name}" >&2
        continue
    fi

    batch+=("${asset}")

    if (( ${#batch[@]} == UPLOAD_BATCH_SIZE )); then
        upload_batch "${batch[@]}"
        batch=()
    fi
done

if (( ${#batch[@]} > 0 )); then
    upload_batch "${batch[@]}"
fi
