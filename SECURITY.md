# Security

- Never commit `config/local.psd1`, SSH private keys, passwords, access tokens, Materials Project API keys, or licensed POTCAR content.
- The shared Yang/Lan endpoints in `config/servers.psd1` are intentionally tracked for group use; put alternative endpoints and personal overrides in `config/servers.local.psd1`.
- Treat accidental credential publication as compromised: revoke or rotate the credential, then remove it from Git history.
- Report security-sensitive issues privately to the repository maintainers rather than opening a public issue.
