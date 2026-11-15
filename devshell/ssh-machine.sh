set -euo pipefail

refresh=false

if [[ ${1:-} == --refresh ]]; then
  refresh=true
  shift
fi

if [[ $# == 0 && $refresh == false ]] || [[ ${1:-} == --help ]]; then
  echo 'Usage: ssh-machine [--refresh] <name> [cmd ...]'
  echo '       ssh-machine --refresh'
  exit 0
fi

# Resolve deploy's relative identity path from the checkout root.
cd "$PRJ_ROOT"

cache_dir=.cache/ssh-machine
cache=$cache_dir/connections.json

fingerprint() {
  {
    git rev-parse HEAD &&
    git diff --no-ext-diff --no-textconv --binary HEAD -- &&
    git diff --no-ext-diff --no-textconv --binary --cached --
  } | sha256sum | cut -d ' ' -f 1
}

key=$(fingerprint)

if [[ $refresh == true ]] || ! jq -e --arg key "$key" \
  '.fingerprint == $key and (.nodes | type == "object")' "$cache" >/dev/null 2>&1; then
  mkdir -p "$cache_dir"
  tmp=$(mktemp "$cache_dir/.connections.XXXXXXXX")
  trap 'rm -f "$tmp"' EXIT

  echo 'Refreshing ssh-machine connection cache…' >&2

  # Interpolation here belongs to Nix, not the shell.
  # shellcheck disable=SC2016
  nix eval --json .#deploy --apply '
    d: builtins.mapAttrs (_: n:
      d.sshOpts ++ n.sshOpts ++ [ "${n.sshUser}@${n.hostname}" ]
    ) d.nodes
  ' > "$tmp"

  if [[ $(fingerprint) != "$key" ]]; then
    echo 'Checkout changed during evaluation; retry ssh-machine.' >&2
    exit 1
  fi

  payload=$(jq -c --arg key "$key" '{fingerprint: $key, nodes: .}' "$tmp")
  printf '%s\n' "$payload" > "$tmp"
  mv -f "$tmp" "$cache"
  trap - EXIT
fi

[[ $# -gt 0 ]] || exit 0

name=$1
shift

# deploy-rs mangles home configuration names containing @.
node=${name//@/-at-}

args=$(jq -ce --arg node "$node" '
  .nodes | if has($node) then .[$node]
  else error("Unknown deploy node: " + $node) end
' "$cache")

mapfile -d '' -t ssh_args < <(jq -j '.[] | ., "\u0000"' <<< "$args")

exec ssh "${ssh_args[@]}" "$@"
