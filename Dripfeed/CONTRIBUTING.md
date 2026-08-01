# Contributing to Dripfeed

Dripfeed is intentionally plain: Bash on the MiSTer card, one browser HTML file,
and small contract tests. You do not need a build system to read or change it.

## Before opening a pull request

1. Read [`STAGING_SPEC.md`](STAGING_SPEC.md). It is the compatibility contract
   shared by the web scheduler, CLI, and reveal engine.
2. Keep user game files, BIOS, saves, credentials, and SD-card images out of Git.
3. Run `bash tests/run.sh` and `bash -n` on every changed shell script.
4. If the CSV contract changes, run `tests/csv-contract.test.js` with Node.js and
   update the spec, web scheduler, CLI, engine, and tests together.
5. Explain hardware-only checks in the pull request. A desktop test is not proof
   that a MiSTer core, graphical menu, or network clock behaves identically.

## Design rules

- Never overwrite a visible game or silently delete support files.
- Preserve exact game and folder names so saves, artwork, and RetroAchievements
  hashes continue to match.
- Treat firmware/support entries as protected infrastructure, not games. When in
  doubt, leave an entry visible and log why it was skipped.
- Prefer readable Bash and browser JavaScript over minified or generated code.
- New behavior needs a short changelog entry and a regression test.

## License

Contributions are accepted under GPLv3 or later. Add a copyright line when adding
substantial new source, and retain the notices and acknowledgements already in the
project. See [`LICENSE`](LICENSE) and [`CREDITS.md`](CREDITS.md).
