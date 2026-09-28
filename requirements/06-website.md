# 06. Product Website

## Purpose

- Publish a responsive, single-page English overview of Rlz Sound Mixer on GitHub Pages.
- Keep the public landing page separate from the React interface embedded in the macOS app.
- Use Tailwind utility classes and the same dark slate, sky-blue, and signal-meter accents as the app interface. Avoid custom page CSS; the Tailwind entry stylesheet contains only the Tailwind import.
- Use plain, factual project copy: describe the app, its features, system requirements, download location, and limitations without slogans or promotional claims.
- Include real screenshots captured from the application. Do not substitute illustrative mockups for app screenshots.
- Describe routing, source levels, internal virtual buses, macOS support, local settings, and permission limits accurately. Do not imply that internal buses are system devices or promise capture outside macOS and device capabilities.
- Link to the current GitHub release and update the version and URL when a newer app release is published. Do not claim notarization or universal application-audio capture.

## Publishing

- The static site source is `Website/`; Vite and Tailwind build it using the pinned dependencies in `Web/` into `Website/dist/`.
- GitHub Actions builds the website and publishes `Website/dist/` to GitHub Pages after pushes to `main` and by manual workflow dispatch.
- The repository's Pages publishing source must be GitHub Actions. The published site must not depend on external runtime assets.
- Verify the first deployment and its public URL after the workflow runs. Confirm mobile layout and repository/release links on the published page.
