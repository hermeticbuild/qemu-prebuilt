# qemu-static

This repository builds static Linux user-mode QEMU archives for GitHub releases.
It is based on <https://codeberg.org/ziglang/qemu-static> at commit
`96593b61f32eebf2e44d88fbfffdc83f5b622225`.

The purpose of the upstream project is to build a highly compatible linux QEMU
binary package for Zig CI testing.

Zig requires a very recent QEMU version, sometimes unreleased commit-revs, and
sometimes with custom patches. For this reason, distro-based QEMU packages are
unsuitable.

The overall strategy is to use Alpine Linux to host a QEMU build and link
statically to all possible libraries.

It is a non-goal to build QEMU with all features enabled.
It is a non-goal to build QEMU with system emulation enabled.
It is a non-goal to build older versions of QEMU.

## Release workflow

Pushing any tag starts `.github/workflows/release.yml`. The workflow builds:

- `qemu-user-linux-amd64-<target>.tar.gz` and `.tar.zst` archives on `ubuntu-24.04`
- `qemu-user-linux-arm64-<target>.tar.gz` and `.tar.zst` archives on `ubuntu-24.04-arm`

Each per-target archive contains one prefixed executable named
`qemu-user-<os>-<exec-arch>-<target-arch>`. Each build uploads every per-target
archive and `.sha256` file as workflow artifacts, attests them with GitHub
artifact attestations, and publishes the attestation bundle as a release asset.
The final job creates or updates the GitHub release for the tag and uploads both
architecture artifact sets, checksums, and attestation bundles.

The workflow can also be run manually with a `tag_name` input to retry release
publication for an existing tag.

Manual release runs can also build a specific upstream QEMU version without
editing the repository. Set `qemu_version` to a stable upstream version such as
`10.2.2`; the workflow builds `v10.2.2` from
`https://gitlab.com/qemu-project/qemu.git` unless `qemu_ref` or `qemu_repo` are
overridden.

## Backfill workflow

`.github/workflows/backfill.yml` discovers stable upstream QEMU release tags
from `qemu-project/qemu`, ignores release candidates, and selects only the
latest patch release for each major.minor line. Results are ordered by major
descending and minor ascending, so a `max_major` of `10` starts with:

```text
10.0.9
10.1.5
10.2.2
```

The backfill workflow skips versions that already have a release in this
repository unless `force_rebuild` is set. It uses the same reusable release
workflow as tag builds, so every backfilled version gets the full binary,
compressed-binary, archive, checksum, and attestation asset set.

If an older QEMU version cannot be built with the current runtime parameters,
create a major-specific branch such as `backfill/8.x`, make the minimal build
recipe changes needed there, and tag only the commits that successfully build.

## Maintainer note: ZSF qemu fork updates

Edit the following values in `build`:

- `ARTIFACT_BASE_VERSION`
- `ARTIFACT_SERIAL`
- `QEMU_REV`

## Build docker image

```sh
docker build --tag qemu .
```

## Run container, save ID, copy artifact(s)

```sh
mkdir ../artifact
docker run -it --cidfile=qemu.cid qemu true
docker cp "$(cat qemu.cid):work/artifact/." ../artifact/.
```

## Review final artifact(s)

```sh
ls -al ../artifact/
```

## Cleanup container, ID-file, and image

```sh
docker container rm "$(cat qemu.cid)"
rm qemu.cid
docker image rm qemu
```

## Really cleanup docker

```sh
docker system prune --force
```
