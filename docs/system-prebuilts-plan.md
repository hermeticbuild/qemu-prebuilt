# QEMU System Prebuilts Plan

This document tracks the work needed to turn `hermeticbuild/qemu-prebuilt` into
the replacement repository for QEMU prebuilts. The existing
`hermeticbuild/qemu-user-prebuilt` repository keeps its existing tags and
releases; this repository starts fresh and rebuilds the artifact model around
QEMU user-mode binaries, QEMU system-mode binaries, and `qemu-img`.

Update this file at the end of each implementation pass. Change task checkboxes,
append short dated notes, and keep decisions concrete enough that another Codex
session can continue from here without re-discovering context.

## Current Status

- [x] Linux user-mode static build exists for `amd64` and `arm64`.
- [x] Static `qemu-img` feasibility was tested on Alpine 3.23.4 with QEMU
  11.0.0.
- [x] Static Linux AIO and io_uring feasibility was tested on Alpine 3.23.4.
- [x] Static `qemu-system-x86_64` feasibility was tested on Alpine 3.23.4.
- [ ] Linux system build scripts are implemented.
- [ ] macOS build scripts are implemented.
- [ ] Windows build scripts are implemented.
- [ ] Release workflow publishes user, system, `qemu-img`, and system-data
  artifacts.

## Repository Direction

This repository intentionally starts from a clean GitHub repository and fresh
release history. Do not push tags from `qemu-user-prebuilt` here.

For a given upstream QEMU version, build and publish these artifact families:

- `qemu-user`: Linux user-mode emulators, retaining the current project value.
- `qemu-system`: system-mode emulators for supported `*-softmmu` targets.
- `qemu-img`: image tooling needed by CI and build actions.
- `qemu-system-data`: firmware and runtime data needed by `qemu-system-*`.

Treat these as separate CI jobs. Sequential execution is acceptable, and is
preferred for macOS and Windows until runner allocation and build duration are
well understood. Linux may remain more parallel where it does not exhaust the
runner quota.

## Verified Feasibility Notes

### Linux Static User Tools

Tested command shape:

```sh
configure \
  --disable-system \
  --enable-linux-user \
  --enable-tools \
  --enable-linux-io-uring \
  --enable-linux-aio \
  --static
```

Result: `qemu-img` linked as static PIE. `file` reported `static-pie linked`,
`ldd` reported only the musl loader line, and `readelf -d` had no `NEEDED`
entries.

Alpine packages verified:

- `libaio-dev` provides `/usr/lib/libaio.a`.
- `liburing-dev` provides `/usr/lib/liburing.a`.
- `bzip2-static` is also required once tools/block formats are enabled.

### Linux Static System

Tested command shape:

```sh
configure \
  --enable-system \
  --disable-linux-user \
  --disable-tools \
  --disable-guest-agent \
  --target-list=x86_64-softmmu \
  --disable-gtk \
  --disable-sdl \
  --disable-vnc \
  --disable-opengl \
  --disable-curses \
  --disable-spice \
  --disable-pa \
  --disable-jack \
  --disable-oss \
  --disable-alsa \
  --disable-brlapi \
  --disable-dbus-display \
  --static
```

Result: `qemu-system-x86_64` linked as static PIE. `file` reported
`static-pie linked`, `ldd` reported only the musl loader line, and `readelf -d`
had no `NEEDED` entries.

Alpine packages verified:

- `pixman-static` is required for static system binaries.
- `util-linux-static` is required because `gio-2.0` pulls static `libmount.a`
  and `libblkid.a`.
- `bzip2-static` remains required.

The system install produced `share/qemu` data. For the x86_64-only probe,
`share/qemu` contained 116 files, including BIOS/UEFI blobs, firmware
descriptors, DTBs, keymaps, option ROMs, and `trace-events-all`.

### Linux Static Slirp

Alpine 3.23.4 has `libslirp-dev` but not a `libslirp-static` package. The
package installs only shared libraries. If Linux artifacts must remain fully
static and still support `-netdev user`, static libslirp needs a separate
source build or vendored dependency build.

## Artifact Model

Do not classify every `bin/qemu-*` as a user-mode target. Current packaging
would mislabel `qemu-img` as target `img` and `qemu-system-x86_64` as target
`system-x86_64`.

Target artifact families:

- `qemu-user-<host-os>-<host-arch>-<guest-arch>-<version>.tar.{gz,zst}`
  contains exactly one prefixed user-mode executable.
- `qemu-img-<host-os>-<host-arch>-<version>.tar.{gz,zst}` contains `qemu-img`
  and only the runtime files it needs.
- `qemu-system-bin-<host-os>-<host-arch>-<system-target>-<version>.tar.{gz,zst}`
  contains exactly one system emulator executable, for example
  `bin/qemu-system-x86_64`.
- `qemu-system-data-<host-os>-<host-arch>-<version>.tar.{gz,zst}` contains
  system data installed under `share/qemu` and, if present, related firmware
  descriptor directories.

Preferred first implementation: ship one `qemu-system-data` archive per
host OS and host architecture build. That keeps artifact reuse simple while
avoiding assumptions that every host build installs byte-identical firmware
metadata.

