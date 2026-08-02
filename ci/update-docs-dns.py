#!/usr/bin/env python3
"""Render docs/reference/dns.md from live authoritative DNS zone transfers.

The authoritative servers are queried directly over AXFR. Records owned by Kea are
identified by DHCID records and omitted together with their forward and reverse data.
"""

import argparse
import ipaddress
import re
import socket
import sys
from dataclasses import dataclass
from pathlib import Path

import dns.exception
import dns.name
import dns.query
import dns.resolver
import dns.rdatatype


OUT = Path("docs/reference/dns.md")
DEFAULT_PORT = 53
IGNORED_TYPES = {"DHCID", "SOA"}
POWERDNS_ALIAS = 65401
POWERDNS_LUA = 65402


@dataclass(frozen=True)
class Record:
    zone: str
    owner: str
    type: str
    value: str


def normalize_name(name: str) -> str:
    return name.rstrip(".").lower()


def record_data(rdtype: int, rdata) -> tuple[str, str]:
    if rdtype == POWERDNS_ALIAS:
        target, _used = dns.name.from_wire(rdata.data, 0)
        return "ALIAS", target.to_text()
    if rdtype == POWERDNS_LUA:
        logical_type = int.from_bytes(rdata.data[:2], byteorder="big")
        return "LUA", dns.rdatatype.to_text(logical_type)
    return dns.rdatatype.to_text(rdtype), rdata.to_text()


def server_addresses(server: str, port: int) -> list[str]:
    addresses = []
    try:
        for result in socket.getaddrinfo(server, port, type=socket.SOCK_STREAM):
            address = result[4][0]
            if address not in addresses:
                addresses.append(address)
    except socket.gaierror as error:
        raise RuntimeError(f"cannot resolve nameserver {server}: {error}") from error
    return addresses


def transfer(server: str, port: int, zone: str) -> list[Record]:
    addresses = server_addresses(server, port)

    errors = []
    for address in addresses:
        try:
            records = []
            for message in dns.query.xfr(
                address, zone, port=port, lifetime=60, relativize=False
            ):
                for rrset in message.answer:
                    for rdata in rrset:
                        record_type, value = record_data(rrset.rdtype, rdata)
                        records.append(
                            Record(
                                zone=normalize_name(zone),
                                owner=normalize_name(rrset.name.to_text()),
                                type=record_type,
                                value=value,
                            )
                        )
            if not any(record.type == "SOA" for record in records):
                raise RuntimeError("transfer returned no SOA record")
            return records
        except (dns.exception.DNSException, OSError, RuntimeError) as error:
            errors.append(f"{address}: {error}")
    raise RuntimeError(f"AXFR of {zone} from {server} failed ({'; '.join(errors)})")


def system_nameservers(domain: str) -> list[str]:
    try:
        answer = dns.resolver.resolve(domain, "NS", lifetime=30)
    except dns.exception.DNSException as error:
        message = f"cannot discover authoritative servers for {domain}: {error}"
        raise RuntimeError(message) from error
    return [rdata.target.to_text() for rdata in answer]


def nameservers_via(server: str, port: int, domain: str) -> list[str]:
    errors = []
    for address in server_addresses(server, port):
        resolver = dns.resolver.Resolver(configure=False)
        resolver.nameservers = [address]
        resolver.port = port
        try:
            answer = resolver.resolve(domain, "NS", lifetime=15, search=False)
            return [rdata.target.to_text() for rdata in answer]
        except dns.exception.DNSException as error:
            errors.append(f"{address}: {error}")
    raise RuntimeError(f"NS query for {domain} via {server} failed ({'; '.join(errors)})")


def discover_nameservers(domains: list[str], port: int) -> dict[str, list[str]]:
    discovered = {}
    unresolved = {}
    candidates = []
    for domain in domains:
        try:
            servers = system_nameservers(domain)
            discovered[domain] = servers
            for server in servers:
                if server not in candidates:
                    candidates.append(server)
        except RuntimeError as error:
            unresolved[domain] = [str(error)]

    for domain, errors in list(unresolved.items()):
        for server in candidates:
            try:
                discovered[domain] = nameservers_via(server, port, domain)
                del unresolved[domain]
                break
            except RuntimeError as error:
                errors.append(str(error))

    if unresolved:
        details = "; ".join(
            f"{domain}: {'; '.join(errors)}" for domain, errors in unresolved.items()
        )
        raise RuntimeError(details)
    return discovered


def transfer_domain(
    port: int, domain: str, servers: list[str], fallback: list[str] = ()
) -> list[Record]:
    # A zone may be delegated publicly to servers that refuse AXFR (e.g. HE serving
    # reverse DNS) while our own authoritative servers, discovered for other zones,
    # will transfer it. Try the delegated servers first, then fall back to those.
    ordered = list(servers)
    for server in fallback:
        if server not in ordered:
            ordered.append(server)

    errors = []
    for server in ordered:
        try:
            return transfer(server, port, domain)
        except RuntimeError as error:
            errors.append(str(error))
    raise RuntimeError(f"no authoritative server allowed AXFR for {domain} ({'; '.join(errors)})")


def dynamic_names(records: list[Record]) -> set[str]:
    return {record.owner for record in records if record.type == "DHCID"}


def dynamic_addresses(records: list[Record], names: set[str]) -> set[str]:
    return {
        record.value.rstrip(".").lower()
        for record in records
        if record.owner in names and record.type in {"A", "AAAA"}
    }


