{ lib, pkgs, pkgs', inputs, config, ... }:
let
  inherit (lib) mkIf mkDefault mkMerge;
  inherit (lib.my) mkBoolOpt' dummyOption;
in
{
  options = with lib.types; {
    my = {
      ssh = {
        strictModes = mkBoolOpt' true
          ("Specifies whether sshd(8) should check file modes and ownership of the user's files and home directory "+
          "before accepting login.");
      };
    };

    # Only present in >=22.05, so forward declare
    documentation.nixos.options.warningsAreErrors = dummyOption;
  };

  imports = [
    inputs.impermanence.nixosModule
    inputs.agenix.nixosModules.age
  ];

  config = mkMerge [
    {
      system = {
        stateVersion = "21.11";
        configurationRevision = with inputs; mkIf (self ? rev) self.rev;
      };

      home-manager = {
        # Installs packages in the system config instead of in the local profile on activation
        useUserPackages = mkDefault true;
      };

      users = {
        mutableUsers = false;
      };

      security = {
        sudo.enable = mkDefault false;
        doas = {
          enable = mkDefault true;
          wheelNeedsPassword = mkDefault false;
        };
      };

      nix = {
        package = pkgs'.mine.nix;
        # TODO: This has been renamed to nix.settings.trusted-users in 22.05
        trustedUsers = [ "@wheel" ];
        extraOptions =
          ''
            experimental-features = nix-command flakes ca-derivations
          '';
      };
      nixpkgs = {
        overlays = [
          inputs.deploy-rs.overlay
        ];
        config = {
          allowUnfree = true;
        };
      };

      documentation = {
        enable = mkDefault true;
        nixos = {
          enable = mkDefault true;
          options.warningsAreErrors = mkDefault false;
        };
      };

      time.timeZone = mkDefault "Europe/Dublin";

      boot = {
        # Use latest LTS release by default
        kernelPackages = mkDefault pkgs.linuxKernel.packages.linux_5_15;
        kernel = {
          sysctl = {
            "net.ipv6.route.max_size" = mkDefault 16384;
          };
        };
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

      environment.systemPackages = with pkgs; [
        bash-completion
        vim
      ];

      programs = {
        # This will enable generating completions at build time and prevent home-manager fish from generating them
        # locally
        fish.enable = mkDefault true;
      };

      services = {
        kmscon = {
          # As it turns out, kmscon hasn't been updated in years and has some bugs...
          enable = mkDefault false;
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
          permitRootLogin = mkDefault "no";
          passwordAuthentication = mkDefault false;
        };
      };
    }
    (mkIf config.services.kmscon.enable {
      fonts.fonts = with pkgs; [
        (nerdfonts.override {
          fonts = [ "SourceCodePro" ];
        })
      ];
    })
  ];

  meta.buildDocsInSandbox = false;
}