Later optimization: if checksums prove `share/qemu` is identical across host
architectures for the same QEMU version and configure surface, collapse to one
`qemu-system-data-<version>` artifact. Do not do this until CI verifies it.

## Baseline System Feature Policy

The goal is a headless QEMU suitable for CI build actions and custom guest
images, not a full desktop QEMU distribution.

Keep enabled:

- TCG on every platform.
- Host acceleration where available: KVM on Linux, HVF on macOS, WHPX on
  Windows.
- Default devices.
- Block layer and common local image formats.
- `qemu-img`.
- Serial, stdio, socket, file, and null character devices.
- VirtIO block, net, serial, rng, console, and 9p where supported.
- Firmware/blob installation.
- Pixman for system emulation internals.

Prefer enabled when statically or portably packageable:

- Linux AIO and io_uring on Linux.
- User-mode networking via slirp.
- TAP networking on Linux and macOS.

Disable for baseline headless artifacts:

- GTK, SDL, VNC, SPICE.
- OpenGL, VirGL, rutabaga.
- Audio backends.
- USB redirection and smartcard support unless a real build-action use case
  appears.
- Docs and guest agent.

## Target Sets

The system target name is the QEMU `*-softmmu` target. For example,
`x86_64-softmmu` builds `qemu-system-x86_64`.

Do not derive system targets by stripping `qemu-` from existing user-mode
binaries. Query QEMU for supported system targets and maintain an explicit
allowlist.

### Tier 1 System Targets

These are the first targets to support because they are most useful for CI and
cross-architecture build testing:

- [ ] `aarch64-softmmu`
- [ ] `arm-softmmu`
- [ ] `i386-softmmu`
- [x] `x86_64-softmmu` feasibility checked on Linux static
- [ ] `riscv32-softmmu`
- [ ] `riscv64-softmmu`
- [ ] `ppc-softmmu`
- [ ] `ppc64-softmmu`
- [ ] `s390x-softmmu`
- [ ] `mips-softmmu`
- [ ] `mipsel-softmmu`
- [ ] `mips64-softmmu`
- [ ] `mips64el-softmmu`
- [ ] `loongarch64-softmmu`

### Tier 2 System Targets

Add these after the Tier 1 matrix is stable:

- [ ] `alpha-softmmu`
- [ ] `hppa-softmmu`
- [ ] `m68k-softmmu`
- [ ] `microblaze-softmmu`
- [ ] `microblazeel-softmmu`
- [ ] `nios2-softmmu`
- [ ] `or1k-softmmu`
- [ ] `sh4-softmmu`
- [ ] `sh4eb-softmmu`
- [ ] `sparc-softmmu`
- [ ] `sparc64-softmmu`
- [ ] `xtensa-softmmu`
- [ ] `xtensaeb-softmmu`

## CI Matrix Plan

### Linux

Use current Docker-on-Linux approach initially because it already produces
static musl artifacts.

Matrix:

- [ ] `linux-amd64` on `ubuntu-24.04`, Docker platform `linux/amd64`.
- [ ] `linux-arm64` on `ubuntu-24.04-arm`, Docker platform `linux/arm64`.

Tasks:

- [ ] Add Linux package dependencies for `qemu-img` and system static builds:
  `libaio-dev`, `liburing-dev`, `bzip2-static`, `pixman-static`,
  `util-linux-static`.
- [ ] Decide whether to build static libslirp from source.
- [ ] Split build modes: `user`, `qemu-img`, `system`.
- [ ] Add `SYSTEM_TARGET_LIST` handling.
- [ ] Validate installed binaries with `file`, `ldd`, and `readelf -d`.

### macOS

Use native macOS runners, not Docker.

Matrix:

- [ ] `darwin-amd64` on an Intel-capable macOS runner if available.
- [ ] `darwin-arm64` on an Apple Silicon macOS runner if available.

Baseline:

- [ ] Enable HVF.
- [ ] Keep TCG.
- [ ] Build portable dynamic artifacts; do not promise fully static binaries.
- [ ] Bundle required `.dylib` dependencies or produce a self-contained prefix.
- [ ] Use `otool -L` validation.
- [ ] Verify `qemu-system-aarch64 -accel hvf` exists on arm64 builds.
- [ ] Verify `qemu-system-x86_64 -accel hvf` exists on amd64 builds.

Open questions:

- [ ] Confirm GitHub-hosted runner availability for true Intel macOS builds.
- [ ] Decide whether cross-compiling `darwin-amd64` from Apple Silicon is
  acceptable for non-HVF smoke tests.

### Windows

Use native Windows runners or an MSYS2/MinGW setup on Windows runners.

Matrix:

- [ ] `windows-amd64` on a Windows x64 runner.
- [ ] `windows-arm64` on a Windows arm64 runner if available.

Baseline:

- [ ] Enable WHPX.
- [ ] Keep TCG.
- [ ] Build portable dynamic artifacts; do not promise fully static binaries.
- [ ] Bundle required `.dll` dependencies beside `.exe` files.
- [ ] Use `dumpbin /DEPENDENTS` or an equivalent dependency validation tool.
- [ ] Smoke-test `qemu-system-x86_64.exe -accel whpx` availability on amd64.
- [ ] Smoke-test `qemu-system-aarch64.exe -accel whpx` availability on arm64
  when the runner supports it.

