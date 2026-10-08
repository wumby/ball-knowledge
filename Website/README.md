# Hoops IQ website

The public Hoops IQ website is a Svelte + Vite static site. It produces three host-ready pages: `index.html`, `privacy.html`, and `support.html`.

## Local development

From this directory:

```sh
npm install
npm run dev
```

Build the static site with:

```sh
npm run build
```

Deploy the contents of `dist/` to any static host. Keep the HTML files at the site root so `/privacy.html` and `/support.html` work without server-side routing.

## App Store link

`VITE_APP_STORE_URL` is the only download destination. Set it to the published App Store product URL during the build:

```sh
VITE_APP_STORE_URL='https://apps.apple.com/app/id123456789' npm run build
```

When the variable is absent or blank, the download controls are deliberately non-clickable and say “Coming soon to the App Store.” No App Store URL is embedded in the source.

## Content and privacy review

Product screens are original CSS illustrations; they are not app screenshots and contain no player images, team marks, league marks, or player names. The ranked mockup uses the app’s original Five Alive Gold rank emblem. Before publishing an app update, compare `privacy.html` with the current App Store Connect privacy questionnaire and update it if the app’s data practices change.
