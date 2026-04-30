# QEMU System Prebuilts Plan

This document tracks the work needed to turn `hermeticbuild/qemu-prebuilt` into
the replacement repository for QEMU prebuilts. The existing
`hermeticbuild/qemu-user-prebuilt` repository keeps its existing tags and
releases; this repository starts fresh and rebuilds the artifact model around
QEMU user-mode binaries, QEMU system-mode binaries, and `qemu-img`.

Update this file at the end of each implementation pass. Change task checkboxes,
append short dated notes, and keep decisions concrete enough that another Codex
session can continue from here without re-discovering context.

This plan is a living engineering document. If a build result, CI result, or
platform finding contradicts this plan, update the plan in the same pass instead
of preserving stale assumptions.

## Current Status

- [x] Linux user-mode static build exists for `amd64` and `arm64`.
- [x] Static `qemu-img` feasibility was tested on Alpine 3.23.4 with QEMU
  11.0.0.
- [x] Static Linux AIO and io_uring feasibility was tested on Alpine 3.23.4.
- [x] Static `qemu-system-x86_64` feasibility was tested on Alpine 3.23.4.
- [x] Linux system build scripts are implemented.
- [x] macOS build scripts are implemented.
- [ ] Windows build scripts are implemented.
- [x] Release workflow publishes user, system, `qemu-img`, and system-data
  artifacts for Linux amd64 and arm64.
- [x] Release workflow publishes system, `qemu-img`, and system-data artifacts
  for macOS amd64 and arm64.

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

## Release-Equivalent Workflow Testing

Every platform should get a workflow test path before being wired into real
release publishing. The test workflow must exercise the same build scripts,
packaging scripts, artifact names, checksum generation, and validation commands
that the release workflow will use. The release workflow should differ only by
the final GitHub Release publication step.

Preferred workflow structure:

- A reusable artifact build workflow builds one artifact family for one host
  platform and uploads the resulting artifacts.
- A manual and pull-request validation workflow calls that reusable build
  workflow with test inputs and validates produced archives.
- The release workflow calls the same reusable build workflow, then downloads
  those artifacts and publishes them.

This avoids a separate "CI-only" build path that can pass while release still
fails.

Implementation order:

1. Linux first: create the reusable build path and a manual validation workflow
   for Linux `qemu-user`, `qemu-img`, `qemu-system`, and `qemu-system-data`.
2. Once Linux validation produces release-shaped artifacts, wire Linux into the
   release workflow.
3. Repeat the same validation-first pattern for macOS.
4. Repeat the same validation-first pattern for Windows.

Linux validation should start with a narrow matrix to keep turnaround practical:

- `linux-amd64`.
- `qemu-img`.
- one user-mode target such as `aarch64`.
- one system target, `x86_64-softmmu`.
- one system-data archive from the same install prefix.

After that passes in GitHub Actions, expand to `linux-arm64`, then Tier 1 system
targets, then the remaining user targets. Do not add macOS or Windows release
publishing until their validation workflow proves release-shaped artifacts.

2026-04-30 implementation note: Linux build scripts now accept an artifact
family (`user`, `img`, `system`, or `system-data`) and produce release-shaped
archive names for QEMU 11.0.0. The release workflow builds those families for
Linux amd64 and arm64, with `x86_64-softmmu` as the initial system target. The
validation workflow builds Linux amd64 `qemu-aarch64`, `qemu-img`,
`qemu-system-x86_64`, and system data artifacts. The system binary and system
data archives are packaged from the same system build so `x86_64-softmmu` is
not compiled twice for validation. The smoke test runs `qemu-img`, starts
`qemu-system-x86_64` with `-machine none`, and runs a static aarch64 program
through `qemu-aarch64`.

2026-04-30 GitHub Actions note: artifact attestations are optional because the
private `hermeticbuild` organization did not have the attestation feature
available during validation. Keep validation focused on build, packaging,
checksums, and smoke tests unless repository billing/visibility changes.

2026-04-30 macOS implementation note: macOS builds use native GitHub-hosted
macOS runners. The first validation matrix builds `qemu-img`, one host-native
system target, and one system data archive for `darwin-amd64` and
`darwin-arm64`. QEMU's global `--static` configure option was tested on the
Intel macOS runner and is not viable because Darwin's linker adds `-static` and
then fails looking for `crt0.o`. macOS artifacts therefore use normal Darwin
dynamic linking. Homebrew runtime `.dylib` dependencies are treated as external
prerequisites rather than bundled files. `libslirp` is installed with Homebrew
and enabled for macOS `qemu-system` artifacts. The macOS smoke workflow installs
the linked Homebrew runtime dependencies before executing the unbundled
artifacts. System data remains a separate `share/qemu` archive and is passed
explicitly with `-L` in smoke tests.

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
package installs only shared libraries. The Linux `qemu-system` build now
builds libslirp 4.9.1 from source with Meson's `--default-library=static`,
installs it into `/work/deps/libslirp`, and puts that pkg-config directory ahead
of QEMU configure. `qemu-img` and `qemu-user` keep slirp disabled because they do
not need the user networking backend.

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

