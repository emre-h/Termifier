# Termifier

Termifier is a native macOS terminal for running and supervising multiple coding agents without leaving the terminal workflow.

## Fork notice

Termifier is a fork of [Yuuichi Eguchi's Calyx](https://github.com/yuuichieguchi/Calyx). This fork renames the application and its supporting tools to Termifier, uses a new app icon, and removes the built-in Sparkle updater.

## Highlights

- Native AppKit and SwiftUI interface powered by libghostty
- Tabs, split panes, tab groups, persistent sessions, and remote sessions
- Agent status tracking and a shared approval inbox
- Git changes, commit history, and inline diff review
- MCP tools for terminal control, agent communication, command history, and LSP features
- Scriptable browser tabs and a bundled `termifier` CLI

## Features added in this fork

In addition to the Termifier rebrand, this fork includes:

- A custom Termifier app icon and removal of the Sparkle updater.
- An SSH sidebar next to Tabs, Changes, and Agents for saved server profiles, grouped into collapsible folders.
- Password, identity-file and agent authentication. Passwords live in the macOS Keychain; connection metadata is kept locally.
- Editable SSH profiles with password preservation when the password field is left blank.
- Port forwarding per profile (`-L`, `-R`, `-D`) with a live indicator showing whether the forwarded ports are listening.
- Jump hosts (`ProxyJump`) for servers behind a bastion.
- Import of the hosts in `~/.ssh/config`, including their user, port, identity file, `ProxyJump` and forwardings.
- File transfer to and from a profile: drag files onto a row to upload, or use Upload/Download from its context menu.
- A remote file browser that opens as a **Files** tab beside the terminal tabs: browse, create, rename, delete and chmod over SFTP, with drag-and-drop upload.
- Host-key management: the editor shows whether a key is recorded in `known_hosts` and can forget a stale one.
- A per-profile startup command, and one-click connection opening in a new terminal tab with a standard `xterm-256color` environment for Linux compatibility.

### SSH sessions

Click **SSH** in the sidebar to add or edit a connection. Choose Password, Identity File or Agent
authentication, then click a saved profile to open it as a terminal tab automatically.

![SSH session opened in Termifier](docs/ssh-session.png)

**Import existing hosts.** *Import from ssh config* reads `~/.ssh/config` and lists every concrete
`Host` block with the settings it already has. `Include` directives and `Match` blocks are not
resolved; a `Host *` block is applied as a default.

**Port forwarding.** Add `-L`, `-R` and `-D` rules to a profile and they are opened with the session.
The dot on the sidebar row reflects what is actually listening on this Mac: green when every
forwarded port is bound, orange when only some are, hollow when none are. Remote (`-R`) forwardings
listen on the server, so they are shown as not observable from here rather than as down.

**Jump hosts.** A comma-separated chain in the profile becomes `ssh -J`, outermost bastion first.

**File transfer.** Drag files or folders onto a profile row to upload them to its remote folder, or
use *Upload Files…* / *Download…* from the row's context menu. Transfers run as `scp` in their own
tab, so progress, prompts and errors stay visible.

**Remote file browser.** The folder button on a profile's row — or *Browse Files…* in its context
menu — opens a **Files** tab for that server, beside the terminal and browser tabs. A second click
returns to the tab that is already open for that profile instead of opening another one. These tabs
are not saved into the session snapshot: restoring one would re-authenticate to a remote host at
launch, before you asked for anything.

The tab lists a directory with sizes, permissions and owners, navigates with an editable path field,
and can create folders, rename, change permissions and delete — deleting a folder removes its
contents, and a symlink row deletes the link rather than its target. Dropping files into it uploads
them into the directory on screen; downloads ask where to save. Both run as `scp` in a terminal tab,
so a large transfer keeps its progress meter.

The browser drives the OpenSSH `sftp` client, one batch process per operation, with
`ControlMaster` multiplexing so the operations after the first reuse a single authenticated
connection.

**Host keys.** Sessions connect with `StrictHostKeyChecking=accept-new`, which refuses a host whose
recorded key changed — the usual state after a server rebuild. The editor shows the recorded key
types, and *Forget* (also in the row's context menu) removes the entry so the next connection
records the new key. `ssh-keygen -R` keeps a `known_hosts.old` backup.

## Requirements

- macOS 26 Tahoe or later
- Xcode 26 or later
- [Zig](https://ziglang.org/)
- [XcodeGen](https://github.com/yonaskolb/XcodeGen)

## Build from source

Clone the repository with its submodules:

```bash
git clone --recursive https://github.com/emre-h/Termifier.git
cd Termifier
```

Build the Ghostty framework:

```bash
cd ghostty
zig build -Demit-xcframework=true -Dxcframework-target=native
cd ..
cp -R ghostty/macos/GhosttyKit.xcframework .
```

Generate the Xcode project and build Termifier:

```bash
xcodegen generate
xcodebuild -project Termifier.xcodeproj -scheme Termifier -configuration Debug build
```

The generated Xcode project is intentionally ignored; `project.yml` is the source of truth.

## License

Termifier is available under the [MIT License](LICENSE). It includes and builds on [Ghostty](https://github.com/ghostty-org/ghostty), also licensed under the MIT License.