Open questions:

- [ ] Confirm GitHub-hosted Windows arm64 runner availability and limitations.
- [ ] Decide whether Windows artifacts should be `.zip` in addition to
  `.tar.zst`.

## Implementation Phases

### Phase 1: Packaging Split

- [ ] Replace `tools/package-qemu-artifacts.sh` with mode-aware packaging or
  add separate package scripts.
- [ ] Package only actual Linux user-mode binaries as `qemu-user-*`.
- [ ] Package `qemu-img` as `qemu-img-*`.
- [ ] Package system binaries as `qemu-system-bin-*`.
- [ ] Package system data as `qemu-system-data-*`.
- [ ] Add archive member validation for multi-file artifacts.
- [ ] Add checksum generation for every artifact.

### Phase 2: Linux Tools and System Builds

- [ ] Add build mode inputs to `tools/build-qemu.sh`.
- [ ] Add Linux static `qemu-img` build with AIO and io_uring enabled.
- [ ] Ensure `qemu-img` is a separate build/release job from `qemu-user` and
  `qemu-system`.
- [ ] Add Linux static system build for Tier 1 targets.
- [ ] Add binary static validation.
- [ ] Add `share/qemu` data packaging.
- [ ] Keep existing user-mode release artifact names stable unless a deliberate
  breaking release is planned.

### Phase 3: Release Workflow Expansion

- [ ] Extend `.github/workflows/reusable-release.yml` to build artifact
  families as separate jobs: `qemu-user`, `qemu-img`, `qemu-system`, and
  `qemu-system-data`.
- [ ] Use sequential dependencies between artifact-family jobs on macOS and
  Windows to avoid saturating runner allocation.
- [ ] Upload and attest all artifact families.
- [ ] Publish all artifacts and checksums to the GitHub release.
- [ ] Add manual inputs to select artifact families for test runs.
- [ ] Add max-parallel controls for larger matrices.

### Phase 4: macOS Builds

- [ ] Add a native macOS build script.
- [ ] Add dependency installation strategy.
- [ ] Add `.dylib` bundling or prefix packaging.
- [ ] Add `otool -L` validation.
- [ ] Add HVF feature validation.
- [ ] Add macOS artifacts to release publishing.

### Phase 5: Windows Builds

- [ ] Add a native Windows build script.
- [ ] Add MSYS2/MinGW dependency installation.
- [ ] Add `.dll` collection.
- [ ] Add dependency validation.
- [ ] Add WHPX feature validation.
- [ ] Add Windows artifacts to release publishing.

### Phase 6: Smoke Tests

- [ ] For every `qemu-system-*`, run `--version`.
- [ ] For every `qemu-system-*`, run `-machine help`.
- [ ] For targets with `virt` machines, run a no-guest smoke test using
  `-machine virt -nographic -nodefaults -S`.
- [ ] For x86 targets, run a no-guest smoke test using
  `-machine q35 -nographic -nodefaults -S`.
- [ ] Add a small `qemu-img create` smoke test.
- [ ] Add static/dynamic dependency validation per platform.

## Data Archive Grouping Policy

Start with one system-data archive per host OS and host architecture:

- `qemu-system-data-linux-amd64-<version>.tar.zst`
- `qemu-system-data-linux-arm64-<version>.tar.zst`
- `qemu-system-data-darwin-amd64-<version>.tar.zst`
- `qemu-system-data-darwin-arm64-<version>.tar.zst`
- `qemu-system-data-windows-amd64-<version>.zip`
- `qemu-system-data-windows-arm64-<version>.zip`

Reason: configure results, path conventions, firmware descriptors, and installed
auxiliary data can vary by host platform or feature set. Per-host data avoids
subtle mismatches.

Only collapse data archives when CI proves the full file list and file hashes
match. If collapsing is implemented, publish a manifest recording which binary
artifacts are compatible with each data archive.

## Future Session Checklist

At the start of a session:

1. Read this file.
2. Check `git status --short`.
3. Identify the next unchecked phase item.
4. Run or update the relevant build probe before changing CI.
5. Keep packaging naming explicit; do not add broad `bin/qemu-*` loops.

At the end of a session:

1. Mark completed checkboxes in this file.
2. Add a short note under "Iteration Notes".
3. Record exact commands used for any new feasibility claim.
4. Record any package/version/platform caveats.

## Iteration Notes

### 2026-04-30

- Verified Linux static `qemu-img` with tools, Linux AIO, and io_uring on
  Alpine 3.23.4 / QEMU 11.0.0.
- Verified Alpine static libraries for `libaio` and `liburing`.
- Verified Linux static `qemu-system-x86_64` on Alpine 3.23.4 / QEMU 11.0.0.
- Confirmed current packaging misclassifies `qemu-img` and
  `qemu-system-x86_64` when broad `bin/qemu-*` matching is used.
- Confirmed Alpine 3.23.4 does not package static `libslirp.a`.
