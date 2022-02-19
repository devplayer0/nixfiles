{ pkgs, ... }:
let
  homeFlake = "$HOME/.config/nixpkgs/flake.nix";
in
{
  commands = [
    {
      name = "repl";
      category = "utilities";
      help = "Open a `nix repl` with this flake";
      command =
        ''
          tmp="$(mktemp --tmpdir repl.nix.XXXXX)"
          echo "builtins.getFlake \"$PRJ_ROOT\"" > "$tmp"
          nix repl "$tmp" || true
          rm "$tmp"
        '';
    }
    {
      name = "home-link";
      category = "utilities";
      help = "Install link to flake.nix for home-manager to use";
      command =
        ''
          [ -e "${homeFlake}" ] && echo "${homeFlake} already exists" && exit 1

          mkdir -p "$(dirname "${homeFlake}")"
          ln -s "$(pwd)/flake.nix" "${homeFlake}"
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
  ];
}
