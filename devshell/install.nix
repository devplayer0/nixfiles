{ lib, pkgs, config, ... }:
let
  inherit (lib) mapAttrsToList;
  inherit (lib.my) mkOpt';

  parseArgs = opts:
    ''
      POSITIONAL_ARGS=()

      while [ $# -gt 0 ]; do
        # shellcheck disable=SC2221,SC2222
        case $1 in
          ${opts}
          -*|--*)
            die "Unknown option $1"
            ;;
          *)
            POSITIONAL_ARGS+=("$1") # save positional arg
            shift # past argument
            ;;
        esac
      done

      set -- "''${POSITIONAL_ARGS[@]}" # restore positional parameters
    '';
  installCommon = pkgs.writeShellApplication {
    name = "install-common.sh";
    runtimeInputs = with pkgs; [
      coreutils
      gnugrep
      openssh
      nixVersions.stable
      jq
    ];
    text =
      ''
        log() {
          echo -e "$@" >&2
        }
        debug() {
          [ -n "$DEBUG" ] || return 0
          log "[\e[32;1mdebug\e[0m]: \e[32m$*\e[0m"
        }
        info() {
          log "[\e[36;1minfo\e[0m]: \e[36m$*\e[0m"
        }
        warn() {
          log "[\e[33;1mwarn\e[0m]: \e[33m$*\e[0m"
        }
        error() {
          log "[\e[31;1merror\e[0m]: \e[31m$*\e[0m"
        }
        die() {
          error "$@"
          exit 1
        }

        askYN() {
          local question="$1"
          local options default

          if [ "$2" = y ]; then
            options="Y/n"
            default="y"
          else
            options="y/N"
            default="n"
          fi

          local input
          read -p "$question [$options] " -n 1 -s -r input
          : "''${input:=$default}"
          echo "$input"
          [[ "$input" =~ ^[yY]$ ]]
        }

        # : is a builtin that does nothing...
        : "''${DEBUG:=}"
        : "''${INSTALLER:=}"
        : "''${INSTALLER_SSH_OPTS:=}"
        : "''${INSTALLER_SSH_PORT:=22}"

        [ -z "$INSTALLER" ] && die "\$INSTALLER is not set"

        KNOWN_HOSTS="$(mktemp --tmpdir known_hosts.XXXXXX)"
        cleanup() {
          rm -f "$KNOWN_HOSTS"
        }
        trap cleanup EXIT

        IFS=" " read -ra SSH_OPTS <<< "$INSTALLER_SSH_OPTS"
        SSH_OPTS+=(-o StrictHostKeyChecking=ask -o UserKnownHostsFile="$KNOWN_HOSTS" -p "$INSTALLER_SSH_PORT")
        debug "ssh params: ''${SSH_OPTS[*]}"

        execInstaller() {
          debug "[root@$INSTALLER -p $INSTALLER_SSH_PORT] $*"
          ssh "''${SSH_OPTS[@]}" "root@$INSTALLER" -- "$@" 2> >(grep -v "Permanently added" 1>&2)
        }
      '';
  };
  installerCommandOpts = with lib.types; {
    options = {
      help = mkOpt' str null "Help message.";
      script = mkOpt' lines "" "Script contents.";
      packages = mkOpt' (listOf package) [ ] "Packages to make available to the script.";
    };
  };
in
{
  options.my.installerCommands = with lib.types;
    mkOpt' (attrsOf (submodule installerCommandOpts)) { } "Installer commands.";

  config = {
    my.installerCommands = {
      installer-shell = {
        help = "Get a shell into the installer";
        script =
          ''
            execInstaller "$@"
          '';
      };

      # TODO: Add new command to generate a template with the output of nixos-generate-config included

      do-install = {
        help = "Install a system configuration into a prepared installer that can be reached at $INSTALLER";
        script =
          ''
            noBootloader=
            noSubstitute=
            ${parseArgs
            ''
              --no-bootloader)
                noBootloader=true
                shift
                ;;
              --no-substitute)
                noSubstitute=true
                shift
                ;;
            ''}
            system="''${1:-}"
            [ -z "$system" ] && die "usage: $0 [--no-bootloader] [--no-substitute] <system>"

            : "''${INSTALLER_BUILD_OPTS:=}"
            IFS=" " read -ra BUILD_OPTS <<< "$INSTALLER_BUILD_OPTS"

            INSTALL_ROOT="$(execInstaller echo \$INSTALL_ROOT)"
            info "Installing configuration for $system to $INSTALLER:$INSTALL_ROOT"
            askYN "Continue?" n || exit 1

            params=()
            [ -z "$noSubstitute" ] && params+=(--substitute-on-destination)

            flakeAttr="$PRJ_ROOT#nixosConfigurations.$system.config.system.build.toplevel"
            info "Building $flakeAttr..."
            storePath="$(nix build "''${BUILD_OPTS[@]}" --no-link --json "$flakeAttr" | jq -r .[0].outputs.out)"

            info "Copying closure of configuration $storePath to target..."
            NIX_SSHOPTS="''${SSH_OPTS[*]}" nix copy "''${params[@]}" \
              --to "ssh://root@$INSTALLER?remote-store=$INSTALL_ROOT" "$storePath"

            profile=/nix/var/nix/profiles/system
            info "Setting $profile on target to point to copied configuration..."
            # Use `nix-env` since `nix profile` uses a non-backwards compatible manifest format
            execInstaller nix-env --store "$INSTALL_ROOT" -p "$INSTALL_ROOT$profile" --set "$storePath"

            # Make switch-to-configuration recognise this as a NixOS system
            execInstaller "mkdir -m 0755 -p \"$INSTALL_ROOT/etc\" && touch \"$INSTALL_ROOT/etc/NIXOS\""

            if [ -z "$noBootloader" ]; then
              info "Activating configuration and installing bootloader..."
              # Grub needs an mtab.
              execInstaller ln -sfn /proc/mounts "$INSTALL_ROOT/etc/mtab"
              execInstaller "export NIXOS_INSTALL_BOOTLOADER=1 && \
                nixos-enter --root \"$INSTALL_ROOT\" -- /run/current-system/bin/switch-to-configuration boot"
            else
              info "Activating configuation..."
              execInstaller \
                nixos-enter --root "$INSTALL_ROOT" -- /run/current-system/bin/switch-to-configuration boot
            fi

            info "Success!"
          '';
      };
    };

    commands = mapAttrsToList (name: cmd: {
      inherit name;
      inherit (cmd) help;
      category = "installation";
      package = pkgs.writeShellApplication {
        inherit name;
        runtimeInputs = cmd.packages;
        text =
          ''
            # shellcheck disable=SC1091
            source "${installCommon}/bin/install-common.sh"

            ${cmd.script}
          '';
      };
    }) config.my.installerCommands;
  };
}
