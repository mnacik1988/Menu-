# Private configuration

- Files named `Пароли и АПИ*` contain the user's private credentials. Keep them local and untracked. Do not open them merely to inspect the project.
- Never print their contents or credential values in tool output, chat, logs, patches, commit messages, screenshots, PR descriptions, or documentation.
- Read a required value locally only when the user authorizes configuration of the corresponding service. Use it only with that service. Do not pass private values in command-line arguments or URLs.
- Exclude these documents and `.env` files from searches, archive creation, uploads, previews, and source synchronization. Package source from an explicit tracked-file list rather than copying the entire project directory.
- `.env.example` must contain placeholders only. Store actual settings in ignored environment files or the appropriate service's secret storage.
- Before committing, run `npm run check:secrets`. Install the local pre-commit hook with `npm run protect:secrets` when no custom hooks path is already configured. Preserve existing custom hooks.
- If a private document is already tracked or appears in Git history, stop publication of those changes and report the affected file names without showing values. Do not rewrite shared history or rotate credentials without the user's authorization.
