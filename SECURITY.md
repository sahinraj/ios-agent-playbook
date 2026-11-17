# Security Policy

## Reporting a vulnerability

Please report vulnerabilities in the installer or the helper scripts privately through GitHub's **Security > Report a vulnerability** feature instead of opening a public issue.

Include the affected command, expected behavior, actual behavior, and a minimal reproduction. Do not include real credentials or proprietary project files.

## Scope

Security reports should concern this repository's installer, its helper scripts, or files they create. The helper scripts are read-only: `project-facts.sh` reads project files and `diff-audit.sh` reads the git diff. Neither writes into your project, builds it, or uses the network. The project does not collect telemetry, run a service, or require credentials.
