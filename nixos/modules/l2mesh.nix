{ lib, config, vpns, ... }:
let
  inherit (builtins) any attrValues;
  inherit (lib) optionalString mapAttrsToList concatStringsSep concatMapStringsSep filterAttrs mkIf mkMerge;
  inherit (lib.my) isIPv6 mkOpt';

  vxlanPort = 4789;

  selfName = config.system.name;
  memberMeshes = filterAttrs (_: c: c.peers ? "${selfName}") vpns.l2;

  info = mesh: {
    ownAddr = mesh.peers."${selfName}".addr;
    otherPeers = filterAttrs (n: _: n != selfName) mesh.peers;
  };

  mkNetConfig = name: mesh: with info mesh; {
    netdevs."30-l2mesh-${name}" = {
      netdevConfig = {
        Name = mesh.interface;
        Kind = "vxlan";
      };
      vxlanConfig = {
        VNI = mesh.vni;
        Local = ownAddr;
        MacLearning = true;
        DestinationPort = vxlanPort;
        PortRange = "${toString vxlanPort}-${toString (vxlanPort + 1)}";
        Independent = true;
      };
    };
    networks."90-l2mesh-${name}" = {
      matchConfig.Name = mesh.interface;
      linkConfig.MTUBytes =
      let
        espOverhead =
          if (!mesh.security.enable) then 0
          else
            # UDP encap + SPI + seq + IV + pad / header + ICV
            (if mesh.udpEncapsulation then 8 else 0) + 4 + 4 + (if mesh.security.encrypt then 8 else 0) + 2 + 16;
        # UDP + VXLAN + Ethernet + L3 (IPv4/IPv6)
        overhead = espOverhead + 8 + 8 + 14 + mesh.l3Overhead;
      in
      toString (mesh.baseMTU - overhead);

      bridgeFDBs = mapAttrsToList (n: peer: {
        bridgeFDBConfig = {
          MACAddress = "00:00:00:00:00:00";
          Destination = peer.addr;
        };
      }) otherPeers;
    };
  };

  vxlanAllow = vni: "udp dport ${toString vxlanPort} @th,96,24 ${toString vni} accept";
  mkFirewallConfig = name: mesh: with info mesh;
  let
    netProto = if (isIPv6 ownAddr) then "ip6" else "ip";
  in
  ''
    table inet filter {
      chain l2mesh-${name} {
        ${optionalString mesh.security.enable ''
          udp dport isakmp accept
          ${if mesh.udpEncapsulation then ''
            udp dport ipsec-nat-t accept
          '' else ''
            meta l4proto esp accept
          ''}
        ''}
        ${optionalString (!mesh.security.enable) (vxlanAllow mesh.vni)}
        return
      }
      chain input {
        ${netProto} daddr ${ownAddr} ${netProto} saddr { ${concatStringsSep ", " (mapAttrsToList (_: p: p.addr) otherPeers)} } jump l2mesh-${name}
      }
    }
  '';

  mkLibreswanConfig = name: mesh: with info mesh; {
    enable = true;
    connections = mkMerge (mapAttrsToList
      (pName: peer: {
        "l2mesh-${name}-${pName}" = ''
          keyexchange=ike
          hostaddrfamily=ipv${if mesh.ipv6 then "6" else "4"}
          type=transport

          left=${ownAddr}
          leftprotoport=udp/${toString vxlanPort}
          right=${peer.addr}
          rightprotoport=udp/${toString vxlanPort}
          rightupdown=

          auto=start
          authby=secret
          phase2=esp
          esp=${if mesh.security.encrypt then "aes_gcm256" else "null-sha256"}
          ikev2=yes
          modecfgpull=no
          encapsulation=${if mesh.udpEncapsulation then "yes" else "no"}
        '';
      })
    otherPeers);
  };
  genSecrets = name: mesh: with info mesh; concatMapStringsSep "\n" (p: ''
    echo "${ownAddr} ${p.addr} : PSK \"$(< "${config.my.vpns.l2.pskFiles.${name}}")\"" >> /run/l2mesh.secrets
  '') (attrValues otherPeers);
  anySecurity = any (c: c.security.enable) (attrValues memberMeshes);
in
{
  options = {
    my.vpns.l2 = with lib.types; {
      pskFiles = mkOpt' (attrsOf str) { } "PSK files for secured meshes.";
    };
  };

  config = {
    systemd.network = mkMerge (mapAttrsToList mkNetConfig memberMeshes);

    environment.etc."ipsec.d/l2mesh.secrets" = mkIf anySecurity {
      source = "/run/l2mesh.secrets";
    };
    systemd.services.ipsec = mkIf anySecurity {
      preStart = ''
        oldUmask="$(umask)"
        umask 006

        > /run/l2mesh.secrets
        ${concatStringsSep "\n" (mapAttrsToList genSecrets memberMeshes)}

        umask "$oldUmask"
      '';
    };

    services.libreswan = mkMerge (mapAttrsToList mkLibreswanConfig (filterAttrs (_: c: c.security.enable) memberMeshes));
    my.firewall.extraRules = concatStringsSep "\n" (mapAttrsToList mkFirewallConfig (filterAttrs (_: c: c.firewall) memberMeshes));
  };
}
