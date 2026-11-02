# Housing Agent: Hong Kong rental agent website (encrypted)

This repository contains two encrypted projects:

| Encrypted file | What it is | Decrypt with |
|---|---|---|
| `encrypted/laravel.tar.gz.age` | **The real application:** Laravel 13 + Filament 5 + Livewire 4, 繁 / 简 / EN | `scripts/decrypt-app.sh` |
| `encrypted/site.tar.gz.age` | The earlier static HTML click-through demo | `scripts/decrypt.sh` |

Both are encrypted with [age](https://age-encryption.org) to the public key in `keys/recipient.txt`. Only the matching **private key** can decrypt them, and that key is not in this repository.

## 1. Decrypt and run the Laravel app

Requirements: PHP 8.3+ with `pdo_sqlite`, `mbstring`, `intl`, `gd` and `zip`; Composer 2; `age`.

```bash
git clone -b claude/interactive-demo https://github.com/androidjaijai/housing-agent.git
cd housing-agent
scripts/decrypt-app.sh ~/path/to/housing-agent-private-key.txt   # → app-src/
cd app-src
composer install
cp -n .env.example .env && php artisan key:generate
touch database/database.sqlite && php artisan migrate --seed
php artisan storage:link
php artisan serve                   # http://127.0.0.1:8000
```

- **Public site:** http://127.0.0.1:8000. It redirects to `/zh-hk`, `/zh-cn` or `/en` based on your browser's language.
- **Admin panel:** http://127.0.0.1:8000/admin. Demo login `admin@example.com` / `password`. **Change it before going live.**
- **Tests:** `php artisan test` (87 Pest tests).
- **MySQL:** set the `DB_*` values in `.env`, then run `php artisan migrate --seed`.
- **Placeholders to replace:** agency name, licence numbers, office address and WhatsApp number. Edit them in the admin under **Settings**, or in `database/seeders/data/demo.json` before seeding.

There is no npm or Vite step. The public pages use plain CSS in `public/css/`, and Filament and Livewire ship their own compiled assets.

## 2. Work on the code: encryption happens on every commit

Install the git hook once after cloning:

```bash
scripts/install-hooks.sh
```

From then on, every `git commit`:

1. Re-encrypts `app-src/` into `encrypted/laravel.tar.gz.age` (and `src/` into `encrypted/site.tar.gz.age` if present), then stages the result.
2. Refuses the commit if any plaintext source (`app-src/`, `src/`, `site/`) or any age private key is staged.

`app-src/`, `src/` and `site/` are git-ignored, so plaintext never reaches GitHub. The archives exclude `vendor/`, `node_modules/`, `.env`, SQLite databases, logs and caches. Run `composer install` after decrypting.

For long sessions, `scripts/autosave.sh [seconds] [times]` encrypts, commits and pushes on a timer.

**To give a colleague access:** add their age public key (`age1…`) as a new line in `keys/recipient.txt`, then commit; the hook re-encrypts. Run `FORCE=1 scripts/encrypt-app.sh` to re-encrypt without code changes.

## Versions and branches

Each finished phase is published as a frozen branch `claude/release/vX.Y.Z` (the cloud session can't push git tags).
To create real tags from them, run `scripts/make-tags.sh` on your machine.

| Version | Contents |
|---|---|
| v0.1.0 | Laravel app: MVP core |
| v0.2.0 | Phase 1: remaining MVP features |
| v0.3.0 | Phase 2: Growth features |
| v0.4.0 | Phase 3: multi-agent |
| v0.5.0 | Phase 4: "later" features |
| v0.6.0 | Phase 5: operations (deployment config and docs) |

## 3. The static HTML demo

```bash
scripts/decrypt.sh ~/path/to/housing-agent-private-key.txt   # → site/
python3 -m http.server 8000 -d site
```

## What's in the Laravel app

- **Public site** (Blade + Livewire):
  - **Home:** search card and district tiles.
  - **Rentals:** live filters synced to the URL (district, MTR line/station, rent, size, bedrooms, features, keyword in any language), map view, saved flats.
  - **Listing:** gallery lightbox, terms, enquiry form that creates a lead, WhatsApp link pre-filled in the visitor's language, with click tracking.
  - **Landlords:** 3-step form with photo upload.
  - **Tools:** moving-in cost and affordability calculators.
  - **About:** agent profile.
- **Compliance:** EAA licence numbers in the footer and on listings. A PICS checkbox is required on every form (PDPO), with a separate marketing opt-in.
- **Admin** (Filament 5, UI in 繁 / 简 / EN):
  - **Dashboard:** stats and a "needs attention" list.
  - **Listings:** language tabs; 繁 → 简 auto-converts with OpenCC; photos; publishing is blocked without an owner consent date.
  - **Leads:** status pipeline, notes, follow-up dates, matching listings, PDPO export and anonymise.
  - **Landlord submissions:** one click converts a submission into a draft listing.
  - **Reference data:** districts, estates, MTR lines and stations.
  - **Translation centre:** missing-translation report and a live editor for UI strings.
  - **Settings:** agency details, stamp duty rates and default lease terms.
  - **Users and agents:** roles admin / agent / assistant, ready for multi-agent use (Phase 4).
- **Stack:** Laravel 13.39, Filament 5.11, Livewire 4.4, spatie/laravel-translatable 6.14, overtrue/php-opencc 1.3, Pest 4.7.

## Keep the private key safe

If the private key is lost, the code can't be recovered. Never commit it; the hook and `.gitignore` both block files named `*private-key*`.
