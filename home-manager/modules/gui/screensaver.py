#!@python@/bin/python
import argparse
import json
import os
import random
import signal
import subprocess
import sys

import filelock

class Screensaver:
    def __init__(self, cmd, env=None, weight=1):
        self.cmd = cmd
        self.weight = weight

        if env is not None:
            self.env = os.environ.copy()
            for k, v in env.items():
                self.env[k] = v
        else:
            self.env = None
        self.proc = None

    def start(self):
        assert self.proc is None
        self.proc = subprocess.Popen(self.cmd, env=self.env)

    def wait(self):
        assert self.proc is not None
        self.proc.wait()

    def stop(self, kill=False):
        assert self.proc is not None
        if kill:
            self.proc.kill()
        else:
            self.proc.terminate()

class DoomSaver(Screensaver):
    wad = '@doomWad@'

    def __init__(self, demo_index, weight=3):
        super().__init__(
            ['@chocoDoom@/bin/chocolate-doom',
             '-iwad', self.wad,
             '-demoloopi', str(demo_index)],
            env={
                'SDL_AUDIODRIVER': 'null',
                'SDL_VIDEODRIVER': 'caca',
                'CACA_DRIVER': 'ncurses',
            },
            weight=weight,
        )

    def stop(self):
        super().stop(kill=True)

class MultiSaver:
    savers = [
        DoomSaver(0),
        DoomSaver(1),
        DoomSaver(2),
    ]
    state_filename = 'screensaver.json'

    def __init__(self):
        self.state_path = os.path.join(f'/run/user/{os.geteuid()}', self.state_filename)
        self.lock = filelock.FileLock(f'{self.state_path}.lock')

        self.selected = None
        self.cleaned_up = False

    def select(self):
        assert self.selected is None
        with self.lock:
            if not os.path.exists(self.state_path):
                state = {'instances': []}
            else:
                with open(self.state_path) as f:
                    state = json.load(f)

            available = set(range(len(self.savers)))
            new_instances = []
            for instance in state['instances']:
                if not os.path.exists(f"/proc/{instance['pid']}"):
                    continue

                new_instances.append(instance)
                i = instance['saver']
                assert i in available
                available.remove(i)
            assert available, 'No screensavers left'
            available = list(available)

            weights = []
            for i in available:
                weights.append(self.savers[i].weight)
            selected_i = random.choices(available, weights=weights)[0]

            new_instances.append({'pid': os.getpid(), 'saver': selected_i})
            state['instances'] = new_instances

            with open(self.state_path, 'w') as f:
                json.dump(state, f)

        print(f'Selected saver {selected_i}')
        self.selected = self.savers[selected_i]

    def cleanup(self):
        if self.cleaned_up:
            return
        self.cleaned_up = True

        with self.lock:
            with open(self.state_path) as f:
                state = json.load(f)

            for i, instance in enumerate(state['instances']):
                if instance['pid'] == os.getpid():
                    del state['instances'][i]

            with open(self.state_path, 'w') as f:
                json.dump(state, f)

    def run(self):
        assert self.selected is not None
        self.selected.start()

        signal.signal(signal.SIGINT, self._sighandler)
        signal.signal(signal.SIGTERM, self._sighandler)
        signal.signal(signal.SIGHUP, self._sighandler)
        self.selected.wait()
        self.cleanup()

    def stop(self):
        assert self.selected is not None
        print('Shutting down')
        self.selected.stop()
        self.cleanup()
    def _sighandler(self, signum, frame):
        self.stop()

def main():
    parser = argparse.ArgumentParser(description='Wayland terminal-based lock screen')
    parser.add_argument('-t', '--terminal', default='alacritty', help='Terminal emulator to use')
    parser.add_argument('-i', '--instance', action='store_true', help='Run as instance')

    args = parser.parse_args()
    if not args.instance:
        subprocess.check_call([
            'swaylock-plugin', '--command-each',
            f'@windowtolayer@/bin/windowtolayer -- {args.terminal} -e {sys.argv[0]} --instance'])
        return

    ms = MultiSaver()
    ms.select()
    ms.run()

if __name__ == '__main__':
    main()
