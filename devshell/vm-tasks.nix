{ lib, pkgs, config, ... }:
let
  inherit (lib) mapAttrsToList;
  inherit (lib.my) mkOpt;

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
  common = pkgs.writeShellApplication {
    name = "vm-tasks-common.sh";
    runtimeInputs = with pkgs; [
      openssh
    ];
    text =
      ''
        : "''${VM_SSH_OPTS:=}"

        IFS=" " read -ra SSH_OPTS <<< "$VM_SSH_OPTS"
        SSH_OPTS+=(-N)

        HOST="''${1:-}"
        VM="''${2:-}"
        if [ -z "$HOST" ] || [ -z "$VM" ]; then
          echo "usage: $0 <host> <vm> ..." >&2
          exit 1
        fi

        SOCKS_DIR="$(mktemp -d --tmpdir vm-socks.XXXXXX)"
        cleanup() {
          rm -rf "$SOCKS_DIR"
        }
        trap cleanup EXIT

        SOCKS=()
        closeSocks() {
          for p in "''${SOCK_PIDS[@]}"; do
            kill "$p"
          done
        }
        openSock() {
          local s="$SOCKS_DIR"/"$1".sock
          ssh "''${SSH_OPTS[@]}" -L "$s":/run/vms/"$VM"/"$1".sock "$HOST" &
          SOCKS+=($!)
          echo "$s"
        }
      '';
  };
  vmTaskOpts = with lib.types; {
    options = {
      help = mkOpt str null;
      script = mkOpt lines "";
      packages = mkOpt (listOf package) [ ];
    };
  };
in
{
  options.my.vmTasks = with lib.types;
    mkOpt (attrsOf (submodule vmTaskOpts)) { };

  config = {
    my.vmTasks = {
      vm-tty = {
        help = "Access remote VM's TTY";
        packages = with pkgs; [ minicom ];
        script =
          ''
            sock="$(openSock tty)"
            minicom -D unix#"$sock"
            closeSocks
          '';
      };
      vm-monitor = {
        help = "Access remote VM's QEMU monitor";
        packages = with pkgs; [ minicom ];
        script =
          ''
            sock="$(openSock monitor)"
            minicom -D unix#"$sock"
            closeSocks
          '';
      };
      vm-viewer = {
        help = "Access remote VM's display with virt-viewer";
        packages = with pkgs; [ virt-viewer ];
        script =
          ''
            sock=$(openSock spice)
            remote-viewer spice+unix://"$sock"
            closeSocks
          '';
      };
    };

    commands = mapAttrsToList (name: cmd: {
      inherit name;
      inherit (cmd) help;
      category = "vm-tasks";
      package = pkgs.writeShellApplication {
        inherit name;
        runtimeInputs = cmd.packages;
        text =
          ''
            # shellcheck disable=SC1091
            source "${common}/bin/vm-tasks-common.sh"

            ${cmd.script}
          '';
      };
    }) config.my.vmTasks;
  };
}
