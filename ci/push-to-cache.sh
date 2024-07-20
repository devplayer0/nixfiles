#!/bin/sh
set -e

REMOTE_STORE=/var/lib/harmonia
SSH_HOST="harmonia@object-ctr.ams1.int.nul.ie"
SSH_KEY=/tmp/harmonia.key
STORE_URI="ssh-ng://$SSH_HOST?ssh-key=$SSH_KEY&remote-store=$REMOTE_STORE"

remote_cmd() {
  ssh -i "$SSH_KEY" "$SSH_HOST" env HOME=/run/harmonia NIX_REMOTE="$REMOTE_STORE" "$@"
}

umask_old=$(umask)
umask 0066
echo "$HARMONIA_SSH_KEY" | base64 -d > "$SSH_KEY"
umask $umask_old

mkdir -p ~/.ssh
cp ci/known_hosts ~/.ssh/
path="$1"

echo "Pushing $path to cache..."
nix copy --no-check-sigs --to "$STORE_URI" "$path"

echo "Updating profile..."
remote_cmd nix-env -p "$REMOTE_STORE"/nix/var/nix/profiles/nixfiles --set "$path"

echo "Collecting garbage..."
remote_cmd nix-collect-garbage --delete-older-than 30d
