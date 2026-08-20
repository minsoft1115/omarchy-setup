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
lazygit/                   lazygit config (installed to ~/.config/lazygit/)
ccstatusline/              Claude Code status line config (installed to ~/.config/ccstatusline/)
docs/                      per-script documentation and research notes (Korean)
```

---

## Everything in one line (install.sh)

Clones the repo, then asks what to install.

```bash
curl -fsSL https://raw.githubusercontent.com/minsoft1115/omarchy-setup/main/install.sh | bash
```

To read it before running it: fetch it with `-o install.sh`, `less` it, then
`bash install.sh`.

A `gum` checklist appears (space toggles, enter confirms):

```
What should be set up? (space toggles, enter confirms)
> [ ] [installed / latest]   Korean input — right Alt for 한/영 · Omarchy menu opens in Latin
  [✓] [installed / outdated] Bash config — Alt-R history picker · fzf search and kill · delta diffs
  [✓] [not installed]        Lazygit — delta renders the diffs
  [✓] [not installed]        Claude status line — context · session/weekly gauges · reset countdowns
  [✓] [not installed]        sudo-pop — privileged password prompts in a popup · polkit agent + sudo router · built from source
  [✓] [not installed]        Workspaces bar — hold Super to see which apps are where before switching
```

Each row says whether it is installed and whether it is current, and **only what
has work to do starts selected.** One failure does not stop the rest.

| Option | |
|---|---|
| `--all` | everything, without asking |
| `--only korean,sudo-pop` | by name (the first column of `--list`) |
| `--guards` / `--no-guards` | answer the `zz-pkg-guards.sh` question in advance |
| `--list` | print what is available and its current state |
| `--dry-run` | show what would run, run nothing |
| `--dir <path>` | where to clone |
| `--remove` | undo. The same checklist appears with **nothing selected** |
| `--purge` | with `--remove`, deletes the clone at the end |

The clone is kept at `~/.local/share/minsoft1115/omarchy-setup`: the scripts
install *from* it, so editing a source there and re-running is how a change is
applied. Running it again starts with a pull.

See [docs/install.md](docs/install.md) for the details (Korean) — the three
states, what the checkboxes mean, and how removing differs.

---

# What gets installed

Six things. Each is its own script and can be run on its own; what it touches,
how it works and what can be tuned is in the linked document.

| | | |
|---|---|---|
| **Korean input** | right Alt toggles 한/영 · `Control+space` freed for tmux's prefix · the Super+Space menu opens in Latin | `setup-korean.sh` · [docs](docs/setup-korean.md) |
| **Bash config** | Alt-R history picker · fzf search and kill · delta diffs · optional guards that ask before `pacman` or `yay` runs | `install-bash-config.sh` · [docs](docs/bash-config.md) |
| **Lazygit** | diffs rendered through delta · installs lazygit itself if missing | `install-lazygit.sh` · [docs](docs/lazygit.md) |
| **Claude status line** | [ccstatusline](https://github.com/sirmalloc/ccstatusline) under the Claude Code prompt, two lines: model · git branch · context gauge, then session/weekly usage gauges with reset countdowns · installs the npm package and registers it in `~/.claude/settings.json` | `install-ccstatusline.sh` · [docs](docs/ccstatusline.md) |
| **sudo-pop** | the password prompt for privileged actions in a popup instead of the terminal — a polkit authentication agent, with a sudo router in front that sends plain commands through run0. [Its own repository](https://github.com/minsoft1115/sudo-pop) — this step clones and builds it | `install-sudo-pop.sh` · [docs](docs/sudo-pop.md) |
| **Workspaces bar** | hold Super to see which apps are where before switching · the focused workspace keeps its number | `install-workspaces-widget.sh` · [docs](docs/workspaces-widget.md) |

![The workspaces widget and the Super-hold preview](screenshots/workspaces-widget.png)

To run one without the checklist:

```bash
git clone https://github.com/minsoft1115/omarchy-setup.git
cd omarchy-setup
./scripts/install-bash-config.sh install
```

They run from inside the repo, because they install *from* it. Most take
`status` (the default), `install` and `remove`; `--help` on any of them says the
rest. If you have run `install.sh` once, the clone is already at
`~/.local/share/minsoft1115/omarchy-setup`.

---

## Documentation

**The files under `docs/` are written in Korean.** This README says what gets
installed and how to run it; those go into how each piece works, what it
touches, and why it was built that way — linked from the table above.

### Research notes

Not scripts — notes on how Omarchy itself works.

| Document | |
|---|---|
| [docs/quickshell-workspaces.md](docs/quickshell-workspaces.md) | how the workspace indicator in the Omarchy 4.0 bar is drawn — where the data comes from, the display rules, click behaviour, and where it can be customised |
| [docs/workspace-peek-design.md](docs/workspace-peek-design.md) | the design of the Super-hold preview and what was measured — key binding behaviour, the lost release event, and what was wrong about the popup size calculation |
