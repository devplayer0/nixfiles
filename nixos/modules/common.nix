{ lib, pkgs, pkgs', inputs, options, config, ... }:
let
  inherit (builtins) attrValues;
  inherit (lib) flatten optional mkIf mkDefault mkMerge mkAliasDefinitions;
  inherit (lib.my) mkOpt' mkBoolOpt' dummyOption;

  defaultUsername = "dev";
  uname = config.my.user.name;
in
{
  options = with lib.types; {
    my = {
      # Pretty hacky but too lazy to figure out if there's a better way to alias the options
      user = mkOpt' (attrsOf anything) { } "User definition (as `users.users.*`).";
      homeConfig = mkOpt' anything { } "Home configuration (as `home-manager.users.*`)";

      ssh = {
        # If enabled, we can't set `authorized_keys` from home-manager because SSH won't like the file being owned by
        # root.
        strictModes = mkBoolOpt' false
          ("Specifies whether sshd(8) should check file modes and ownership of the user's files and home directory "+
          "before accepting login.");
      };
    };

    # Only present in >=22.05, so forward declare
    documentation.nixos.options.warningsAreErrors = dummyOption;
  };

  config = mkMerge [
    {
      my = {
        user = {
          name = mkDefault defaultUsername;
          isNormalUser = true;
          uid = mkDefault 1000;
          extraGroups = mkDefault [ "wheel" ];
          password = mkDefault "hunter2"; # TODO: secrets...
        };
      };

      home-manager = {
        # Installs packages in the system config instead of in the local profile on activation
        useUserPackages = mkDefault true;
      };

      users = {
        mutableUsers = false;
        users.${uname} = mkAliasDefinitions options.my.user;
      };

      # NOTE: As the "outermost" module is still being evaluated in NixOS land, special params (e.g. pkgs) won't be
      # passed to it
      home-manager.users.${uname} = config.my.homeConfig;

      security = {
        sudo.enable = mkDefault false;
        doas = {
          enable = mkDefault true;
          wheelNeedsPassword = mkDefault false;
        };
      };

      nix = {
        package = pkgs'.unstable.nixVersions.stable;
        extraOptions =
          ''
            experimental-features = nix-command flakes ca-derivations
          '';
      };
      nixpkgs = {
        overlays = [
          # TODO: Wait for https://github.com/NixOS/nixpkgs/pull/159074 to arrive to nixos-unstable
          (final: prev: { remarshal = pkgs'.master.remarshal; })
        ];
        config = {
          allowUnfree = true;
        };
      };

      documentation = {
        nixos = {
          enable = mkDefault true;
          options.warningsAreErrors = mkDefault false;
        };
      };

      time.timeZone = mkDefault "Europe/Dublin";

      boot = {
        # Use latest LTS release by default
        kernelPackages = mkDefault pkgs.linuxKernel.packages.linux_5_15;
        loader = {
          efi = {
            efiSysMountPoint = mkDefault "/boot";
            canTouchEfiVariables = mkDefault false;
          };
          grub = {
            memtest86.enable = mkDefault true;
          };
          systemd-boot = {
            enable = mkDefault true;
            editor = mkDefault true;
            consoleMode = mkDefault "max";
            configurationLimit = mkDefault 10;
            memtest86.enable = mkDefault true;
          };
        };
      };

      networking = {
        useDHCP = mkDefault false;
        enableIPv6 = mkDefault true;
      };
      virtualisation = {
        forwardPorts = flatten [
          (optional config.services.openssh.openFirewall { from = "host"; host.port = 2222; guest.port = 22; })
        ];
      };

      environment.systemPackages = with pkgs; [
        bash-completion
        vim
      ];

      services = {
        kmscon = {
          enable = mkDefault true;
          hwRender = mkDefault true;
          extraOptions = "--verbose";
          extraConfig =
            ''
              font-name=SauceCodePro Nerd Font Mono
            '';
        };

        openssh = {
          enable = mkDefault true;
          extraConfig = ''StrictModes ${if config.my.ssh.strictModes then "yes" else "no"}'';
        };
      };

      system = {
        stateVersion = "21.11";
        configurationRevision = with inputs; mkIf (self ? rev) self.rev;
      };
    }
    (mkIf config.services.kmscon.enable {
      fonts.fonts = with pkgs; [
        (nerdfonts.override {
          fonts = [ "SourceCodePro" ];
        })
      ];
    })
    (mkIf config.my.build.isDevVM {
      networking.interfaces.eth0.useDHCP = mkDefault true;
    })
  ];

  meta.buildDocsInSandbox = false;
}