def reverse_address(owner: str) -> str | None:
    if owner.endswith(".in-addr.arpa"):
        labels = owner.removesuffix(".in-addr.arpa").split(".")
        if len(labels) != 4:
            return None
        try:
            return str(ipaddress.IPv4Address(".".join(reversed(labels))))
        except ValueError:
            return None

    if owner.endswith(".ip6.arpa"):
        labels = owner.removesuffix(".ip6.arpa").split(".")
        if len(labels) != 32:
            return None
        try:
            value = int("".join(reversed(labels)), 16)
            return str(ipaddress.IPv6Address(value))
        except ValueError:
            return None
    return None


def static_records(records: list[Record]) -> list[Record]:
    names = dynamic_names(records)
    addresses = dynamic_addresses(records, names)
    static = []
    for record in records:
        if record.type in IGNORED_TYPES or record.owner in names:
            continue
        if record.type == "PTR":
            target = normalize_name(record.value.split()[0])
            address = reverse_address(record.owner)
            if target in names or address in addresses:
                continue
        static.append(record)
    return static


def relative_name(owner: str, zone: str) -> str:
    if owner == zone:
        return "@"
    suffix = f".{zone}"
    return owner[: -len(suffix)] if owner.endswith(suffix) else owner


def markdown_code(value: str) -> str:
    escaped = value.replace("|", "\\|")
    return f"`{escaped}`"


def display_record(record: Record) -> tuple[str, str]:
    if record.type != "LUA":
        return record.type, record.value
    return f"{record.value} (LUA)", "generated at query time"


def render_forward(domain: str, records: list[Record]) -> list[str]:
    domain = normalize_name(domain)
    rows = []
    for record in records:
        if record.zone != domain or record.type == "PTR":
            continue
        record_type, value = display_record(record)
        rows.append((relative_name(record.owner, record.zone), record_type, value))
    rows.sort(key=lambda row: (row[0] != "@", row[0], row[1], row[2]))

    lines = ["| Name | Type | Value |", "|---|---|---|"]
    lines.extend(
        f"| {markdown_code(name)} | {markdown_code(record_type)} | {markdown_code(value)} |"
        for name, record_type, value in rows
    )
    return lines


def render_reverse(domain: str, records: list[Record]) -> list[str]:
    domain = normalize_name(domain)
    rows = []
    for record in records:
        if record.zone != domain or record.type != "PTR":
            continue
        rows.append((reverse_address(record.owner) or record.owner, record.value))
    rows.sort(key=lambda row: ipaddress.ip_address(row[0]))

    lines = ["| Address | Name |", "|---|---|"]
    lines.extend(
        f"| {markdown_code(address)} | {markdown_code(name)} |" for address, name in rows
    )
    return lines


def is_reverse(domain: str) -> bool:
    domain = normalize_name(domain)
    return domain.endswith(".in-addr.arpa") or domain.endswith(".ip6.arpa")


def rendered_zones(transferred: list[tuple[str, list[Record]]]) -> dict[str, list[str]]:
    records = static_records([record for _domain, zone in transferred for record in zone])
    rendered = {}
    for domain, _raw_records in transferred:
        if is_reverse(domain):
            rendered[normalize_name(domain)] = render_reverse(domain, records)
        else:
            rendered[normalize_name(domain)] = render_forward(domain, records)
    return rendered


def update_target(transferred: list[tuple[str, list[Record]]], target: Path) -> bool:
    rendered = rendered_zones(transferred)
    text = target.read_text()
    lines = text.splitlines()
    marker_re = re.compile(r"^<!--\s*dns:\s*(\S+)\s*-->$")
    found = set()
    output = []
    i = 0
    while i < len(lines):
        match = marker_re.match(lines[i].strip())
        if not match or normalize_name(match.group(1)) not in rendered:
            output.append(lines[i])
            i += 1
            continue

        domain = normalize_name(match.group(1))
        end = i + 1
        while end < len(lines) and lines[end].strip() != "<!-- dns-end -->":
            end += 1
        if end >= len(lines):
            raise RuntimeError(f"missing <!-- dns-end --> for {domain}")

        output.extend(
            [
                lines[i],
                "<!-- dns-start -->",
                *rendered[domain],
                "<!-- dns-end -->",
            ]
        )
        found.add(domain)
        i = end + 1

    missing = rendered.keys() - found
    if missing:
        raise RuntimeError(f"missing DNS markers for: {', '.join(sorted(missing))}")

    new = "\n".join(output) + "\n"
    if new == text:
        return False
    target.write_text(new)
    return True


def main() -> int:
    parser = argparse.ArgumentParser(prog="update-docs-dns", description=__doc__)
    parser.add_argument("domain", nargs="+", help="DNS zone to transfer")
    parser.add_argument("--port", type=int, default=DEFAULT_PORT)
    parser.add_argument("--output", type=Path, default=OUT)
    args = parser.parse_args()

    try:
        nameservers = discover_nameservers(args.domain, args.port)
        fallback = []
        for servers in nameservers.values():
            for server in servers:
                if server not in fallback:
                    fallback.append(server)
        transferred = [
            (domain, transfer_domain(args.port, domain, nameservers[domain], fallback))
            for domain in args.domain
        ]
    except RuntimeError as error:
        print(f"update-docs-dns: {error}", file=sys.stderr)
        return 1

    try:
        changed = update_target(transferred, args.output)
    except (OSError, RuntimeError) as error:
        print(f"update-docs-dns: {error}", file=sys.stderr)
        return 1
    if changed:
        print(f"updated {args.output}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
