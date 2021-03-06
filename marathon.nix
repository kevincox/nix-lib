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
					options.type = mkOption {
						type = types.str;
						default = "A";
					};
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
					options.priority = mkOption {
						type = types.nullOr types.int;
						default = null;
					};
					options.weight = mkOption {
						type = types.nullOr types.int;
						default = null;
					};
			});
		};
	};
	apps-type = mkOption {
		type = types.listOf app-type;
	};
in {
	config = configuration: let
		result = lib.evalModules {
			modules = [
				{
					config._module.check = true;
					
					options.marathon.config = apps-type;
					config.marathon.config = configuration;
				}
			];
		};
		apps = map (r: let
		env-1 = { PATH = makeBinPath r.path; } // r.env;
		env = concatStringsSep "\n" (mapAttrsToList (k: v: "${k}='${v}'") env-1);
		env-pass = concatMapStringsSep " " (k: ''"${k}=''${${k}}"'') r.env-pass;
		user-cmd = if isList r.exec then r.exec
			else ["${pkgs.bash}/bin/bash" "-c" "set -eux\n\n${r.exec}"];
		change-user = if r.user == "root" then ""
			else "${pkgs.utillinux}/bin/runuser '-u${r.user}' --";
		stage2 = ''
			#! ${pkgs.dash}/bin/dash
			set -eaux
			
			${ concatMapStringsSep "\n" (f: ". '${f}'") r.env-files }
			${ env }
			
			${pkgs.coreutils}/bin/chown ${r.user}: .
			exec ${change-user} "$@"
			
			# Not executed, included to make a dependency.
			${concatStrings user-cmd}
		'';
		stage2f = klib.toExe "stage2.sh" stage2;
		dns-labels = listToAttrs (imap (i: e: {
			name = "kevincox-dns-${toString i}";
			value = builtins.toJSON { inherit (e) type name cdn ttl priority weight; };
		}) r.dns);
	in {
		inherit
			stage2f;
		inherit (r)
			constraints
			cpus
			disk
			healthChecks
			id
			instances
			mem
			upgradeStrategy;
		
		labels = dns-labels // r.labels;
		
		ports = if isList r.ports then r.ports else range 1 r.ports;
		requirePorts = isList r.ports;
		
		user = "root";
		args = [
			"/run/current-system/sw/bin/sh" "-c" ''
				set -eaux
				. /etc/kevincox-environment
				nix-store -r ${stage2f} --add-root klib-marathon-stage-2 --indirect
				exec env -i ${env-pass} ${stage2f} "$@"
			'' "stage2" # "stage2" is used as $0.
		] ++ user-cmd;
	}) result.config.marathon.config;
	in stdenv.mkDerivation {
		name = "marathon.json";
		
		buildInputs = with pkgs; [ nix ruby ];
		
		json = builtins.toJSON apps;
		
		builder = builtins.toFile "builder.sh" ''
			source $stdenv/setup
			
			ruby -e '
				require "json"
				
				json = JSON.parse(ENV.fetch("json"))
				json.each do |job|
					script = job.delete "stage2f"
					deps = IO.popen(%W[nix-store -qR #{script}]).each_line.map &:chomp
					size = IO.popen(%W[du -sc -B1M] + deps).each_line.to_a.last.to_i
					
					job["cpus"] = job["cpus"].to_i
					job["disk"] = job["disk"] + size + 1
				end
				
				File.write ENV.fetch("out"), json.to_json
			'
		'';
	};
}

