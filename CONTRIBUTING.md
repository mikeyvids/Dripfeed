# Contributing

The suite is intentionally readable: Bash, self-contained HTML, and small test
harnesses. Please keep contributions understandable without proprietary tools.

Before a pull request:

1. Keep ROMs, saves, BIOS files, credentials, card images, private paths, and
   generated archives out of Git.
2. Run `bash tests/run.sh` from the repository root.
3. Add a regression test for changed behavior.
4. Update the affected README and changelog.
5. Clearly label hardware-only checks that still need a real MiSTer.

Never overwrite a visible game, guess through an ambiguous recovery state,
delete a profile to simplify an operation, or publish a credential. Contributions
are accepted under GPLv3 or later and must retain existing notices and credits.
