let
	nixpkgs = import <nixpkgs> {};
	klib = rec {
		load = file: import file { inherit nixpkgs klib; };
		
		marathon = load ./marathon.nix;
		toExe = name: content: nixpkgs.stdenv.mkDerivation {
			inherit name content;
			
			builder = builtins.toFile "toExe-builder.sh" ''
				source $stdenv/setup
				
				echo "$content" > "$out"
				chmod +x "$out"
			'';
		};
	};
in klib
