{nixpkgs, ...}: with nixpkgs; stdenv.mkDerivation rec {
	name = "gzip_dir";

	src = ./gzip_dir.sh;

	unpackPhase = " ";

	buildPhase = ''
		sed -i \
			-e 's_^BC=.*_BC=${pkgs.bc}/bin/bc_' \
			-e 's_^FIND=.*_FIND=${pkgs.findutils}/bin/find_' \
			-e 's_^GZIP=.*_GZIP=${pkgs.zopfli}/bin/zopfli_' \
			-e 's_^PARALLEL=.*_PARALLEL=${pkgs.parallel}/bin/parallel_' \
			-e 's_^RM=.*_RM=${pkgs.coreutils}/bin/rm_' \
			-e 's_^STAT=.*_STAT=${pkgs.coreutils}/bin/stat_' \
			"$src"
	'';

	installPhase = ''
		install -Dm755 $src $out/bin/gzip_dir
	'';
}
