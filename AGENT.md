# Agent Notes

This repository builds and publishes portable QEMU prebuilts for build systems
and CI environments.

The project goal is to provide reproducible release artifacts for:

- QEMU user-mode emulators.
- QEMU system-mode emulators.
- `qemu-img`.
- Runtime data needed by QEMU system emulators, such as firmware and
  `share/qemu` files.

The current implementation plan is tracked in
`docs/system-prebuilts-plan.md`. Read that plan before starting work. Treat it
as a living document: when build results, CI behavior, platform constraints, or
packaging findings change the direction, amend the plan in the same branch as
the code change.

Keep repository history here independent from `hermeticbuild/qemu-user-prebuilt`.
Do not import or push tags from the older repository.
