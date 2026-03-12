# gssh

Zsh helper for SSH into GCP VMs via IAP tunnel. Interactive project/zone selection with [fzf](https://github.com/junegunn/fzf) support and tab-completion for VM names.

## Features

- **Tab-completion** for VM names from `gcloud compute instances list`
- **Interactive selectors** for project and zone (fzf or built-in `select`)
- **VM name cache** with configurable TTL (default 24h)
- Works on **macOS** and **Linux**

## Demo

```
$ gssh mysql-<TAB>
mysql-primary-01   mysql-replica-01   mysql-replica-02

$ gssh mysql-primary-01
Select project: production-12345678
Select zone: us-central1-a
gssh: connecting to mysql-primary-01 | project: production-12345678 | zone: us-central1-a
```

## Prerequisites

- [Google Cloud SDK](https://cloud.google.com/sdk/docs/install) (`gcloud` CLI)
- Zsh
- [fzf](https://github.com/junegunn/fzf) (optional, falls back to built-in `select`)

## Installation

### Option 1: install script

```bash
git clone https://github.com/USER/gssh.git
cd gssh
cp .env.example .env   # edit with your projects/zones
chmod +x install.sh
./install.sh
exec zsh
```

### Option 2: manual

```bash
git clone https://github.com/USER/gssh.git ~/.gssh
```

Add to `~/.zshrc` **before** `compinit`:

```zsh
# gssh
[[ -f "${HOME}/.gssh/gssh.zsh" ]] && source "${HOME}/.gssh/gssh.zsh"
[[ -f "${HOME}/.gssh/.env" ]] && source "${HOME}/.gssh/.env"
fpath=("${HOME}/.gssh" $fpath)
```

Then reload: `exec zsh`

### Option 3: zinit / sheldon / antidote

```zsh
# zinit
zinit light USER/gssh

# sheldon (plugins.toml)
[plugins.gssh]
github = "USER/gssh"
```

## Configuration

Create `.env` from the example (or export in `.zshrc`):

```bash
cp .env.example .env
```

| Variable | Default | Description |
|---|---|---|
| `GSSH_PROJECTS` | _(required)_ | Space-separated GCP project IDs |
| `GSSH_ZONES` | `us-central1-a us-central1-b us-central1-c` | Space-separated zones |
| `GSSH_CACHE_FILE` | `~/.cache/gssh/vms` | Path to VM name cache |
| `GSSH_CACHE_TTL` | `86400` (24h) | Cache lifetime in seconds |

## Usage

```bash
# SSH into a VM (interactive project/zone selection)
gssh <vm-name>

# Specify project and zone directly
gssh <vm-name> <project-id> <zone>

# Force-refresh the VM cache
gssh --refresh

# Help
gssh --help
```

## Tab completion

VM names are cached locally and refreshed automatically when the cache expires. To force a refresh:

```bash
gssh --refresh
```

Completion works for the first argument (VM name). Type a prefix and press `<TAB>`:

```
gssh mysql-<TAB>
gssh rabbit<TAB>
```

## Uninstall

```bash
chmod +x uninstall.sh
./uninstall.sh
# Remove the gssh block from ~/.zshrc
exec zsh
```

## License

MIT
