{nixpkgs, klib}:
with nixpkgs;
with lib;
let
	app-type = types.submodule {
		options.id = mkOption {
			type = types.str;
		};
		options.labels = mkOption {
			type = types.attrsOf types.str;
			default = {};
		};
		
		options.instances = mkOption {
			type = types.int;
			default = 1;
		};
		options.constraints = mkOption {
			type = types.listOf (types.listOf types.str);
			default = [];
		};
		
		options.cpus = mkOption {
			type = types.str;
			default = "0.01";
		};
		options.mem = mkOption {
			type = types.int;
			default = 0;
		};
		options.disk = mkOption {
			type = types.int;
			default = 0;
		};
		options.ports = mkOption {
			type = types.either types.int (types.listOf types.int);
			default = 0;
		};
		
		options.user = mkOption {
			type = types.str;
			default = "root";
		};
		options.path = mkOption {
			type = types.listOf types.path;
			default = [];
		};
		options.env = mkOption {
			type = types.attrsOf types.str;
			default = {};
			description = ''
				Set environment variables. These variables have the highest
				prescedence and will be available when your command is run.
			'';
		};
		options.env-files = mkOption {
			type = types.listOf types.str;
			default = [];
			description = ''
				Read variables from files. These files will be sourced by bash
				and have all of their variables exported.
				
				Variables set by the `env` setting override these.
			'';
		};
		options.env-pass = mkOption {
			type = types.listOf types.str;
			default = [];
			description = ''
				These variables will not be cleared from the executors environment. They have the lowest priority and will be overwritten by `env-files` and `env`.
			'';
		};
		options.exec = mkOption {
			type = types.either types.str (types.listOf types.str);
		};
		
		options.healthChecks = mkOption {
			type = types.listOf types.unspecified;
			default = [];
		};
		options.upgradeStrategy = mkOption {
			type = types.unspecified;
			default = {};
		};
		
		options.dns = mkOption {
			default = [];
			type = types.listOf (types.submodule {
					options.name = mkOption {
						type = types.str;
					};
					options.cdn = mkOption {
						type = types.bool;
						default = false;
					};
					options.ttl = mkOption {
						type = types.int;
						default = 0;
					};
			});
		};
	};
	module = {
		options.apps = mkOption {
			type = types.listOf app-type;
		};
	};
in {
	config = configuration: let
		result = lib.evalModules {
			modules = [
				{ config.apps = configuration; }
				module
			];
		};
		apps = map (r: let
		env-1 = { PATH = makeBinPath r.path; } // r.env;
		env = concatStringsSep " " (mapAttrsToList (k: v: "${k}='${v}'") env-1);
		env-pass = concatMapStringsSep " " (k: ''"${k}=''${${k}}"'') r.env-pass;
		user-cmd = if isList r.exec then
			r.exec
		else
			["${pkgs.bash}/bin/bash" "-c" r.exec];
		stage2 = ''
			#! ${pkgs.bash}/bin/bash
			set -eax
			${ concatMapStringsSep "\n" (f: ". '${f}'") r.env-files }
			${ env }
			exec "$@"
			
			# Not executed, included to make a dependency.
			${concatStrings user-cmd}
		'';
		stage2f = klib.toExe "stage2.sh" stage2;
		sudo-user = if r.user == "root" then "" else "sudo '-u${r.user}'";
		dns-labels = listToAttrs (imap (i: e: {
			name = "kevincox-dns-${toString i}";
			value = builtins.toJSON { inherit (e) name cdn ttl; };
		}) r.dns);
	in {
		inherit (r) id instances constraints mem disk healthChecks upgradeStrategy;
		
		labels = dns-labels // r.labels;
		
		cpus = "JSON_UNSTRING${r.cpus}JSON_UNSTRING";
		
		ports = if isList r.ports then r.ports else range 1 r.ports;
		requirePorts = isList r.ports;
		
		user = "root";
		args = [
			"/run/current-system/sw/bin/bash" "-c" ''
				set -eax
				. /etc/kevincox-environment
				nix-store -r ${stage2f} --add-root klib-marathon-stage-2 --indirect
				chown ${r.user}: .
				exec ${sudo-user} env -i ${env-pass} ${stage2f} "$@"
			'' "stage2" # "stage2" is used as $0.
		] ++ user-cmd;
	}) result.config.apps;
	in stdenv.mkDerivation {
		name = "marathon.json";
		
		json = builtins.toJSON apps;
		bash = pkgs.bash;
		
		builder = builtins.toFile "builder.sh" ''
			source $stdenv/setup
			
			echo "$json" > "$out"
			substituteInPlace "$out" \
				--replace '"JSON_UNSTRING' "" \
				--replace 'JSON_UNSTRING"' ""
		'';
	};
}

