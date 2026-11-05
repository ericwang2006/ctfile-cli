---
name: CTfile CLI Release
description: Build all cross-platform binaries with build.sh (Windows 7-compatible via the go-legacy-win7 toolchain) and publish a new GitHub Release (tag, title, 12 assets) for ericwang2006/ctfile-cli.
---

## When to use

Use this when the user asks to publish/发布 a new Release for **ctfile-cli**
(e.g. "发布一个新版本 vXX.XX.XX"), including creating the tag and attaching the
compiled binaries. This project has no CI, so the release is created directly
through the GitHub API.

## Prerequisites

- Run from the ctfile-cli repository root (contains `build.sh` and `ctfile-cli.go`).
- A GitHub token with write access to `ericwang2006/ctfile-cli`:
  - classic PAT with `repo` scope, or
  - fine-grained PAT with **Contents: Read and write** on the repository.
- Tools: `curl`, `python3`, `zip`, `tar`, and network access on the first build.
  A system Go install is **not** required: `build.sh` downloads the
  `go-legacy-win7` toolchain itself (see [Toolchain](#toolchain-windows-7-compatibility)).
  Cross `*-strip` tools are optional — `build.sh` degrades gracefully when they
  are missing.

## Workflow

1. **Confirm the version.** Ask for the tag if the user did not give one.
   Convention: `vYY.MM.DD` (e.g. `v26.11.05`). Never reuse an existing tag:
   ```bash
   git fetch --tags
   git tag -l '<tag>'
   ```
2. **Review what changed** since the previous release to write the notes:
   ```bash
   git log --oneline "$(git describe --tags --abbrev=0 HEAD)..HEAD"
   ```
3. **Build all binaries** (12 platforms → `dist/`):
   ```bash
   ./build.sh
   ls -la dist/
   ```
   On the first run `build.sh` downloads the `go-legacy-win7` toolchain
   (≈65 MB) into `GO_LEGACY_DIR`, extracts it, and prints the Go version it
   uses; later runs reuse it. Every target is compiled with that toolchain so
   the Windows binaries remain compatible with Windows 7.
4. **Provide the token** without leaking it into logs:
   ```bash
   printf '%s' '<TOKEN>' > /tmp/opencode/gh_token && chmod 600 /tmp/opencode/gh_token
   ```
5. **Publish** with the bundled script:
   ```bash
   scripts/publish_release.sh --tag vXX.XX.XX
   ```
   It verifies the token, creates the tag + Release on `main`, uploads every file
   in `dist/`, and prints the result. Override the notes with `--body "..."`
   (or `--body-file <file>`); by default it uses the latest commit subject,
   which matches past releases.
6. **Report** the release URL and asset list, then **remove the token file**:
   ```bash
   rm -f /tmp/opencode/gh_token
   ```
   If the token was pasted into chat, remind the user to revoke it in
   GitHub → Settings → Developer settings → Personal access tokens.

## Toolchain (Windows 7 compatibility)

Upstream Go dropped Windows 7/8/8.1 support in Go 1.21: its Windows binaries are
stamped `10.0` and refuse to start on Win7. This project therefore compiles with
[`thongtech/go-legacy-win7`](https://github.com/thongtech/go-legacy-win7), a fork
that restamps the PE target version to `6.1` and falls back to legacy Windows
APIs on old systems while matching stock Go on modern Windows.

`build.sh` manages the toolchain automatically and pins the version:

| Env var | Default | Meaning |
| ------- | ------- | ------- |
| `GO_LEGACY_VERSION` | `1.27.3-1` | Release tag to install (no leading `v`) |
| `GO_LEGACY_DIR` | `$HOME/.local/go-legacy-win7` | Install dir; reused when `bin/go` exists |
| `GO_BIN` | unset | Force a specific `go` binary and skip the install |

The correct archive is chosen from the host OS/arch, so the release can be built
on Linux or macOS. Verify a Windows build targets Win7 (expect
`MajorOSystemVersion 6` / `MinorOSystemVersion 1`):

```bash
unzip -o dist/ctfile-cli_windows_amd64.zip -d /tmp/pe
x86_64-w64-mingw32-objdump -p /tmp/pe/ctfile-cli.exe | grep OSystemVersion
```

To upgrade the toolchain, set `GO_LEGACY_VERSION` to a newer tag and remove
`GO_LEGACY_DIR` so it reinstalls.

## Conventions

- Repository: `ericwang2006/ctfile-cli`, base branch `main`.
- Release title: `ctfile-cli <tag>` (e.g. `ctfile-cli v26.11.05`).
- Release body: a short Chinese summary, usually the main commit subject.
- The 12 assets produced by `build.sh`:

  | Platform | Asset |
  | -------- | ----- |
  | Linux x86_64 | `ctfile-cli_linux_amd64.tar.gz` |
  | Linux i686 | `ctfile-cli_linux_386.tar.gz` |
  | Linux ARM | `ctfile-cli_linux_arm.tar.gz` |
  | Linux ARM64 | `ctfile-cli_linux_arm64.tar.gz` |
  | Linux MIPS | `ctfile-cli_linux_mips.tar.gz` |
  | Linux MIPSEL | `ctfile-cli_linux_mipsle.tar.gz` |
  | Linux MIPS64 | `ctfile-cli_linux_mips64.tar.gz` |
  | Linux MIPS64EL | `ctfile-cli_linux_mips64le.tar.gz` |
  | macOS x86_64 | `ctfile-cli_darwin_amd64.tar.gz` |
  | macOS ARM64 | `ctfile-cli_darwin_arm64.tar.gz` |
  | Windows x86_64 | `ctfile-cli_windows_amd64.zip` |
  | Windows i686 | `ctfile-cli_windows_386.zip` |

- Upload content types: `.tar.gz` → `application/x-gzip`, `.zip` → `application/zip`.
- Archive layout: the inner binary is always named `ctfile-cli`
  (`ctfile-cli.exe` on Windows), regardless of platform.

## Notes

- `build.sh` skips `strip` for macOS and for targets without a cross-strip tool;
  this is expected and not an error.
- The `go-legacy-win7` fork tracks current Go (1.27.x), so the non-Windows
  targets are unaffected; only the Windows binaries change (PE target `6.1`).
- Never print the token or let it appear in command output. Keep it only in the
  token file and read it inside the script.
- If `gh` is installed and authenticated, an equivalent shortcut is
  `gh release create <tag> -t "ctfile-cli <tag>" -n "<body>" dist/* --target main`.
  The script exists so publishing works with just a raw token.
