# Flashing an OpenWrt box

Guided procedure for putting a flake-built OpenWrt image onto a box. The images themselves are
declared in [`openwrt/default.nix`](../openwrt/default.nix) and described in
[`deployment.md`](deployment.md#openwrt-images); the boxes are listed on their site pages (today
that is [fergal](sites/home/switches.md#fergal-the-openwrt-switch)).

Packages are baked into the image, so this runs whenever the package list changes — not only for
version upgrades. Work through the phases in order; ⏸ marks the point to stop and confirm.

## Phase 1 — Build

```sh
nix build .#openwrt-<box>
```

The result holds the `-squashfs-sysupgrade.bin` to flash, plus a `.manifest` listing every package
in the image and an SBOM. Check the manifest for the packages the change was meant to add — an
unknown package name is not an error at build time, it just silently isn't there.

## Phase 2 — Pre-flight

Confirm on the box:

```sh
grep -E 'RELEASE|REVISION' /etc/openwrt_release   # what is running now
mount | grep -E ' / | /overlay | /rom '           # flash or RAM? (see below)
uci get network.lan.ipaddr                        # will it come back reachable?
cat /lib/upgrade/keep.d/*                         # what survives the flash
df -h /tmp                                        # room for the image
```

**Flash or RAM matters.** A box booted normally shows a squashfs `/rom` plus a jffs2 `/overlay`;
one booted from an initramfs has `/` on tmpfs. The initramfs case has its own hazards — see
[Flashing from an initramfs](sites/home/switches.md#flashing-notes).

**Check the address is in UCI**, not just present on the interface. An address added by hand with
`ip` disappears on reboot and the box comes back unreachable.

`keep.d` normally lists `/etc/config/`, `/etc/dropbear/authorized_keys` and the dropbear host keys,
so an ordinary flash preserves both access and identity. Verify rather than assume — losing
`authorized_keys` on a box reachable only over SSH means a serial console recovery.

## Phase 3 — Back up

```sh
sysupgrade -b /tmp/<box>-config-backup.tar.gz
```

Fetch it with `ssh <box> 'cat /tmp/…' > local.tar.gz`. **`scp` does not work** — these boxes have no
`/usr/libexec/sftp-server`, so it fails with `Connection closed`. (`scp -O` forces the legacy
protocol if you prefer it.)

For a box being flashed off its **vendor** firmware for the first time, back up the whole flash
first — the vendor partitions hold per-unit MAC addresses and licence data that cannot be
regenerated. See [fergal's flash layout](sites/home/switches.md#flash-layout).

## Phase 4 — Stage and validate

```sh
ssh <box> 'cat > /tmp/sysupgrade.bin' < <image>.bin
ssh <box> 'sha256sum /tmp/sysupgrade.bin; sysupgrade -T /tmp/sysupgrade.bin'
```

Compare the sha256 against the local file, and require `sysupgrade -T` to exit 0. `-T` validates the
image and its device-compatibility metadata without writing anything, which is the last cheap chance
to catch a wrong-profile image.

## Phase 5 — Flash ⏸

Confirm before this point. It reboots the box and is not interruptible.

```sh
ssh <box> 'setsid sh -c "sleep 2; sysupgrade -v /tmp/sysupgrade.bin" \
  </dev/null >/tmp/upgrade.log 2>&1 & echo detached'
```

**Detaching matters.** `sysupgrade` kills the SSH session partway through; without `setsid` the
upgrade dies with it, potentially after the flash has been erased. `nohup` is not available on these
boxes' busybox — use `setsid`.

Plain `sysupgrade` keeps the config in `keep.d`. Do not reach for `-c` out of caution: it needs
`/overlay/upper/etc` and aborts *after* erasing the firmware if that is missing.

## Phase 6 — Wait and verify

Poll SSH, not ping. A successful ping returns in milliseconds, so a naive "wait for it to go down"
loop finishes before the box has even started rebooting. Sleep between probes and wait on something
that only succeeds once userspace is up:

```sh
for i in $(seq 1 40); do
  sleep 15
  ssh -o ConnectTimeout=5 -o BatchMode=yes <box> 'grep REVISION /etc/openwrt_release' && break
done
```

Expect roughly three minutes. Then confirm the revision changed, the management address returned,
the package count matches the manifest, and the new packages are actually present and running.
Connecting without host-key overrides also confirms the host keys survived.

If the box does not return, it needs the serial console — have that confirmed as reachable *before*
Phase 5, not after.
