# CLAUDE-DEPLOY: operating manual for the local Claude Code

## Purpose

Deploy the encrypted Laravel 13 app (this repo, `encrypted/laravel.tar.gz.age`) to Opalstack shared hosting. Flow: decrypt locally with the user's age key, rsync to the server, `composer install` on the server. Use `deploy/opalstack/opalstack-deploy.sh` for all server work. Follow this file literally, in order. Talk to the user in Cantonese (Traditional Chinese, HK written style); this file stays English.

## Hard rules

1. Never read, print, cat, paste or commit the age private key (`AGE_KEY_FILE`) or the contents of any `.env` (local or server). Check presence only: `test -f`, `test -s`, `grep -c '^KEY=' file`, `stat -c %a`. Never echo secrets into chat or logs.
2. No deploy without a passing `preflight` in the current session.
3. Ask the user before EVERY command that changes the server (`first-run`, `deploy`, `cron --install`, `rollback`, `.env` edits, DB changes, creating users), unless they explicitly said to proceed for that step. Read-only commands (`preflight`, `status`, `deploy --dry-run`, `ls`, `php -v`) need no approval.
4. Never `git add app-src/` or any plaintext source or key. Never force-push. Do not run `git commit`/`git push` unless the user asks.
5. Never disable TLS verification (`curl -k`, `StrictHostKeyChecking=no`, `--insecure`).
6. Always `deploy --dry-run` before the first real deploy of a session.
7. On any failure: STOP, show the error (not secrets), and report. Do not improvise destructive fixes (no `rm -rf` on the server, no `migrate:fresh`, no dropping tables, no editing releases by hand).
8. If PHP >= 8.3 is not available on the server: STOP and tell the user (support ticket to Opalstack, or another host).

## Step 0: read and check

- `test -f` and read: `deploy/opalstack/README.md`, `deploy/opalstack/opalstack-deploy.sh` (skim usage only), `deploy/opalstack/env.opalstack.example`, `deploy/opalstack/opalstack.env.example`. If a script file is missing, tell the user the scripts are not on this branch and stop.
- `git status --short` must be clean (ignoring git-ignored files); on `DEPLOY_BRANCH` (default `claude/interactive-demo`). If not clean, ask the user.
- `git check-ignore deploy/opalstack/opalstack.env app-src` should print both.

## Step 1: verify Opalstack facts (do not assume)

Details below were NOT verified when this manual was written. Check them on https://docs.opalstack.com (PHP and Symlink app guides: https://docs.opalstack.com/topic-guides/symlinks/), in the dashboard https://my.opalstack.com (ask the user to read values), and on the server:

- `ssh $OPAL_SSH 'ls /usr/bin/php*; php -v; php -m'` (CLI PHP). Need >= 8.3 and extensions: pdo_mysql, mbstring, intl, gd (with WebP), zip, sodium, curl, dom, fileinfo, openssl (bcmath recommended, not required).
- Which PHP the web app uses (set in the dashboard app) must also be >= 8.3 and match the CLI one.
- Path of a PHP 8.3 CLI binary (`OPAL_PHP`) and of Composer (`command -v composer`, else a `composer.phar` path; `OPAL_COMPOSER`).
- Database host and port (MariaDB), SMTP host/port/encryption for the mailbox.
- App directory: `/home/<user>/apps/<appname>`.

Record verified values in `deploy/opalstack/opalstack.env` (git-ignored) in Step 2; unknowns go to the user.

## Step 2: config

`cp -n deploy/opalstack/opalstack.env.example deploy/opalstack/opalstack.env`, then set (ask the user for values; never invent):

| Var | Meaning |
|---|---|
| `OPAL_SSH` | `user@host` |
| `OPAL_APP_DIR` | e.g. `/home/<user>/apps/housing_agent` |
| `OPAL_PHP` | server PHP 8.3 CLI path |
| `OPAL_COMPOSER` | server composer command |
| `OPAL_URL` | `https://domain`, no trailing slash |
| `AGE_KEY_FILE` | private key path, outside the repo, `chmod 600` (check with `stat -c %a`) |
| `DEPLOY_BRANCH` | default `claude/interactive-demo` |
| `KEEP_RELEASES` | default 5 |
| `OPAL_SSH_OPTS` | optional extra ssh options |

`OPAL_CONFIG=/path` overrides the config path. `SKIP_GIT_UPDATE=1` skips the git fetch. Pre-migrate DB backup can be bypassed only with `SKIP_BACKUP` / `ALLOW_NO_BACKUP`; never set these unless the user explicitly asks.

## Step 3: preflight

