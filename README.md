# shell_utils

Collection of standalone shell scripts for macOS DNS management and developer tooling setup.

## Available Tools

### 1) `flush_dns.sh`
- Purpose: Flushes macOS DNS caches and clears `/etc/resolv.conf`.
- What it does:
  - Runs `dscacheutil -flushcache`
  - Restarts `mDNSResponder`
  - Backs up `/etc/resolv.conf` to `/etc/resolv.conf.bak`
  - Clears `/etc/resolv.conf`
- When to use: Before re-applying DNS servers to ensure stale cache/config is removed.
- Requires: `sudo`

Run:

```bash
sudo ./flush_dns.sh
```

### 2) `add_dns.sh`
- Purpose: Adds DNS servers from `dns_list.txt` into `/etc/resolv.conf`.
- What it does:
  - Reads each line from `dns_list.txt`
  - Ignores blank lines and comments (`# ...`)
  - Appends missing `nameserver <ip>` entries
  - Avoids duplicate DNS entries
- When to use: After flushing DNS, to apply a known DNS server list.
- Requires: `sudo`

Run:

```bash
sudo ./add_dns.sh
```

### 3) `dns_list.txt`
- Purpose: Source list of DNS server IP addresses used by `add_dns.sh`.
- What it contains: Public DNS providers (for example Google, Cloudflare, OpenDNS, Quad9, Comodo).
- How to edit: One IP per line; use `#` for comments.

Example format:

```txt
# Cloudflare
1.1.1.1
1.0.0.1
```

### 4) `opencode_docker_install.sh`
- Purpose: Installs/configures OpenCode Docker tooling from this repository.
- When to use: To quickly bootstrap OpenCode Docker setup on a machine.

Install/run from GitHub:

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/tycoi2005/shell_utils/main/opencode_docker_install.sh)
```

### 5) `claude_openrouter_install.sh`
- Purpose: Installs/configures Claude + OpenRouter helper setup from this repository.
- When to use: To quickly configure Claude tooling through OpenRouter.

Install/run from GitHub:

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/tycoi2005/shell_utils/main/claude_openrouter_install.sh)
```

### 6) `opencode_devcontainer_install.sh`
- Purpose: Installs a global `opencode-devcontainer` command for project-scoped Dev Container workflows.
- What it does:
  - Installs launcher to `~/.bin/opencode-devcontainer`
  - Uses existing `.devcontainer/devcontainer.json` if present
  - Auto-generates `.devcontainer/devcontainer.json` when missing
  - Sets `workspaceFolder` without duplicating workspace mounts
  - Recreates container each run to apply image/config changes
  - Syncs host `~/.local/share/opencode/auth.json` into container
  - Syncs host `~/.config/opencode/config.json` into container
  - Verifies `opencode` in-container and reinstalls `opencode-ai` if missing/broken
  - Runs `devcontainer up` then `devcontainer exec ... opencode`
- When to use: When you want an isolated, reproducible OpenCode environment per project.
- Requires: Docker and `@devcontainers/cli` (the launcher checks for it).
- Default base image: `node:22` (Debian-based for better CLI binary compatibility).

Install/run from GitHub:

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/tycoi2005/shell_utils/main/opencode_devcontainer_install.sh)
```

## Typical DNS Workflow

1. Flush DNS cache and clear resolver config:

```bash
sudo ./flush_dns.sh
```

2. Re-apply DNS servers from list:

```bash
sudo ./add_dns.sh
```

## Notes

- These DNS scripts are macOS-specific.
- Scripts modify system DNS files and services, so review before running.

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/tycoi2005/shell_utils/main/opencode_docker_install.sh)
```
