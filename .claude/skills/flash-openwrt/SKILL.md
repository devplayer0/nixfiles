---
name: flash-openwrt
description: >-
  Flash a flake-built OpenWrt image onto one of the OpenWrt boxes (currently fergal): build the
  image, pre-flight the box, back up its config, validate and stage the image, run sysupgrade, and
  verify what came back. Use when the user wants to flash, reflash, upgrade or sysupgrade an OpenWrt
  box, or after changing its baked-in package list.
---

# Flash an OpenWrt box

The canonical, agent-agnostic procedure lives in the repo at
[`docs/openwrt-flash.md`](../../../docs/openwrt-flash.md). Read it and follow the phases in order.

Key reminders (see the doc for the full steps):

- **Stop at the ⏸ before Phase 5.** Flashing reboots the box and cannot be interrupted partway.
  Confirm with the user, and confirm a serial console is reachable, *before* writing anything.
- **Packages are baked into the image**, so a package change means a reflash. Edit the box's list in
  [`openwrt/default.nix`](../../../openwrt/default.nix), rebuild, and check the built `.manifest` —
  a package name that doesn't exist is not a build error, it just isn't in the image.
- **`scp` does not work** on these boxes (no `sftp-server`). Move files with
  `ssh <box> 'cat > /dev/…' < file` and `ssh <box> 'cat …' > file`.
- **Detach the upgrade with `setsid`**, not `nohup` (absent on busybox). `sysupgrade` kills the SSH
  session mid-run, and an attached run dies with it — possibly after the firmware is erased.
- **Never reach for `sysupgrade -c`.** It needs `/overlay/upper/etc` and aborts *after* erasing the
  firmware when that is missing, which is exactly the initramfs case. Plain `sysupgrade` already
  keeps everything in `/lib/upgrade/keep.d/`.
- **Poll SSH to detect the reboot, never ping.** Successful pings return in milliseconds, so a
  "wait for down" loop completes instantly and reports nonsense. Sleep between probes; expect about
  three minutes.
- **Verify after**, don't assume: revision, management address, package count against the manifest,
  and that the new packages are present and running.

The images are declared in [`openwrt/default.nix`](../../../openwrt/default.nix); background on the
outputs and the pinned package feeds is in
[`docs/deployment.md`](../../../docs/deployment.md#openwrt-images).
