{ pkgs, ... }:
let
  homeFlake = "$HOME/.config/home-manager/flake.nix";
  devKey = ".keys/dev.key";
in
{
  commands = [
    {
      name = "repl";
      category = "utilities";
      help = "Open a `nix repl` with this flake";
      command = "nix repl .#";
    }
    {
      name = "home-link";
      category = "utilities";
      help = "Install link to flake.nix for home-manager to use";
      command =
        ''
          [ -e "${homeFlake}" ] && echo "${homeFlake} already exists" && exit 1

          mkdir -p "$(dirname "${homeFlake}")"
          ln -sf "$(pwd)/flake.nix" "${homeFlake}"
          echo "Installed link to $(pwd)/flake.nix at ${homeFlake}"
        '';
    }
    {
      name = "home-unlink";
      category = "utilities";
      help = "Remove home-manager flake.nix link";
      command = "rm -f ${homeFlake}";
    }
    {
      name = "ragenix";
      category = "utilities";
      help = "age-encrypted secrets for NixOS";
      command = ''exec ${pkgs.ragenix}/bin/ragenix --identity "$PRJ_ROOT/.keys/dev.key" "$@"'';
    }
    {
      name = "qemu-genmac";
      category = "utilities";
      help = "Generate MAC address suitable for QEMU";
      command = ''printf "52:54:00:%02x:%02x:%02x\n" $((RANDOM%256)) $((RANDOM%256)) $((RANDOM%256))'';
    }
    {
      name = "ssh-get-ed25519";
      category = "utilities";
      help = "Print the ed25519 pubkey for a host";
      command = "${pkgs.openssh}/bin/ssh-keyscan -t ed25519 \"$1\" 2> /dev/null | awk '{ print $2 \" \" $3 }'";
    }
    {
      name = "json2nix";
      category = "utilities";
      help = "Convert JSON to formatted Nix";
      command = "nix eval --impure --expr 'builtins.fromJSON (builtins.readFile /dev/stdin)' | ${pkgs.nixfmt-rfc-style}/bin/nixfmt";
    }

    {
      name = "fmt";
      category = "tasks";
      help = pkgs.nixpkgs-fmt.meta.description;
      command = ''exec "${pkgs.nixpkgs-fmt}/bin/nixpkgs-fmt" "$@"'';
    }
    {
      name = "home-switch";
      category = "tasks";
      help = "Run `home-manager switch`";
      command = ''home-manager switch --flake . "$@"'';
    }
    {
      name = "build-system";
      category = "tasks";
      help = "Build NixOS configuration";
      command = ''nix build "''${@:2}" ".#nixosConfigurations.\"$1\".config.system.build.toplevel"'';
    }
    {
      name = "build-n-switch";
      category = "tasks";
      help = "Shortcut to nixos-rebuild for this flake";
      command = ''
        # HACK: Upstream changes in Git + Nix makes this necessary
        # https://github.com/NixOS/nix/issues/10202
        doas git config --global --add safe.directory "$PWD"
        doas nixos-rebuild --flake . "$@"
      '';
    }
    {
      name = "run-vm";
      category = "tasks";
      help = "Run NixOS configuration as a VM";
      command =
        ''
          cd "$PRJ_ROOT"
          tmp="$(mktemp -d nix-vm.XXXXXXXXXX --tmpdir)"
          install -Dm0400 "${devKey}" "$tmp/xchg/dev.key"
          TMPDIR="$tmp" USE_TMPDIR=1 nix run ".#nixosConfigurations.\"$1\".config.my.buildAs.devVM"
        '';
    }
    {
      name = "build-iso";
      category = "tasks";
      help = "Build NixOS configuration into an ISO";
      command = ''nix build "''${@:2}" ".#nixfiles.config.nixos.systems.\"$1\".configuration.config.my.buildAs.iso"'';
    }
    {
      name = "build-kexec";
      category = "tasks";
      help = "Build NixOS configuration as kexec tree";
      command = ''nix build "''${@:2}" ".#nixfiles.config.nixos.systems.\"$1\".configuration.config.my.buildAs.kexecTree"'';
    }
    {
      name = "build-netboot";
      category = "tasks";
      help = "Build NixOS configuration as netboot tree";
      command = ''nix build "''${@:2}" ".#nixfiles.config.nixos.systems.\"$1\".configuration.config.my.buildAs.netbootTree"'';
    }
    {
      name = "build-home";
      category = "tasks";
      help = "Build home-manager configuration";
      command = ''nix build "''${@:2}" ".#homeConfigurations.\"$1\".activationPackage"'';
    }
    {
      name = "update-nixpkgs";
      category = "tasks";
      help = "Update nixpkgs flake inputs";
      command = ''nix flake update nixpkgs-{unstable,stable,mine,mine-stable}'';
    }
    {
      name = "update-home-manager";
      category = "tasks";
      help = "Update home-manager flake inputs";
      command = ''nix flake update home-manager-{unstable,stable}'';
    }
    {
      name = "update-installer";
      category = "tasks";
      help = "Update installer tag (to trigger new release)";
      command = ''git tag -f installer && git push -f origin installer'';
    }
    {
      name = "deploy-multi";
      category = "tasks";
      help = "Deploy multiple flakes at once";
      command = ''
        for f in $@; do
          deploy "$O" $f
        done
      '';
    }
  ];
}
