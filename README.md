# omarchy-setup

**English** · [한국어](README.ko.md)

Setup scripts to run on a fresh [Omarchy](https://omarchy.org) (Arch +
Hyprland) machine.

Every script **runs on its own** and is **idempotent** — running it again is
safe, and anything already done is reported as skipped. Existing config files
are backed up as `*.bak.<timestamp>` before they are touched.

```
install.sh                 entry point — clone + pick what to install
scripts/                   the individual installers
minsoft1115.workspaces/    Quickshell plugin source (bar widget + shell service)
hypr/                      Hyprland Lua snippets (installed to ~/.config/minsoft1115/hypr/)
bash/                      alias and function sources (installed to ~/.config/minsoft1115/bash/)
docs/                      per-script documentation and research notes (Korean)
```

---

## Everything in one line (install.sh)

Clones the repo and then asks what to install.

```bash
curl -fsSL https://raw.githubusercontent.com/minsoft1115/omarchy-setup/main/install.sh | bash
```

To read it before running it, do it in two steps:

```bash
curl -fsSL https://raw.githubusercontent.com/minsoft1115/omarchy-setup/main/install.sh -o install.sh
less install.sh
bash install.sh
```

It clones (or pulls) into `~/.local/share/minsoft1115/omarchy-setup`, then
**reattaches the terminal** and re-executes itself from that clone — a script
arriving through a pipe has stdin that is not a keyboard, so the checklist would
read EOF and select nothing.

Then a `gum` checklist appears (space toggles, enter confirms):

```
What should be set up? (space toggles, enter confirms)
> [ ] [installed / latest]   Korean input — right Alt for 한/영 · Omarchy menu opens in Latin
  [✓] [installed / outdated] Bash config — Alt-R history picker · fzf search and kill · delta diffs
  [✓] [not installed]        Workspaces bar — hold Super to see which apps are where before switching
```

- There are **three states**. The first half says whether it is installed, the
  second whether it is current. The answer comes from a **byte comparison**
  between the repo files and the installed copies — a `git pull` that moved the
  repo ahead, or a source file edited by hand, both show up as `outdated`

  | State | Meaning | Selected by default |
  |---|---|---|
  | `not installed` | never installed | ✓ |
  | `installed / outdated` | installed, but differs from the repo | ✓ |
  | `installed / latest` | installed and identical to the repo | — |

  **Only what has work to do is selected.** There is no reason to re-run
  something already current
- Every checkbox means the same thing — **"run this now"**. The optional
  `zz-pkg-guards.sh` is not on the list: the bash step asks about it while it
  runs, and only when the file is not there yet. If it is already in use it is
  updated without asking (`--guards` / `--no-guards` answer in advance)
- The **order is fixed** regardless of what you picked
  (`korean` → `bash-config` → `workspaces`). The workspaces widget restarts the
  shell, so it goes last
- One failure does not stop the rest; a summary is printed at the end

**The clone is not deleted.** All three scripts install *from the repo* (alias
sources, widget sources, Hyprland snippets), and editing a source and re-running
is how a change is applied — deleting the clone would remove that path. Running
it again starts with a pull.

| Option | |
|---|---|
| `--all` | everything, without asking |
| `--only korean,bash-config` | by name (the first column of `--list`) |
| `--guards` / `--no-guards` | answer the `zz-pkg-guards.sh` question in advance |
| `--list` | print what is available and its current state |
| `--dry-run` | show what would run, run nothing |
| `--dir <path>` | where to clone |
| `--remove` | undo. The same checklist appears with **nothing selected**, and steps run in reverse order |
| `--purge` | with `--remove`, deletes the clone at the end |

A wrong pick when installing is fixed by running again; a wrong pick when
removing is not, which is why `--remove` starts with nothing selected.

See [docs/install.md](docs/install.md) for the details (Korean).

---

# The individual scripts

You can run just one, without `install.sh`. They all run from inside the repo,
because they read their sources from it (`bash/`, `hypr/`,
`minsoft1115.workspaces/`).

```bash
git clone https://github.com/minsoft1115/omarchy-setup.git
cd omarchy-setup
```

If you have run `install.sh` once, the clone is already at
`~/.local/share/minsoft1115/omarchy-setup`.

---

## setup-korean.sh

Installs and configures fcitx5 + hangul for Korean input: binds right Alt as the
Hangul/Latin toggle, removes the `Control+space` trigger that collides with
tmux's prefix, and makes the Super+Space menu always open in Latin mode.

```bash
./scripts/setup-korean.sh
```

To re-apply only the key settings on a machine that is already set up (no
packages, no sudo):

```bash
./scripts/setup-korean.sh --light
```

To undo — only what this script created; the fcitx5 config is left alone:

```bash
./scripts/setup-korean.sh remove
```

It **does not edit Hyprland's own files.** Lua snippets go into
`~/.config/minsoft1115/hypr/`, and only a `require` line wrapped in markers is
added to `hyprland.lua` (the same approach as
`install-workspaces-widget.sh`).

This script's console output is in Korean, as is
[docs/setup-korean.md](docs/setup-korean.md) — it is the one part of this repo
written for a Korean-speaking user.

---

## install-bash-config.sh

