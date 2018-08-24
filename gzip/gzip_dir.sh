#!/bin/sh
set -eu

BC=bc
FIND=find
GZIP=zopfli
PARALLEL=parallel
RM=rm
STAT=stat

gzip_dir_ignore=(
	'-not' '-name' '*.map'
	'-not' '-name' '*.src.js'
	'-not' '-name' '*.png'
)

if [ -z "$1" ]; then
	echo 'Usage: gzip_dir $dir'
	exit 1
fi

echo 'Gzipping content...'
$FIND "$1" -type f "${ignore[@]}" -print0 \
	| $PARALLEL -0v -- $GZIP '{}'

echo 'Pruning uncompressable content...'
shopt -s globstar
for comp in "$1"/**/*.gz; do
	orig="''${comp%%.gz}"
	[ -f "$orig" ] || continue # Skip if we don't have the source.
	
	compsize=$($STAT -c %s "$comp")
	origsize=$($STAT -c %s "$orig")
	if [ $($BC -l <<<"$compsize/$origsize > 0.95") -ne 0 ]; then
		echo "Removing '$comp' with ratio $($BC -l <<<"$compsize/$origsize")"
		$RM "$comp"
	fi
done
