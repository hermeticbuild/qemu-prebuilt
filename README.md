# qemu-static

This repository builds QEMU archives for GitHub releases. Linux artifacts are
static where practical; macOS artifacts use normal Darwin dynamic linking and
leave third-party `.dylib` dependencies as external prerequisites.
It is based on <https://codeberg.org/ziglang/qemu-static> at commit
`96593b61f32eebf2e44d88fbfffdc83f5b622225`.

The purpose of the upstream project is to build a highly compatible linux QEMU
binary package for Zig CI testing.

Zig requires a very recent QEMU version, sometimes unreleased commit-revs, and
sometimes with custom patches. For this reason, distro-based QEMU packages are
unsuitable.

The Linux strategy is to use Alpine Linux to host a QEMU build and link
statically to all possible libraries, including a source-built static libslirp
for `qemu-system` user networking. The macOS strategy is to build natively on
GitHub-hosted macOS runners and document any Homebrew runtime libraries as
prerequisites instead of bundling them into the artifacts.

It is a non-goal to build QEMU with all features enabled.
It is a non-goal to build older versions of QEMU.

## Release workflow

Pushing any tag starts `.github/workflows/release.yml`. The workflow builds
Linux and macOS release artifacts:

- `qemu-user-linux-<host-arch>-<target>-<version>.tar.gz` and `.tar.zst`
  archives
- `qemu-img-linux-<host-arch>-<version>.tar.gz` and `.tar.zst` archives
- `qemu-system-bin-linux-<host-arch>-x86_64-softmmu-<version>.tar.gz` and
  `.tar.zst` archives
- `qemu-system-data-linux-<host-arch>-<version>.tar.gz` and `.tar.zst`
  archives
- `qemu-img-darwin-<host-arch>-<version>.tar.gz` and `.tar.zst` archives
- `qemu-system-bin-darwin-<host-arch>-<system-target>-<version>.tar.gz` and
  `.tar.zst` archives
- `qemu-system-data-darwin-<host-arch>-<version>.tar.gz` and `.tar.zst`
  archives

User-mode archives contain one prefixed executable named
`qemu-user-<os>-<exec-arch>-<target-arch>`. `qemu-img` and system binary
archives preserve QEMU's installed `bin/` layout, and the system data archive
contains installed `share/qemu` runtime data. Each build uploads every archive
and `.sha256` file as workflow artifacts, attests them with GitHub artifact
attestations, and publishes the attestation bundle as a release asset. The final
job creates or updates the GitHub release for the tag and uploads both
architecture artifact sets and checksums. GitHub artifact attestations are
optional because private repositories require organization support for that
feature; manual release runs can enable them with `attest`.

`.github/workflows/validate-linux.yml` is the Linux release-equivalent
validation workflow. It builds a narrow Linux amd64 matrix for QEMU 11.0.0 by default:
`qemu-aarch64`, `qemu-img`, `qemu-system-x86_64`, and one system data archive.
The smoke job runs `qemu-img`, starts `qemu-system-x86_64` with `-machine none`,
checks that the `user` network backend is compiled in, and runs a static
aarch64 program through the packaged `qemu-aarch64`.

`.github/workflows/validate-macos.yml` validates native macOS artifacts before
they are added to release publishing. It builds `qemu-img`, one host-native
`qemu-system-*` binary, and one system data archive for `darwin-amd64` and
`darwin-arm64`. macOS binary artifacts contain the QEMU binaries only; users
must install any linked Homebrew libraries, including `libslirp` for
`qemu-system` user networking, with Homebrew. System data remains a separate
`share/qemu` archive and can be passed to QEMU with `-L`.

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

To build one release-shaped artifact family locally:

```sh
tools/build-qemu.sh amd64 11.0.0 user aarch64-linux-user
tools/build-qemu.sh amd64 11.0.0 img
tools/build-qemu.sh amd64 11.0.0 system x86_64-softmmu
tools/smoke-test-linux-artifacts.sh out amd64
```

On macOS, build native artifacts with:

```sh
tools/build-qemu-macos.sh arm64 11.0.0 img
tools/build-qemu-macos.sh arm64 11.0.0 system aarch64-softmmu
tools/smoke-test-macos-artifacts.sh out arm64
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
