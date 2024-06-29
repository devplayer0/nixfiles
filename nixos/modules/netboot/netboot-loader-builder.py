#! @python3@/bin/python3 -B
# Based on `nixos/modules/system/boot/loader/systemd-boot/systemd-boot-builder.py`
import argparse
import datetime
import glob
import os
import os.path
import shutil
import subprocess
import sys
import json
from typing import NamedTuple, Dict, List
from dataclasses import dataclass

BOOT_MOUNT_POINT = '/boot'
STORE_DIR = 'nix'

# These values will be replaced with actual values during the package build
BOOTSPEC_TOOLS = '@bootspecTools@'
NIX = '@nix@'
DISTRO_NAME = '@distroName@'
SYSTEM_NAME = '@systemName@'
CONFIGURATION_LIMIT = int('@configurationLimit@')
CHECK_MOUNTPOINTS = "@checkMountpoints@"

@dataclass
class BootSpec:
  init: str
  initrd: str
  kernel: str
  kernelParams: List[str]
  label: str
  system: str
  toplevel: str
  specialisations: Dict[str, 'BootSpec']
  sortKey: str
  initrdSecrets: str | None = None

class SystemIdentifier(NamedTuple):
  profile: str | None
  generation: int
  specialisation: str | None

def copy_if_not_exists(source: str, dest: str) -> None:
  if not os.path.exists(dest):
    shutil.copyfile(source, dest)

def generation_dir(profile: str | None, generation: int) -> str:
  if profile:
    return f'/nix/var/nix/profiles/system-profiles/{profile}-{generation}-link'
  else:
    return f'/nix/var/nix/profiles/system-{generation}-link'

def system_dir(i: SystemIdentifier) -> str:
  d = generation_dir(i.profile, i.generation)
  if i.specialisation:
    return os.path.join(d, 'specialisation', i.specialisation)
  else:
    return d

def entry_key(i: SystemIdentifier) -> str:
  pieces = [
    'nixos',
    i.profile or None,
    'generation',
    str(i.generation),
    f'specialisation-{i.specialisation}' if i.specialisation else None,
  ]
  return '-'.join(p for p in pieces if p)

def bootspec_from_json(bootspec_json: Dict) -> BootSpec:
  specialisations = bootspec_json['org.nixos.specialisation.v1']
  specialisations = {k: bootspec_from_json(v) for k, v in specialisations.items()}
  systemdBootExtension = bootspec_json.get('org.nixos.systemd-boot', {})
  sortKey = systemdBootExtension.get('sortKey', 'nixos')
  return BootSpec(
    **bootspec_json['org.nixos.bootspec.v1'],
    specialisations=specialisations,
    sortKey=sortKey
  )

bootspecs = {}
def get_bootspec(profile: str | None, generation: int) -> BootSpec:
  k = (profile, generation)
  if k in bootspecs:
    return bootspecs[k]

  system_directory = system_dir(SystemIdentifier(profile, generation, None))
  boot_json_path = os.path.realpath(f'{system_directory}/boot.json')
  if os.path.isfile(boot_json_path):
    boot_json_f = open(boot_json_path, 'r')
    bootspec_json = json.load(boot_json_f)
  else:
    boot_json_str = subprocess.check_output([
      f'{BOOTSPEC_TOOLS}/bin/synthesize',
      '--version',
      '1',
      system_directory,
      '/dev/stdout',
    ],
    universal_newlines=True)
    bootspec_json = json.loads(boot_json_str)

  bs = bootspec_from_json(bootspec_json)
  bootspecs[k] = bs
  return bs

def copy_from_file(file: str, dry_run: bool = False) -> str:
  store_file_path = os.path.realpath(file)
  suffix = os.path.basename(store_file_path)
  store_dir = os.path.basename(os.path.dirname(store_file_path))
  dst_path = f'/{STORE_DIR}/{store_dir}-{suffix}'
  if not dry_run:
    copy_if_not_exists(store_file_path, f'{BOOT_MOUNT_POINT}{dst_path}')
  return dst_path

MENU_ITEM = 'item {gen_key} {title} Generation {generation} {description}'

BOOT_ENTRY = ''':{gen_key}
kernel ${{server}}/systems/{system_name}{kernel} {kernel_params} boothost=${{boothost}}
initrd ${{server}}/systems/{system_name}{initrd}
boot
'''

