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
- [x] macOS builds were prototyped and then dropped because useful artifacts
  require Homebrew runtime libraries.
- [x] Windows was dropped because the supported QEMU build path is MinGW/MSYS2
  and a reliable static-or-near-static artifact is not established.
- [x] Release workflow publishes user, system, `qemu-img`, and system-data
  artifacts for Linux amd64 and arm64.

## Repository Direction

This repository intentionally starts from a clean GitHub repository and fresh
release history. Do not push tags from `qemu-user-prebuilt` here.

For a given upstream QEMU version, build and publish these artifact families:

- `qemu-user`: Linux user-mode emulators, retaining the current project value.
- `qemu-system`: system-mode emulators for supported `*-softmmu` targets.
- `qemu-img`: image tooling needed by CI and build actions.
- `qemu-system-data`: firmware and runtime data needed by `qemu-system-*`.

Treat these as separate CI jobs. Linux may remain parallel where it does not
exhaust the runner quota. macOS is not an active release target.

## Release-Equivalent Workflow Testing

Every active platform should get a workflow test path before being wired into
real release publishing. The test workflow must exercise the same build
scripts, packaging scripts, artifact names, checksum generation, and validation
commands that the release workflow will use. The release workflow should differ
only by the final GitHub Release publication step.

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
3. Revisit Windows only if a static or near-static artifact can be produced
   without requiring an MSYS2/QEMU package installation.

Linux validation should start with a narrow matrix to keep turnaround practical:

- `linux-amd64`.
- `qemu-img`.
- one user-mode target such as `aarch64`.
- one system target, `x86_64-softmmu`.
- one system-data archive from the same install prefix.

Keep validation narrow, but make release artifacts broad. Release system builds
should compile the QEMU `*-softmmu` targets that overlap with the linux-user
guest target set so consumers can find both `qemu-user` and `qemu-system`
artifacts for the same supported guest architecture. Do not add macOS or
Windows release publishing until their validation workflow proves release-shaped
artifacts and the artifacts are meaningfully easier to consume than installing
QEMU from the platform package manager.

2026-04-30 implementation note: Linux build scripts now accept an artifact
family (`user`, `img`, `system`, or `system-data`) and produce release-shaped
archive names for QEMU 11.0.0. The release workflow builds those families for
Linux amd64 and arm64. Release system builds compile the explicit softmmu target
set that overlaps with QEMU's linux-user guest targets. The validation workflow
stays narrow and builds Linux amd64 `qemu-aarch64`, `qemu-img`,
`qemu-system-x86_64`, and system data artifacts. The system binary and system
data archives are packaged from the same system build so `x86_64-softmmu` is
not compiled twice for validation. The smoke test runs `qemu-img`, starts
`qemu-system-x86_64` with `-machine none`, and runs a static aarch64 program
through `qemu-aarch64`.

2026-04-30 GitHub Actions note: release and backfill builds generate artifact
attestations. Validation keeps attestations disabled so pull-request checks stay
focused on build, packaging, checksums, and smoke tests.

2026-04-30 macOS implementation note: macOS builds were prototyped on native
GitHub-hosted macOS runners for `darwin-amd64` and `darwin-arm64`. QEMU's
global `--static` configure option was tested on the Intel macOS runner and is
not viable because Darwin's linker adds `-static` and then fails looking for
`crt0.o`. Dynamic macOS artifacts worked, including Homebrew `libslirp`, but
the system binaries require Homebrew runtime libraries such as `glib`, `gnutls`,
`libpng`, `libslirp`, `libusb`, `lzo`, `pixman`, and `zstd`. Since users would
need Homebrew anyway, macOS release publishing and validation were removed for
now.

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
- Host acceleration where available: KVM on Linux. WHPX is only relevant if
  Windows returns to scope.
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
- TAP networking on Linux.

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

### Release System Targets

These targets are configured in the release matrix because they overlap with
QEMU 11.0.0 linux-user guest targets:

- [x] `aarch64-softmmu`
- [x] `alpha-softmmu`
- [x] `arm-softmmu`
- [x] `hppa-softmmu`
- [x] `i386-softmmu`
- [x] `loongarch64-softmmu`
- [x] `m68k-softmmu`
- [x] `microblaze-softmmu`
- [x] `mips-softmmu`
- [x] `mips64-softmmu`
- [x] `mips64el-softmmu`
- [x] `mipsel-softmmu`
- [x] `or1k-softmmu`
- [x] `ppc-softmmu`
- [x] `ppc64-softmmu`
- [x] `riscv32-softmmu`
- [x] `riscv64-softmmu`
- [x] `s390x-softmmu`
- [x] `sh4-softmmu`
- [x] `sh4eb-softmmu`
- [x] `sparc-softmmu`
- [x] `sparc64-softmmu`
- [x] `x86_64-softmmu`
- [x] `xtensa-softmmu`
- [x] `xtensaeb-softmmu`