Run `deploy/opalstack/opalstack-deploy.sh preflight`. Fix each failing check, one at a time:

| Failing check | Fix |
|---|---|
| age/rsync/ssh/git missing | tell the user to install it |
| key file missing or perms not 600 | ask the user for the path; `chmod 600` it; never read it |
| SSH fails | user must add the SSH public key in the dashboard; check `OPAL_SSH` |
| PHP < 8.3 or extension missing | Hard rule 8 / check `OPAL_PHP`, `php -m` |
| composer missing | verify path; else a local `composer.phar` in the app dir (ask) |
| working tree dirty / wrong branch | ask the user |

Repeat until it passes. Report the result before moving on.

## Step 4: first-run and server .env

Ask approval, then run `deploy/opalstack/opalstack-deploy.sh first-run`. It creates `$OPAL_APP_DIR/{releases,shared/storage}` and uploads `env.opalstack.example` as `shared/.env` if missing. Do not print the file.

The user edits it ON THE SERVER: `ssh -t $OPAL_SSH nano $OPAL_APP_DIR/shared/.env`. Walk through every key; for each say where the value comes from. Verify later only by `ssh $OPAL_SSH "grep -c '^KEY=.' $OPAL_APP_DIR/shared/.env"`.

| Key | Source |
|---|---|
| `APP_KEY` | generate: `php artisan key:generate --show` from a decrypted local copy (`scripts/decrypt-app.sh "$AGE_KEY_FILE" /tmp/xx`, then delete it), or on the server inside a release dir after first deploy. The user pastes it; do not log it. |
| `APP_URL` | the final `https://domain`; must equal the real domain (host check returns 400 otherwise) |
| `APP_ENV=production`, `APP_DEBUG=false` | fixed |
| `DB_CONNECTION` | `mariadb` (`mysql` also works) |
| `DB_HOST`, `DB_PORT` | dashboard / docs. VERIFY, do not assume `127.0.0.1` |
| `DB_DATABASE`, `DB_USERNAME`, `DB_PASSWORD` | dashboard database + user |
| `MAIL_HOST`, `MAIL_PORT`, `MAIL_USERNAME`, `MAIL_PASSWORD`, `MAIL_FROM_ADDRESS` | Opalstack mailbox. VERIFY host/port; example file has a placeholder `smtp.example.com` |
| `MAIL_ADMIN_ADDRESS` | user's address for backup alerts |
| `SESSION_DRIVER`, `CACHE_STORE`, `QUEUE_CONNECTION` | `database` |
| `SESSION_SECURE_COOKIE`, `FORCE_HTTPS` | `true` |
| `TRUSTED_PROXIES` | `127.0.0.1` first; see Step 6 |
| `TURNSTILE_SITE_KEY` / `TURNSTILE_SECRET_KEY` | optional, Cloudflare Turnstile; empty disables |
| GA4 id | optional; set in admin Settings, not `.env` |
| `ANTHROPIC_API_KEY` | optional (AI translation); user's own key |
| `BACKUP_DISK` | `backups` (local) minimum; recommend `backups,s3` with `AWS_*` set for off-server copies |
| `BACKUP_ARCHIVE_PASSWORD` | optional; user stores it in a password manager |
| `HEALTH_REQUIRE_SCHEDULER` | `true` is fine, but `/health` shows failing until cron is installed (Step 7); set `false` temporarily if needed |
| `SECURITY_CSP_REPORT_ONLY` | `true` for the first week |

## Step 5: first deploy

1. `deploy/opalstack/opalstack-deploy.sh deploy --dry-run` and report the plan.
2. Ask approval, then `deploy/opalstack/opalstack-deploy.sh deploy`. It decrypts locally, rsyncs a new `releases/<ts>`, links shared `.env` and `storage`, then runs remote-release.sh: `composer install --no-dev`, `storage:link`, `backup:run --only-db` before migrate, `migrate --force`, `optimize`, atomic `current` switch, `queue:restart`, prune old releases.
3. NO demo seeding in production: never run `migrate --seed` or `db:seed`.
4. Create the first admin interactively: first confirm the command exists with `ssh $OPAL_SSH "cd $OPAL_APP_DIR/current && $OPAL_PHP artisan list | grep filament-user"`; then ask the user to run (or approve running) `ssh -t $OPAL_SSH "cd $OPAL_APP_DIR/current && $OPAL_PHP artisan make:filament-user"`. The password is typed by the user at the prompt only. Remind them to enable MFA.

## Step 6: web routing and HTTPS

