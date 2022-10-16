{ lib, pkgs, config, vpns, ... }:
let
  inherit (lib) optionalString mapAttrsToList concatStringsSep filterAttrs mkIf mkMerge;
  inherit (lib.my) isIPv6;

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
        Independent = true;
      };
    };
    networks."90-l2mesh-${name}" = {
      matchConfig.Name = mesh.interface;
      extraConfig = concatStringsSep "\n" (mapAttrsToList (n: peer: ''
        [BridgeFDB]
        MACAddress=00:00:00:00:00:00
        Destination=${peer.addr}
      '') otherPeers);
    };
  };

  mkLibreswanConfig = name: mesh: with info mesh; {
    enable = true;
    # TODO: finish this...
    connections."l2mesh-${name}" = ''
      keyexchange=ike
      type=transport
      left=${ownAddr}

      auto=start
      phase2=esp
      ikev2=yes
    '';
  };

  mkFirewallConfig = name: mesh: with info mesh;
  let
    netProto = if (isIPv6 ownAddr) then "ip6" else "ip";
  in
  ''
    table inet filter {
      chain l2mesh-${name} {
        ${optionalString mesh.security.enable "meta l4proto esp accept"}
        udp dport ${toString vxlanPort} @th,96,24 ${toString mesh.vni} accept
        return
      }
      chain input {
        ${netProto} daddr ${ownAddr} ${netProto} saddr { ${concatStringsSep ", " (mapAttrsToList (_: p: p.addr) otherPeers)} } jump l2mesh-${name}
      }
    }
  '';
in
{
  config = {
    systemd.network = mkMerge (mapAttrsToList mkNetConfig memberMeshes);
    # TODO: finish this...
    #services.libreswan = mkMerge (mapAttrsToList mkLibreswanConfig (filterAttrs (_: c: c.security.enable) memberMeshes));
    my.firewall.extraRules = concatStringsSep "\n" (mapAttrsToList mkFirewallConfig (filterAttrs (_: c: c.firewall) memberMeshes));
  };
}