Do not add system-only targets such as `avr-softmmu`, `rx-softmmu`, or
`tricore-softmmu` unless the artifact policy changes.

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

Not active for release publishing.

Matrix:

- [x] `darwin-amd64` was prototyped on an Intel-capable macOS runner.
- [x] `darwin-arm64` was prototyped on an Apple Silicon macOS runner.

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
- [x] Drop macOS from release and validation because unbundled artifacts require
  Homebrew runtime dependencies, making `brew install qemu` a better user path.

Open questions:

- [x] Confirm GitHub-hosted runner availability for true Intel macOS builds.
- [x] Decide whether cross-compiling `darwin-amd64` from Apple Silicon is
  acceptable for non-HVF smoke tests: no, because macOS is out of scope.

### Windows

Not active for release publishing. QEMU supports Windows builds through current
MinGW, either cross-built from Linux or built via MSYS2 on Windows. That is a
viable build path, but it is not the same as a proven static binary distribution
path. MSYS2 packages are explicitly dependency-bearing packages that may include
runtime libraries, shared libraries, static import libraries, headers, and
metadata; publishing a QEMU ZIP with collected DLLs would be feasible, but it
does not meet this repository's current static-or-near-static bar.

Matrix:

- [ ] `windows-amd64` on a Windows x64 runner.
- [ ] `windows-arm64` on a Windows arm64 runner if available.

Baseline:

- [x] Reuse the same release-equivalent validation workflow pattern proven on
  Linux before adding Windows release publishing.
- [x] Enable WHPX only if Windows returns to scope.
- [x] Keep TCG only if Windows returns to scope.
- [x] Decide whether a static or near-static MinGW build is practical: not
  established enough to publish now.
- [x] Avoid publishing Windows if required dependencies must be installed
  separately by users.
- [ ] Use `dumpbin /DEPENDENTS` or an equivalent dependency validation tool.
- [ ] Smoke-test `qemu-system-x86_64.exe -accel whpx` availability on amd64
  if Windows returns to scope.
- [ ] Smoke-test `qemu-system-aarch64.exe -accel whpx` availability on arm64
  when the runner supports it.

Open questions:

- [ ] Confirm GitHub-hosted Windows arm64 runner availability and limitations.
- [x] Decide whether Windows artifacts should be `.zip` in addition to
  `.tar.zst`: no Windows artifacts for now.
- [x] Decide whether static linking of QEMU's common deps works reliably with
  the selected MSYS2/UCRT64 or LLVM-MinGW toolchain.

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
- [x] Configure Linux release builds for the softmmu targets that overlap with
  QEMU linux-user guest targets.
- [ ] Add binary static validation.
- [ ] Add `share/qemu` data packaging.
- [ ] Keep existing user-mode release artifact names stable unless a deliberate
  breaking release is planned.

### Phase 3: Release Workflow Expansion

- [ ] Extend `.github/workflows/reusable-release.yml` to build artifact
  families as separate jobs: `qemu-user`, `qemu-img`, `qemu-system`, and
  `qemu-system-data`.
- [ ] Keep non-Linux release jobs out of the matrix until their artifacts are
  worth publishing.
- [x] Upload and attest all artifact families for release publishing.
- [ ] Publish all artifacts and checksums to the GitHub release.
- [ ] Add manual inputs to select artifact families for test runs.
- [ ] Add max-parallel controls for larger matrices.

### Phase 4: macOS Builds

- [x] Add a native macOS build script.
- [x] Add dependency installation strategy.
- [x] Decide not to add `.dylib` bundling or prefix packaging.
- [x] Add `otool -L` validation.
- [x] Add HVF feature validation.
- [x] Remove macOS artifacts from release publishing.

### Phase 5: Windows Builds

- [x] Decide whether `.dll` collection is acceptable; otherwise drop Windows:
  drop Windows for now.
- [x] Do not add Windows artifacts to release publishing.
- [ ] Add a native Windows build script if Windows returns to scope.
- [ ] Add MSYS2/MinGW dependency installation if Windows returns to scope.
- [ ] Add dependency validation if Windows returns to scope.
- [ ] Add WHPX feature validation if Windows returns to scope.

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

Start with one system-data archive per active host OS and host architecture:

- `qemu-system-data-linux-amd64-<version>.tar.zst`
- `qemu-system-data-linux-arm64-<version>.tar.zst`

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
  and prototyped Homebrew `libslirp` for macOS `qemu-system` artifacts.
- Dropped macOS from release publishing and validation after confirming the
  useful system artifacts require external Homebrew runtime libraries.
- Dropped Windows from release publishing after confirming that the practical
  route is MinGW/MSYS2 or collected DLLs, not a proven static-or-near-static
  artifact.
- Decided that Linux comes first and must get a release-equivalent validation
  workflow before real release publishing. Windows should only be revisited if
  it can provide static or near-static artifacts.
