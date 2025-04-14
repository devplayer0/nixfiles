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

    def __init__(self, demo_index, weight=1.5):
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

class TTESaver(Screensaver):
    effects = (
        'beams,binarypath,blackhole,bouncyballs,bubbles,burn,colorshift,crumble,'
        'decrypt,errorcorrect,expand,fireworks,middleout,orbittingvolley,overflow,'
        'pour,print,rain,randomsequence,rings,scattered,slice,slide,spotlights,'
        'spray,swarm,synthgrid,unstable,vhstape,waves,wipe'
    ).split(',')

    def __init__(self, cmd, env=None, weight=1):
        super().__init__(cmd, env=env, weight=weight)
        self.running = False

    def start(self):
        self.running = True

    def wait(self):
        while self.running:
            effect_cmd = ['@terminaltexteffects@/bin/tte', random.choice(self.effects)]
            print(f"$ {self.cmd} | {' '.join(effect_cmd)}")
            content = subprocess.check_output(self.cmd, shell=True, env=self.env, stderr=subprocess.DEVNULL)

            self.proc = subprocess.Popen(effect_cmd, stdin=subprocess.PIPE)
            self.proc.stdin.write(content)
            self.proc.stdin.close()
            self.proc.wait()

    def stop(self):
        self.running = False
        self.proc.terminate()

class FFmpegCACASaver(Screensaver):
    @staticmethod
    def command(video, size):
        return ['@ffmpeg@/bin/ffmpeg', '-hide_banner', '-loglevel', 'error',
                '-stream_loop', '-1', '-i', video,
                '-pix_fmt', 'rgb24', '-window_size', f'{size}x{size}',
                '-f', 'caca', '-']

    def __init__(self, video, weight=2):
        cols, lines = os.get_terminal_size()
        # IDK if it's reasonable to do this as "1:1"
        size = lines - 4
        super().__init__(
            self.command(video, size),
            env={'CACA_DRIVER': 'ncurses'},
            weight=weight,
        )

    def stop(self):
        super().stop(kill=True)

class BrainrotStorySaver(Screensaver):
    def __init__(self, video, text_command, weight=2):
        cols, lines = os.get_terminal_size()
        video_size = lines - 1
        video_command = ' '.join(FFmpegCACASaver.command(video, video_size))
        text_command = (
            f'while true; do {text_command} | '
            f'@terminaltexteffects@/bin/tte --wrap-text --canvas-width=80 --canvas-height={video_size//2} --anchor-canvas=c '
            'print --final-gradient-stops=ffffff; clear; done' )
        self.tmux_session = f'screensaver-{os.urandom(4).hex()}'
        super().__init__(
            ['@tmux@/bin/tmux', 'new-session', '-s', self.tmux_session, '-n', 'brainrot',
             text_command, ';', 'split-window', '-hbl', str(lines), video_command],
            # ['sh', '-c', text_command],
            env={
                'CACA_DRIVER': 'ncurses',
                'SHELL': '/bin/sh',
            },
            weight=weight,
        )

    def stop(self):
        subprocess.check_call(['@tmux@/bin/tmux', 'kill-session', '-t', self.tmux_session])

class MultiSaver:
    savers = [
        DoomSaver(0),
        DoomSaver(1),
        DoomSaver(2),

        Screensaver(['cmatrix']),

        TTESaver('screenfetch -N'),
        TTESaver('fortune | cowsay'),
        TTESaver('top -bn1 | head -n50'),
        TTESaver('ss -nltu'),
        TTESaver('ss -ntu'),
        TTESaver('jp2a --width=100 @enojy@'),

        BrainrotStorySaver('@subwaySurfers@', '@brainrotTextCommand@'),
        BrainrotStorySaver('@minecraftParkour@', '@brainrotTextCommand@'),
    ]
    state_filename = 'screensaver.json'

    def __init__(self, select=None):
        self.state_path = os.path.join(f'/run/user/{os.geteuid()}', self.state_filename)
        self.lock = filelock.FileLock(f'{self.state_path}.lock')

        if select is not None:
            assert select >= 0 and select < len(self.savers), 'Invalid screensaver index'
            self.selected = self.savers[select]
        else:
            self.selected = None
        self.cleaned_up = False

    def select(self):
        with self.lock:
            if not os.path.exists(self.state_path):
                state = {'instances': []}
            else:
                with open(self.state_path) as f:
                    state = json.load(f)

            if self.selected is None:
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

                # print(f'Selected saver {selected_i}')
                self.selected = self.savers[selected_i]

            with open(self.state_path, 'w') as f:
                json.dump(state, f)

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
    parser.add_argument('-l', '--locker-cmd', default='swaylock-plugin', help='swaylock-plugin command to use')
    parser.add_argument('-t', '--terminal', default='alacritty', help='Terminal emulator to use')
    parser.add_argument('-i', '--instance', action='store_true', help='Run as instance')
    parser.add_argument('-s', '--screensaver', type=int, help='Force use of specific screensaver')

    args = parser.parse_args()
    if not args.instance:
        cmd = [
            args.locker_cmd, '--command-each',
            f'@windowtolayer@/bin/windowtolayer -- {args.terminal} -e {sys.argv[0]} --instance']
        if args.screensaver is not None:
            cmd[-1] += f' --screensaver {args.screensaver}'
        subprocess.check_call(cmd)
        return

    ms = MultiSaver(select=args.screensaver)
    ms.select()
    ms.run()

if __name__ == '__main__':
    main()