def gen_entry(i: SystemIdentifier) -> (str, str):
  bootspec = get_bootspec(i.profile, i.generation)
  if i.specialisation:
    bootspec = bootspec.specialisations[i.specialisation]
  kernel = copy_from_file(bootspec.kernel)
  initrd = copy_from_file(bootspec.initrd)

  gen_key = entry_key(i)
  title = '{name}{profile}{specialisation}'.format(
    name=DISTRO_NAME,
    profile=' [' + i.profile + ']' if i.profile else '',
    specialisation=f' ({i.specialisation})' if i.specialisation else '')

  kernel_params = f'init={bootspec.init} '

  kernel_params = kernel_params + ' '.join(bootspec.kernelParams)
  build_time = int(os.path.getctime(system_dir(i)))
  build_date = datetime.datetime.fromtimestamp(build_time).strftime('%F')

  return MENU_ITEM.format(
    gen_key=gen_key,
    title=title,
    description=f'{bootspec.label}, built on {build_date}',
    generation=i.generation,
  ), BOOT_ENTRY.format(
    gen_key=gen_key,
    generation=i.generation,
    system_name=SYSTEM_NAME,
    kernel=kernel,
    kernel_params=kernel_params,
    initrd=initrd,
  )

def get_generations(profile: str | None = None) -> list[SystemIdentifier]:
  gen_list = subprocess.check_output([
    f'{NIX}/bin/nix-env',
    '--list-generations',
    '-p',
    '/nix/var/nix/profiles/' + ('system-profiles/' + profile if profile else 'system')],
    universal_newlines=True)
  gen_lines = gen_list.split('\n')
  gen_lines.pop()

  configurationLimit = CONFIGURATION_LIMIT
  configurations = [
    SystemIdentifier(
      profile=profile,
      generation=int(line.split()[0]),
      specialisation=None
    )
    for line in gen_lines
  ]
  return configurations[-configurationLimit:]

def remove_old_files(gens: list[SystemIdentifier]) -> None:
  known_paths = []
  for gen in gens:
    bootspec = get_bootspec(gen.profile, gen.generation)
    known_paths.append(copy_from_file(bootspec.kernel, True))
    known_paths.append(copy_from_file(bootspec.initrd, True))
  for path in glob.iglob(f'{BOOT_MOUNT_POINT}/{STORE_DIR}/*'):
    if not path in known_paths and not os.path.isdir(path):
      os.unlink(path)

def get_profiles() -> list[str]:
  if os.path.isdir('/nix/var/nix/profiles/system-profiles/'):
    return [x
      for x in os.listdir('/nix/var/nix/profiles/system-profiles/')
      if not x.endswith('-link')]
  else:
    return []

MENU = '''#!ipxe
# Server hostname option
set boothost ${{66:string}}
set server http://${{boothost}}

:start
menu {distro} boot menu
item --gap -- Generations
{generation_items}
item --gap -- Other
item --key m main Main netboot menu
choose --timeout 5000 --default {menu_default} selected || goto cancel
goto ${{selected}}

:cancel
shell
goto start

:error
echo Booting failed, dropping to shell
shell
goto start

:main
chain ${{server}}/boot.ipxe || goto error
'''

def write_menu(gens: list[SystemIdentifier], default: SystemIdentifier) -> None:
  gen_menu_items = []
  gen_cmds = []

  for g in gens:
    bootspec = get_bootspec(g.profile, g.generation)
    specialisations = [
      SystemIdentifier(profile=g.profile, generation=g.generation, specialisation=s) for s in bootspec.specialisations]
    for i in [g] + specialisations:
      mi, cmds = gen_entry(i)
      gen_menu_items.append(mi)
      gen_cmds.append(cmds)

  menu_file = f'{BOOT_MOUNT_POINT}/menu.ipxe'
  with open(f'{menu_file}.tmp', 'w') as f:
    f.write(MENU.format(
      distro=DISTRO_NAME,
      generation_items='\n'.join(gen_menu_items),
      menu_default=entry_key(default),
    ))

    print(file=f)
    print('\n\n'.join(gen_cmds), file=f)

  os.rename(f'{menu_file}.tmp', menu_file)

def install_bootloader(args: argparse.Namespace) -> None:
  os.makedirs(f'{BOOT_MOUNT_POINT}/{STORE_DIR}', exist_ok=True)

  gens = get_generations()
  for profile in get_profiles():
    gens += get_generations(profile)

  gens = sorted(gens, key=lambda g: entry_key(g), reverse=True)

  remove_old_files(gens)

  for g in gens:
    if os.path.dirname(get_bootspec(g.profile, g.generation).init) == os.path.realpath(args.default_config):
      default = g
      break
  else:
    assert False, 'No default generation found'

  write_menu(gens, default)

def main() -> None:
  parser = argparse.ArgumentParser(description=f'Update {DISTRO_NAME}-related netboot files')
  parser.add_argument('default_config', metavar='DEFAULT-CONFIG', help=f'The default {DISTRO_NAME} config to boot')
  args = parser.parse_args()

  subprocess.check_call(CHECK_MOUNTPOINTS)

  install_bootloader(args)

if __name__ == '__main__':
  main()
