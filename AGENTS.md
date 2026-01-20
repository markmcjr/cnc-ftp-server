# Repository Guidelines

## Project Structure & Module Organization
- The repository currently contains the design and build guide in `Internal_CNC_FTP_Server_Project_Plan.md`.
- When adding implementation artifacts, keep top-level folders purpose-driven (e.g., `config/` for service configs like `vsftpd.conf`, `scripts/` for provisioning scripts, `docs/` for operational runbooks).
- Store machine files or examples outside the repo; the FTP data directory is intended to be `/srv/ftp/cnc-files` on the server, not in source control.

## Build, Test, and Development Commands
- No build or test automation exists yet. If you add scripts, keep them self-contained and document usage in this file.
- Example pattern: `bash scripts/provision.sh` for VM setup and `bash scripts/validate.sh` for hardening checks.

## Coding Style & Naming Conventions
- Prefer clear, descriptive names that map to the architecture in the plan (`ftp`, `sftp`, `firewall`, `hardening`).
- For Markdown documents, keep headings short, use `-` for lists, and separate sections with a single blank line.
- For shell scripts, use `#!/usr/bin/env bash`, `set -euo pipefail`, and lowercase, hyphenated filenames like `configure-ufw.sh`.

## Testing Guidelines
- No testing framework is defined. If you introduce tests or validation scripts, place them in `scripts/` and name them with a `validate-` or `test-` prefix.
- Document expected prerequisites (e.g., Debian 12, root privileges) at the top of each script.

## Commit & Pull Request Guidelines
- No Git history is present in this repository, so no commit conventions are established.
- Use concise, imperative commit messages (e.g., `Add vsftpd config template`) and include context in PR descriptions: scope, risk, and validation steps.
- For security-sensitive changes, call out firewall ports, service users, and any deviations from the project plan.

## Security & Configuration Tips
- Never commit credentials, SSH private keys, or host-specific IPs. Use placeholders like `{{PUBLISHER_IP}}` in templates.
- Align changes with the locked architecture in `Internal_CNC_FTP_Server_Project_Plan.md` and document any required exceptions.
