# Contributing

Contributions that make the process clearer, the checks more accurate, or the installer safer are welcome.

## What belongs where

- `skills/ios-playbook/SKILL.md` holds the loop, the modes, the gates and the hard rules. Keep it under 200 lines. Explain why a rule exists, because an agent that understands the reason applies it better than one following an order.
- Detail goes in the matching file under `skills/ios-playbook/references/`, with a row in the reference table of `SKILL.md`.
- This is a process skill. Swift, SwiftUI and SwiftData knowledge belongs in a domain skill such as [iOS Swift Master](https://github.com/sahinraj/ios-swift-master-copilot).
- Helper scripts must stay read-only and must run with the bash 3.2 and BSD tools that ship with macOS. No GNU-only flags.

## Before opening a pull request

Run the checks:

```bash
./install.sh verify
bash tests/scripts_test.sh
bash tests/install_test.sh
bash tests/bootstrap_test.sh
bash tests/evals_test.sh
shellcheck -S warning install.sh docs/install.sh evals/score.sh tests/*.sh skills/ios-playbook/scripts/*.sh
```

CI runs the same checks on macOS and Linux.

If you change a command in `references/verification-gates.md`, say which Xcode version you ran it on. If you change the behavior of the skill, add or update a task under `evals/tasks/` that would catch a regression.

Do not include proprietary source code, credentials, personal data, or copyrighted material copied from documentation.
