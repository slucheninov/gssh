# gssh

Zsh helper for SSH into GCP VMs via IAP tunnel. It wraps `gcloud compute ssh`, adds account-aware tab completion, keeps a local VM cache, and can infer project/zone from cached instance metadata when there is a single match.

## Features

- **Tab-completion** for accounts, VM names, projects, and zones
- **Interactive selectors** for account, project, and zone (fzf or built-in `select`)
- **Account-aware VM cache** with project/zone metadata and configurable TTL (default 24h)
- **Literal exclude prefixes** to filter out unwanted VMs (e.g. `gke-` nodes)
- **Multiple GCP accounts** with interactive switching (`--account` / `-a`)
- **Extra SSH args** via `--` (port forwarding, tunnels, etc.)
- **Dry-run and copy modes** for inspecting or copying the generated `gcloud` command
- **Atomic self-upgrade**: downloads all files before replacing the installed copy
- Works on **macOS** and **Linux**

## Demo

```
$ gssh -a user@company.com mysql-<TAB>
mysql-primary-01   mysql-replica-01   mysql-replica-02

$ gssh mysql-primary-01
Select project: production-12345678
Select zone: us-central1-a
gssh: connecting to mysql-primary-01 | project: production-12345678 | zone: us-central1-a

$ gssh --dry-run mysql-primary-01 production-12345678 us-central1-a -- -L 3306:localhost:3306
gcloud compute ssh mysql-primary-01 --tunnel-through-iap --project=production-12345678 --zone=us-central1-a -- -L 3306:localhost:3306
```

## Prerequisites

- [Google Cloud SDK](https://cloud.google.com/sdk/docs/install) (`gcloud` CLI)
- Zsh
- [fzf](https://github.com/junegunn/fzf) (optional, falls back to built-in `select`)

## Installation

### Option 1: one-liner (curl)

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/slucheninov/gssh/master/install.sh)
```

or with wget:

```bash
bash <(wget -qO- https://raw.githubusercontent.com/slucheninov/gssh/master/install.sh)
```

### Option 2: git clone

```bash
git clone https://github.com/slucheninov/gssh.git
cd gssh
cp .env.example .env   # edit with your projects/zones/accounts
chmod +x install.sh
./install.sh
exec zsh
```

### Option 3: manual

```bash
git clone https://github.com/slucheninov/gssh.git ~/.gssh
```

Add to `~/.zshrc` **before** `compinit`:

```zsh
# gssh
[[ -f "${HOME}/.gssh/gssh.zsh" ]] && source "${HOME}/.gssh/gssh.zsh"
[[ -f "${HOME}/.gssh/.env" ]] && source "${HOME}/.gssh/.env"
fpath=("${HOME}/.gssh" $fpath)
```

Then reload: `exec zsh`

### Option 4: zinit / sheldon / antidote

```zsh
# zinit
zinit light slucheninov/gssh

# sheldon (plugins.toml)
[plugins.gssh]
github = "slucheninov/gssh"
```

## Configuration

Create `.env` from the example (or export in `.zshrc`):

```bash
cp .env.example .env
```

| Variable | Default | Description |
|---|---|---|
| `GSSH_PROJECTS` | _(current gcloud project)_ | Space-separated GCP project IDs. If empty, `gcloud config get-value project` is used |
| `GSSH_ZONES` | `us-central1-a us-central1-b us-central1-c` | Space-separated zones |
| `GSSH_CACHE_FILE` | `~/.cache/gssh/vms` | Path to VM name cache |
| `GSSH_CACHE_TTL` | `86400` (24h) | Cache lifetime in seconds |
| `GSSH_EXCLUDE_PREFIXES` | _(empty)_ | Space-separated literal prefixes to exclude from cache (e.g. `gke-`) |
| `GSSH_ACCOUNTS` | _(empty)_ | Space-separated GCP account emails for account switching |

## Usage

```bash
# SSH into a VM (interactive project/zone selection)
gssh <vm-name>

# Specify project and zone directly
gssh <vm-name> <project-id> <zone>

# Use a specific GCP account
gssh -a user@company.com <vm-name>
gssh --account user@company.com <vm-name> <project-id> <zone>

# Port forwarding and extra SSH args
gssh <vm-name> -- -L 3306:localhost:3306
gssh <vm-name> <project-id> <zone> -- -L 8080:localhost:80 -N

# List cached VM names
gssh --list        # or: gssh -l

# Force-refresh the VM cache
gssh --refresh     # or: gssh -r

# Show command without executing it
gssh --dry-run <vm-name> <project-id> <zone>
gssh -d <vm-name> <project-id> <zone>

# Copy command to clipboard
gssh --copy <vm-name> <project-id> <zone>
gssh -c <vm-name> <project-id> <zone>

# Upgrade installed gssh files
gssh --upgrade     # or: gssh -u

# Version
gssh --version     # or: gssh -V

# Help
gssh --help        # or: gssh -h
```

`--dry-run` and `--copy` shell-quote arguments with spaces so commands such as `-o "ProxyCommand=ssh host"` remain pasteable.

## Cache

The cache is refreshed automatically when it is missing, expired, or in the older name-only format. It stores VM name, project, and zone internally so `gssh` can narrow project/zone completion and skip selectors when a VM has a single cached match.

When `GSSH_ACCOUNTS` or `--account` is used, each account gets its own cache file derived from `GSSH_CACHE_FILE`, for example:

```text
~/.cache/gssh/user_company_com_vms
```

Refreshes are atomic: `gssh` writes a temporary cache first and keeps the existing cache if `gcloud compute instances list` fails.

## Tab completion

VM names are cached locally and refreshed automatically when the cache expires. To force a refresh:

```bash
gssh --refresh
```

Completion works for:

- `--account` / `-a` values from `GSSH_ACCOUNTS`
- VM names from the selected account cache
- Projects from `GSSH_PROJECTS` or cached VM metadata
- Zones from `GSSH_ZONES` or cached VM metadata

```
gssh -a <TAB>
gssh mysql-<TAB>
gssh mysql-primary-01 <TAB>
gssh mysql-primary-01 production-12345678 <TAB>
```

For completion to work, keep the `fpath=("${HOME}/.gssh" $fpath)` line before `compinit` in your `~/.zshrc`.

## Upgrade

Upgrade the installed `gssh.zsh` and `_gssh` files with:

```bash
gssh --upgrade
```

The upgrade downloads all files first and replaces the installed copy only after every download succeeds. Your `~/.gssh/.env` file is not changed.

## Development

```bash
make lint   # shellcheck, shfmt, zsh syntax checks
make test   # Bats tests
make check  # lint + test
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
