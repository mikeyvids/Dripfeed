# Recover an older split or incomplete multi-disc queue

Use this only when an older Dripfeed build left the same game both in
`games/<SYSTEM>/` and in a dated `.dripfeed` queue, or when one side is missing
disc files.

## First: preserve both sides

1. Power MiSTer off normally and put the SD card in a computer.
2. Copy **both** versions of the affected game folder to another drive. Do not
   merge, delete, or overwrite either one yet.
3. If the game has an `.m3u`, every line in it must point to a file present in
   that same folder. If it has `.cue` files, every `FILE` entry must be present.
4. Compare file sizes—or hashes when available—with your known-good source.

The visible `games/<SYSTEM>/<Game>/` folder from the old interrupted browser
operation is usually the untouched source, while the dated queue folder is the
unfinished copy. Verify instead of assuming.

## Then: install the repaired build

1. Replace `Scripts/Dripfeed.sh` with version 1.3.2 or newer.
2. Run it once from MiSTer's Scripts menu so its hidden engine updates.
3. New schedules will wait under `/.dripfeed-library/<SYSTEM>/`, outside
   `games/`. Existing `games/<SYSTEM>/.dripfeed/` queues are still read.
4. Browser changes marked **MOVE PENDING** are applied by this card-side engine
   the next time Dripfeed runs; the browser does not copy the game folder.
5. Run `Scripts/.dripfeed/dripfeed-engine.sh --diag` over SSH if available. It
   labels incomplete sets, duplicate queue entries, and a queued/visible name
   collision. These are recovery holds; Dripfeed will not guess which copy wins.

If both a staged and visible copy still exist, keep the verified complete copy
in `games/<SYSTEM>/`. Move the questionable one off-card for examination. The
current Undrip operation does not silently delete a collision or restore an
incomplete legacy set; it moves the questionable staged side into
`.dripfeed-library/.conflicts/`.

There is no safe automatic way to infer a missing disc from a loose group of
CHDs that has no `.m3u` or other manifest. Compare that set with the original
library source before playing or deleting anything.
