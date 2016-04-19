gzip_dir_ignore=(
	'-not' '-name' '*.map'
	'-not' '-name' '*.src.js'
	'-not' '-name' '*.png'
)
gzip_dir () { (
	if [ -z "$1" ]; then
		echo 'Usage: gzip_dir $dir'
		return 1
	fi
	
	echo 'Gzipping content...'
	find "$1" -type f "${ignore[@]}" -print0 \
		| parallel -0v -- zopfli '{}'
	
	echo 'Pruning uncompressable content...'
	shopt -s globstar
	for comp in "$1"/**/*.gz; do
		local orig="''${comp%%.gz}"
		[ -f "$orig" ] || continue # Skip if we don't have the source.
		
		local compsize=$(stat -c %s "$comp")
		local origsize=$(stat -c %s "$orig")
		if [ $(bc -l <<<"$compsize/$origsize > 0.95") -ne 0 ]; then
			echo "Removing '$comp' with ratio $(bc -l <<<"$compsize/$origsize")"
			rm "$comp"
		fi
	done
) }
