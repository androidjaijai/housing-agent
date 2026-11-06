---
description: Deploy the encrypted Laravel app to Opalstack shared hosting (preflight, first-run, deploy, rollback, status)
argument-hint: [preflight|first-run|deploy|rollback|status]
---

Read `deploy/opalstack/CLAUDE-DEPLOY.md` in full and follow it literally for this step: $ARGUMENTS

If no argument was given, run the preflight step, report the result, and say which step comes next.

Hard rules (details are in the manual):
- Never read, print, paste or commit the age private key or any `.env` contents; check presence with `test` or `grep -c` only.
- Ask me before every command that changes the server, unless I said to proceed. Dry-run before a real deploy; no deploy without a passing preflight.
- Never `git add app-src/`, never force-push, never disable TLS verification. On any failure, stop and report; do not improvise destructive fixes.

Reply to me in Cantonese (Traditional Chinese, Hong Kong written style).
