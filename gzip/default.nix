{nixpkgs, klib}: with nixpkgs;
makeSetupHook {
	deps = with pkgs; [ parallel zopfli ];
} ./gzip.sh
