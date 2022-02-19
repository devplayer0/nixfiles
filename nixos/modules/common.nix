{ lib, pkgs, pkgs', inputs, options, config, ... }:
let
  inherit (builtins) attrValues;
  inherit (lib) flatten optional mkIf mkDefault mkMerge mkOption mkAliasDefinitions;
  inherit (lib.my) mkOpt' mkBoolOpt' dummyOption mkDefault';
in
{
  options = with lib.types; {
    my = {
      # TODO: Move to separate module
      user = {
        enable = mkBoolOpt' true "Whether to create a primary user.";
        config = mkOption {
          type = options.users.users.type.nestedTypes.elemType;
          default = { };
          description = "User definition (as `users.users.*`).";
        };
        homeConfig = mkOption {
          type = options.home-manager.users.type.nestedTypes.elemType;
          default = { };
          # Prevent docs traversing into all of home-manager
          visible = "shallow";
          description = "Home configuration (as `home-manager.users.*`)";
        };
      };

      ssh = {
        strictModes = mkBoolOpt' true
          ("Specifies whether sshd(8) should check file modes and ownership of the user's files and home directory "+
          "before accepting login.");
      };
    };

    # Only present in >=22.05, so forward declare
    documentation.nixos.options.warningsAreErrors = dummyOption;
  };

  config = mkMerge [
    (let
      cfg = config.my.user;
      user' = cfg.config;
    in mkIf cfg.enable
    {
      my = {
        user = {
          config = {
            name = mkDefault' "dev";
            isNormalUser = true;
            uid = mkDefault 1000;
            extraGroups = mkDefault [ "wheel" ];
            password = mkDefault "hunter2"; # TODO: secrets...
            openssh.authorizedKeys.keyFiles = [ lib.my.authorizedKeys ];
          };
          # In order for this option to evaluate on its own, home-manager expects the `name` (which is derived from the
          # parent attr name) to be the users name, aka `home-manager.users.<name>`
          homeConfig = { _module.args.name = lib.mkForce user'.name; };
        };

        deploy.authorizedKeys = mkDefault user'.openssh.authorizedKeys;
      };

        # mkAliasDefinitions will copy the unmerged defintions to allow the upstream submodule to deal with
      users.users.${user'.name} = mkAliasDefinitions options.my.user.config;

      # NOTE: As the "outermost" module is still being evaluated in NixOS land, special params (e.g. pkgs) won't be
      # passed to it
      home-manager.users.${user'.name} = mkAliasDefinitions options.my.user.homeConfig;
    })
    {
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
        package = pkgs'.unstable.nixVersions.stable;
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
        domain = mkDefault "int.nul.ie";
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
          permitRootLogin = mkDefault "no";
          passwordAuthentication = mkDefault false;
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