- [ ] Add a Linux workflow validation entrypoint that calls the same reusable
  artifact build jobs the release workflow will use.
- [ ] Start Linux workflow validation with a narrow matrix:
  `linux-amd64`, `qemu-img`, one user target, one system target, and
  `qemu-system-data`.
- [x] Add Linux package dependencies for `qemu-img` and system static builds:
  `libaio-dev`, `liburing-dev`, `bzip2-static`, `pixman-static`,
  `util-linux-static`.
- [x] Decide whether to build static libslirp from source.
- [x] Split build modes: `user`, `qemu-img`, `system`.
- [x] Add `SYSTEM_TARGET_LIST` handling.
- [x] Validate installed binaries with `file`, `ldd`, and `readelf -d`.

### macOS

Use native macOS runners, not Docker.

Matrix:

- [x] `darwin-amd64` on an Intel-capable macOS runner if available.
- [x] `darwin-arm64` on an Apple Silicon macOS runner if available.

Baseline:

- [x] Reuse the same release-equivalent validation workflow pattern proven on
  Linux before adding macOS release publishing.
- [x] Enable HVF.
- [x] Keep TCG.
- [x] Build portable dynamic artifacts; do not promise fully static binaries.
- [x] Keep required `.dylib` dependencies external; do not bundle Homebrew
  libraries.
- [x] Enable slirp via Homebrew `libslirp` for system artifacts.
- [x] Use `otool -L` validation.
- [x] Verify `qemu-system-aarch64 -accel hvf` exists on arm64 builds.
- [x] Verify `qemu-system-x86_64 -accel hvf` exists on amd64 builds.

Open questions:

- [x] Confirm GitHub-hosted runner availability for true Intel macOS builds.
- [ ] Decide whether cross-compiling `darwin-amd64` from Apple Silicon is
  acceptable for non-HVF smoke tests.

### Windows

Use native Windows runners or an MSYS2/MinGW setup on Windows runners.

Matrix:

- [ ] `windows-amd64` on a Windows x64 runner.
- [ ] `windows-arm64` on a Windows arm64 runner if available.

Baseline:

- [ ] Reuse the same release-equivalent validation workflow pattern proven on
  Linux before adding Windows release publishing.
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

### Phase 0: Linux Release-Equivalent Workflow

- [ ] Add a reusable artifact-family build workflow that can be called by both
  validation and release workflows.
- [ ] Add a manual Linux validation workflow that uses release-shaped artifact
  names and archive contents.
- [ ] Validate produced archives without creating or updating a GitHub Release.
- [ ] Keep the final release publish job as the only meaningful difference
  between validation and release.
- [ ] Run the workflow on GitHub Actions and record the run URL and findings in
  "Iteration Notes".

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

- [x] Add a native macOS build script.
- [x] Add dependency installation strategy.
- [ ] Add `.dylib` bundling or prefix packaging.
- [x] Add `otool -L` validation.
- [x] Add HVF feature validation.
- [x] Add macOS artifacts to release publishing.

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

1. Read `AGENT.md`.
2. Read this file.
3. Check `git status --short`.
4. Identify the next unchecked phase item.
5. Run or update the relevant build probe before changing CI.
6. Keep packaging naming explicit; do not add broad `bin/qemu-*` loops.
7. If new findings make this plan wrong, edit this plan before or alongside the
   implementation change.

At the end of a session:

1. Mark completed checkboxes in this file.
2. Add a short note under "Iteration Notes".
3. Record exact commands used for any new feasibility claim.
4. Record any package/version/platform caveats.
5. Record workflow run URLs for CI claims.

## Iteration Notes

### 2026-04-30

- Verified Linux static `qemu-img` with tools, Linux AIO, and io_uring on
  Alpine 3.23.4 / QEMU 11.0.0.
- Verified Alpine static libraries for `libaio` and `liburing`.
- Verified Linux static `qemu-system-x86_64` on Alpine 3.23.4 / QEMU 11.0.0.
- Confirmed current packaging misclassifies `qemu-img` and
  `qemu-system-x86_64` when broad `bin/qemu-*` matching is used.
- Confirmed Alpine 3.23.4 does not package static `libslirp.a`.
- Added a source-built static libslirp path for Linux `qemu-system` artifacts
  and enabled Homebrew `libslirp` for macOS `qemu-system` artifacts.
- Decided that Linux comes first and must get a release-equivalent validation
  workflow before real release publishing. macOS and Windows should reuse that
  validation-first pattern after Linux works.
