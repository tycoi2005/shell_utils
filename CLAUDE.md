# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository Overview

This is a collection of standalone macOS shell scripts for DNS management. There is no build system, package manager, or test framework. Scripts are run directly with `bash` or `./script.sh`.

## Scripts

### DNS Management (use in order)

1. **`flush_dns.sh`** — Flushes the macOS DNS cache (`dscacheutil`, `mDNSResponder`) and clears `/etc/resolv.conf` (backing it up to `/etc/resolv.conf.bak`). Requires `sudo`.

2. **`add_dns.sh`** — Reads DNS server IPs from `dns_list.txt`, skips blanks and comments, and appends `nameserver` entries to `/etc/resolv.conf` if not already present. Requires `sudo`.

3. **`dns_list.txt`** — Data source for `add_dns.sh`. Contains 10 public DNS server IPs (Google, Cloudflare, OpenDNS, Quad9, Comodo). Lines starting with `#` are comments.

Typical workflow: run `flush_dns.sh`, then `add_dns.sh`.

### Other

- **`claude_qwen.sh`** (untracked) — Sets `ANTHROPIC_BASE_URL`, `ANTHROPIC_AUTH_TOKEN`, and model env vars to route Claude Code through OpenRouter with Qwen models, then launches `claude`.

## Commands

```bash
# Flush DNS cache and clear resolv.conf
sudo ./flush_dns.sh

# Add DNS servers from dns_list.txt to resolv.conf
sudo ./add_dns.sh

# Launch Claude with Qwen/OpenRouter config
./claude_qwen.sh
```

## Architecture Notes

- All scripts are macOS-specific (use `dscacheutil`, `mDNSResponder`, `/etc/resolv.conf`).
- No dependencies between scripts beyond data files (`dns_list.txt` is read by `add_dns.sh`).
- No test suite or linting.
- The `.env` file contains secrets and is untracked from git.
