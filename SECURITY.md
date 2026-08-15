# Security

- Never commit `config/local.psd1`, SSH private keys, passwords, access tokens, Materials Project API keys, or licensed POTCAR content.
- Put private server addresses and site-specific overrides in `config/servers.local.psd1`.
- Treat accidental credential publication as compromised: revoke or rotate the credential, then remove it from Git history.
- Report security-sensitive issues privately to the repository maintainers rather than opening a public issue.
