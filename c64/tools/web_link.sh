#!/bin/sh
# Point the "play in the browser" links of the READMEs at the commit that last changed docs/galaga.prg. A link with a commit in it never
# comes from a cache (a link to master can, in the browser or in vc64web); a query string (?v=...) does not work: vc64web needs the address
# to end in .prg. Run it after you commit a changed docs/galaga.prg, then commit the READMEs.
cd "$(dirname "$0")/../.." || exit 1
SHA=$(git log -1 --format=%H -- c64/docs/galaga.prg)
[ -n "$SHA" ] || { echo "docs/galaga.prg is not committed yet" >&2; exit 1; }
sed -i '' -E "s#raw.githubusercontent.com/Shadester/galagas/[0-9a-z]+/c64/docs/galaga.prg#raw.githubusercontent.com/Shadester/galagas/$SHA/c64/docs/galaga.prg#" README.md c64/README.md docs/index.html
git diff --stat -- README.md c64/README.md docs/index.html
