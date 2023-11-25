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

  ifaceA = { pkgs, iface, skipBroadcasts ? [] }:
  let
    extraFilters = concatMapStringsSep " " (b: ''and .broadcast != \"${b}\"'') skipBroadcasts;
    script = pkgs.writeText "if-${iface}-a.lua" ''
      local proc = io.popen("${pkgs.iproute2}/bin/ip -j addr show dev ${iface} | ${pkgs.jq}/bin/jq -r '.[0].addr_info[] | select(.family == \"inet\" and .scope == \"global\" ${extraFilters}).local'", "r")
      assert(proc, "failed to popen")

      local addr_line = proc:read("*l")
      assert(proc:close(), "command failed")
      assert(addr_line, "no output from command")

      return addr_line
    '';
  in
    ''A "dofile('${script}')"'';

  lookupIP = { pkgs, hostname, server, type ? "A" }:
  let
    script = pkgs.writeScript "drill-${hostname}-${server}.lua" ''
      local proc = io.popen("${pkgs.ldns}/bin/drill -Q @${server} ${hostname} ${type}", "r")
      assert(proc, "failed to popen")

      local addr_line = proc:read("*l")
      assert(proc:close(), "command failed")
      assert(addr_line, "no output from command")

      return addr_line
    '';
  in
    ''${type} "dofile('${script}')"'';
}
