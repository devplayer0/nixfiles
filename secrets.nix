let
  self = getFlake (toString ./.);
  inherit (self) lib;

  inherit (builtins) mapAttrs attrValues readFile getFlake;
  inherit (lib) fileContents optional flatten zipAttrsWith nameValuePair mapAttrs';

  secretPath = p: "secrets/${p}.age";

  defaultKeys = [
    (fileContents .keys/dev.pub)
  ];
  secretKeys =
    zipAttrsWith
      (_: keys: flatten (keys ++ defaultKeys))
      (map
        (c: let cfg = c.config.my.secrets; in mapAttrs'
          (f: _: nameValuePair
            (secretPath f)
            (optional (cfg.key != null) cfg.key))
          cfg.files)
        (attrValues self.nixosConfigurations));
in
mapAttrs (_: keys: { publicKeys = keys; }) secretKeys