- In the dashboard the Symlink app must point to `$OPAL_APP_DIR/current/public` (the user does this; give the exact path). Site routes `/` to that app, Let's Encrypt on, HTTPS redirect on.
- Check: `curl -sSI $OPAL_URL/`, then check HTTPS-generated URLs (links in HTML start with `https://`, no `http://`), and that login at `/admin` works without a redirect loop. The app must see `request()->isSecure()` true.
- Set `TRUSTED_PROXIES` ONLY if needed (e.g. the app sees http behind the proxy): ask the user to check with Opalstack for the proxy address; never use `*`. After editing `.env`: `ssh $OPAL_SSH "cd $OPAL_APP_DIR/current && $OPAL_PHP artisan optimize:clear && $OPAL_PHP artisan optimize"`.

## Step 7: cron

Ask approval, run `deploy/opalstack/opalstack-deploy.sh cron` (shows the entries), then `... cron --install`. It installs the user crontab: `schedule:run` and `queue:work --stop-when-empty` every minute. Verify with `ssh $OPAL_SSH crontab -l` and, after 2 minutes, `/health` returns 200.

## Step 8: verification checklist

Run and report each (replace `$OPAL_URL`):

- [ ] `curl -sSI $OPAL_URL/` returns 200 (or a 30x to `/zh-hk` ending in 200).
- [ ] Security headers present: CSP, HSTS, `X-Frame-Options`, `X-Content-Type-Options`, `Referrer-Policy`, `Permissions-Policy`; NO `X-Powered-By`.
- [ ] `curl -s $OPAL_URL/health` returns `{"status":"ok"}`.
- [ ] Admin login at `/admin` works.
- [ ] Submit a test enquiry on a listing; a lead appears in admin.
- [ ] An email arrives (e.g. password reset or notification) after at most ~1 minute.
- [ ] `curl -sI -H 'Host: evil.example' $OPAL_URL/` returns 400 (via connect-to or resolving; if it can't be tested remotely, say so).
- [ ] `curl -sI $OPAL_URL/storage/logs/laravel.log` and `$OPAL_URL/.env` return 404.
- [ ] `status` subcommand shows the current release.

Then remind the user of the pre-launch list in `deploy/opalstack/README.md` (demo accounts, MFA, restore drill, ZAP, SSL Labs).

## Step 9: later deploys

`git pull` (or `SKIP_GIT_UPDATE=1`), `preflight`, `deploy --dry-run`, ask approval, `deploy`, repeat Step 8 quickly. Needing new `.env` keys: tell the user which, they edit on the server.

## Rollback

Ask approval, then `deploy/opalstack/opalstack-deploy.sh rollback` (points `current` at the previous release, `queue:restart`). Then check `/health`. DB migrations are not undone; if a migration was the problem, stop and report; the pre-migrate backup is in the backups disk (`php artisan backup:list`). Do not restore without explicit user approval.

## Troubleshooting

| Symptom | Check / fix |
|---|---|
| 500 | `ssh $OPAL_SSH "tail -n 80 $OPAL_APP_DIR/shared/storage/logs/laravel-*.log"` (log file names are daily); read, do not paste secrets |
| 500 after deploy, permission errors | `shared/storage` and `bootstrap/cache` must be writable by the shell user; check `ls -ld`; fix only with `chmod -R u+rwX` on those two |
| Works in CLI, fails in web (or reverse) | CLI PHP version vs the PHP of the Symlink app differ; compare `php -v` and the dashboard app PHP; extensions via `php -m` |
| `composer install` killed / memory | `COMPOSER_MEMORY_LIMIT=-1` in the command; retry once; otherwise report |
| Symlink app 403/404 | the symlink path must be exactly `$OPAL_APP_DIR/current/public`; `ssh $OPAL_SSH "ls -l $OPAL_APP_DIR/current; ls $OPAL_APP_DIR/current/public"`; site route URI `/` |
| Redirect loop / mixed content | `TRUSTED_PROXIES` (Step 6), `FORCE_HTTPS=true`, `APP_URL` is https, `SESSION_SECURE_COOKIE=true`; then `optimize:clear` |
| 400 on the real domain | `APP_URL` host differs from the requested host |
| Emails / queue idle | cron missing or failing: `crontab -l`, run `cron`, check `queue:work` output; `/health` scheduler status |
| `/health` 503 | read the JSON checks; scheduler (cron), queue size, disk free, DB |

## Finish

End with a short Cantonese summary to the user: what was done, URL, which checks passed or failed, what they still must do (demo accounts, MFA, backup restore drill, ZAP, SSL Labs, `SECURITY_CSP_REPORT_ONLY` after one week).
