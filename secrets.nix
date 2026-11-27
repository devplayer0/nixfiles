let
  self = getFlake (toString ./.);
  inherit (self) lib;

  inherit (builtins) mapAttrs readFile getFlake;
  inherit (lib) fileContents optional flatten zipAttrsWith nameValuePair mapAttrs' mapAttrsToList;

  secretPath = p: "secrets/${p}.age";

  defaultKeys = [
    (fileContents .keys/dev.pub)
    # `slop-broker` on `palace`, which changes secrets for agents
    (fileContents .keys/slop-broker.pub)
  ];
  secretKeys =
    zipAttrsWith
      (_: keys: flatten (keys ++ defaultKeys))
      (mapAttrsToList
        # The comment names the key in `slop-broker` approvals; age ignores it
        (name: c: let cfg = c.config.my.secrets; in mapAttrs'
          (f: _: nameValuePair
            (secretPath f)
            (optional (cfg.key != null) "${cfg.key} ${name}"))
          cfg.files)
        self.nixosConfigurations);
in
mapAttrs (_: keys: { publicKeys = keys; }) secretKeys
