{ lib }: 
let
  inherit (builtins) filter;
  inherit (lib)
    concatStringsSep concatMapStringsSep mapAttrsToList filterAttrs flatten optionalString;
in
rec {
  genRecords =
    {
      allAssignments,
      domain,
      names,
      f,
    }:
    concatStringsSep
      "\n"
      (filter
        (s: s != "")
        (flatten
          (map
            (name: (mapAttrsToList
              (_: as: f as."${name}")
              (filterAttrs
                (_: as: as ? "${name}" && as."${name}".domain == domain && as."${name}".visible)
                allAssignments)))
            names)));

  fwdRecords =
    {
      allAssignments,
      domain,
      names,
    }:
    genRecords {
      inherit allAssignments domain names;
      f = a: ''
        ${a.name} IN A ${a.ipv4.address}
        ${optionalString (a.ipv6.address != null) "${a.name} IN AAAA ${a.ipv6.address}"}
        ${concatMapStringsSep "\n" (alt: "${alt} IN CNAME ${a.name}") a.altNames}
      '';
    };
  ptrRecords =
    {
      allAssignments,
      domain,
      names,
      ndots,
    }:
    genRecords {
      inherit allAssignments domain names;
      f = a:
        optionalString
          a.ipv4.genPTR
          ''@@PTR:${a.ipv4.address}:${toString ndots}@@ IN PTR ${a.name}.${domain}.'';
    };
  ptr6Records =
    {
      allAssignments,
      domain,
      names,
      ndots,
    }:
    genRecords {
      inherit allAssignments domain names;
      f = a:
        optionalString
          (a.ipv6.address != null && a.ipv6.genPTR)
          ''@@PTR:${a.ipv6.address}:${toString ndots}@@ IN PTR ${a.name}.${domain}.'';
    };
}