Copies the alias and function files in `bash/` to
`~/.config/minsoft1115/bash/` and makes `~/.bashrc` load them. The loader is a
**loop over the folder** rather than one source line per file, so adding a file
to `bash/` later needs an `install` and nothing else — `~/.bashrc` never has to
change again.

### What you get

| File | |
|---|---|
| `bash/aliases.sh` | `cat` → `bat -p` (highlighting), `grep` → `rg` |
| `bash/fhistory.sh` | `fhistory` — **Alt-R** picks a line from history with fzf and **puts it on the prompt without running it** (you press Enter yourself). The list keeps `history` order, and typing a query **moves the cursor to the best match instead of filtering or reordering** the lines. Ctrl-Y copies the command. Ctrl-R is left to fzf's own widget |
| `bash/fkill.sh` | `fkill` — pick one of your processes with fzf and kill it. Takes a signal: `fkill -9` |
| `bash/fsearch.sh` | `fsearch` — browse a content search (rg) through fzf. `fsearch TODO` / `fsearch md TODO` (by extension), Enter opens `$EDITOR`, Ctrl-Y copies the path |
| `bash/gdiff.sh` | `gdiff` — pipe `git diff` through `delta`. Arguments pass straight through |
| `bash/zz-pkg-guards.sh` | **optional** — before `pacman` or `yay` runs, offers the omarchy command that replaces it and **asks whether to run it at all**. Read-only operations (`-Q`, `-Ss`, `-Si` …) are never asked about |

`install` **asks before installing** `zz-pkg-guards.sh` (`gum confirm`), since
Omarchy ships guards of its own; if it is already there it is updated without
asking. The files load *after* Omarchy's own bash rc, so on a name collision
these win, and they load in **filename order**. The tools they need
(`git-delta`, `bat`, `ripgrep`, `fzf`, `gum`) are installed first, through
`omarchy pkg`.

The guards used to answer `pacman` and `yay` with a reminder and **refuse to run
them**. There is always the one time you do mean pacman, and a wall makes you
retype the whole line with `command pacman` in front of it — so they ask
instead, with the recommended command one keypress away.

```
$ sudo pacman -S ripgrep
Omarchy manages packages on this machine.
> omarchy pkg add ripgrep
  run as typed: sudo pacman -S ripgrep
  cancel
```

Catching `sudo pacman` needs `sudo` to be a function too, and **aliases are
expanded before functions are looked up**. So this file is named to load
**last** (the `zz-` prefix), and it takes over whatever `alias sudo=...` is in
place by then (sudo-pop installs one) and calls it — neither tool has to know
the other exists. See
[docs/bash-config.md](docs/bash-config.md#선택-파일) (Korean).

```bash
./scripts/install-bash-config.sh install
```

A process cannot change the shell that started it. New terminals just get them;
to load them into the shell you are sitting in, **source the script instead of
running it**:

```bash
source ./scripts/install-bash-config.sh install
```

To undo:

```bash
./scripts/install-bash-config.sh remove
```

The install folder `~/.config/minsoft1115/bash/` is **not ours alone** —
sudo-pop drops its own snippet there. So the files this script installs are
written down in `.installed`, and **only files on that list** are ever deleted.
Neither the cleanup during `install` nor `remove` touches anyone else's file.

See [docs/bash-config.md](docs/bash-config.md) for the details (Korean).

---

## install-workspaces-widget.sh

The point is **seeing what is on a workspace before deciding to switch to it.**
Hold Super and the workspaces that hold windows appear, each with its window
list, which replaces going back and forth by number from memory. As a bonus the
focused workspace keeps **its number** instead of being covered by a glyph.

![The workspaces widget and the Super-hold preview](screenshots/workspaces-widget.png)

In the bar, 1 is focused (inverted number), 2 has windows, and 3–5 are empty and
dimmed. Holding Super brings up the popup below it, listing each workspace's
windows.

It installs the Quickshell plugin and the Hyprland key binding together.

```bash
./scripts/install-workspaces-widget.sh install
```

To undo:

```bash
./scripts/install-workspaces-widget.sh revert
```

See [docs/workspaces-widget.md](docs/workspaces-widget.md) for the details
(Korean).

---

## Documentation

**The files under `docs/` are written in Korean.** This README covers what the
scripts do and how to run them; those go into how each one works, what it
touches, and why it was built that way.

| Document | |
|---|---|
| [docs/install.md](docs/install.md) | `install.sh` — bootstrap, the checklist, undoing |
| [docs/setup-korean.md](docs/setup-korean.md) | `setup-korean.sh` — step by step, files touched, troubleshooting |
| [docs/bash-config.md](docs/bash-config.md) | `install-bash-config.sh` — the loader, the optional file, the load-order trap |
| [docs/workspaces-widget.md](docs/workspaces-widget.md) | `install-workspaces-widget.sh` — what changes, the layout, tuning |

### Research notes

Not scripts — notes on how Omarchy itself works.

| Document | |
|---|---|
| [docs/quickshell-workspaces.md](docs/quickshell-workspaces.md) | how the workspace indicator in the Omarchy 4.0 bar is drawn — where the data comes from, the display rules, click behaviour, and where it can be customised |
| [docs/workspace-peek-design.md](docs/workspace-peek-design.md) | the design of the Super-hold preview and what was measured — key binding behaviour, the lost release event, and what was wrong about the popup size calculation |
