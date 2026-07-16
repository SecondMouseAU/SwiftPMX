---
title: Changelog
nav_order: 2
---

# Changelog

All notable changes to SwiftPMX are documented here. Format loosely follows
[Keep a Changelog](https://keepachangelog.com/en/1.0.0/); versioning follows
[Semantic Versioning](https://semver.org/).

## [1.1.0] - 2026-07-16

### Added

- `PMX.Submesh` and `Mesh.submeshes` — per-material index ranges recovered from the PMX material
  section's `surfaceCount`, so a single part (e.g. a carbody skin) can be isolated from a whole-model
  PMX. No text is decoded to build the table: every name/memo is stepped over with the existing
  `skipString()`. A per-triangle material id is threaded through both degenerate-drop passes
  (pre-weld index-duplicate, post-weld weld-collapse) so offsets stay correct even when a dropped
  face sits in the middle of a material's range. Best-effort: a truncated/malformed material section
  yields `submeshes: []` without affecting `positions`/`indices`.
  ([#4](https://github.com/SecondMouseAU/SwiftPMX/issues/4))

## [1.0.0] - 2026-06-22

### Added

- Initial release: native-Swift PMX 2.0/2.1 geometry reader — vertex positions and the triangle index
  buffer, with left-handed → right-handed conversion, seam welding, degenerate-face culling, and
  uniform scale. Dependency-free (no ICU/Unicode needed, since text fields are never decoded).
