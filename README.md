# Housing Agent: interactive demo (encrypted)

An interactive demo website for a Hong Kong residential rental agent: urban districts (港島 · 九龍), rentals first, in 繁 / 简 / EN. It's plain HTML, CSS and JavaScript with no build step, and includes:

- **Public site:** home with search, rentals search (live filters, map view, shareable links), listing detail (gallery lightbox, enquiry form, WhatsApp pre-fill), landlord sign-up form, moving-in cost and affordability calculators, agent profile, saved flats, and mobile layout with a bottom tab bar.
- **Admin panel (demo):** dashboard, listings table with bulk actions, listing editor (language tabs, 繁 → 简 auto-convert, photos), leads pipeline (table and kanban), lead detail, and a translation centre. Everything is stored in the browser's `localStorage`; a "Reset demo data" button clears it.

All listings, names and numbers are samples. Drawings stand in for real photos.

## The source is encrypted

This repository contains **only the encrypted site**:

| Path | What it is |
|---|---|
| `encrypted/site.tar.gz.age` | The whole HTML site, encrypted with [age](https://age-encryption.org) |
| `encrypted/site.tar.gz.age.sha256` | Checksum, verified before decrypting |
| `keys/recipient.txt` | Public key used to encrypt (safe to share) |
| `scripts/decrypt.sh` / `scripts/encrypt.sh` | Helper scripts |

The matching **private key is not in this repository**. Without it the files can't be read.

### Decrypt and open the demo

Requirements: `age`, `tar` and `python3` (`brew install age` on macOS, `apt install age` on Debian/Ubuntu).

```bash
# 1. Decrypt with your private key (writes the site to ./site)
scripts/decrypt.sh /path/to/housing-agent-private-key.txt

# 2. Serve it locally and open http://localhost:8000
python3 -m http.server 8000 -d site
```

Open `http://localhost:8000/admin/` for the admin panel.

Without the scripts, the equivalent commands are:

```bash
age -d -i /path/to/housing-agent-private-key.txt encrypted/site.tar.gz.age | tar -xz -C site
```

### Edit and re-encrypt

1. Decrypt into `src/` with `scripts/decrypt.sh key.txt src`.
2. Edit the files in `src/`.
3. Re-encrypt with `scripts/encrypt.sh`, then commit `encrypted/`.

`src/` and `site/` are in `.gitignore`, so plaintext never gets committed.

To let another person decrypt, add their age public key as a new line in `keys/recipient.txt` and re-encrypt.

### Important

- **Keep the private key safe and backed up.** If it's lost, the encrypted site can't be recovered.
- Never commit the private key. The `.gitignore` blocks `*private-key*` and `age-key*.txt`.
- GitHub Pages can't serve the encrypted files. Run the demo locally, or decrypt it and deploy the `site/` folder to a private host.

## Project structure (after decrypting)

```
index.html  rentals.html  listing.html  landlords.html  tools.html  about.html
admin/      index.html  listings.html  listing-edit.html  leads.html  lead.html  translations.html
assets/css/site.css            design tokens and components ("Harbour Neon")
assets/js/data.js              sample listings, districts, MTR stations, leads
assets/js/i18n*.js             繁 / 简 / EN strings
assets/js/illustrations.js     drawn stand-ins for photos, skyline, maps
assets/js/app.js               header/footer, storage, shared helpers
assets/js/admin.js             admin chrome
assets/js/pages/*.js           page scripts
```

Before going live, replace the placeholders in `assets/js/data.js` (`config`): agency name, EAA licence numbers, office address and WhatsApp number.
