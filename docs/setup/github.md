# GitHub setup

Repository: https://github.com/cicorias/satchel-app (public, ADR-0014).

The agent applies these settings through `gh` when it creates the repo:

- Secret scanning and push protection: **on**
- Pages: **GitHub Actions** source (`.github/workflows/pages.yml` publishes `site/`)
- Issues: **on**, for external bug reports and support only. Work items live in the repo under `.scratch/` (ADR-0018).

You need to do these in the web UI:

1. **Social preview:** Settings → General → Social preview → upload `store/github/social-preview-1280x640.png`.
2. **Branch protection** (when switching from scaffolding to PRs): Settings → Rules → Rulesets → new ruleset for `main` that requires the `web` and `apple` checks and blocks force pushes.
3. **Pages URL:** after the first `pages` workflow run, confirm that https://cicorias.github.io/satchel-app/ serves the site. A custom domain can be added later under Settings → Pages.
