#!/usr/bin/env python3
import subprocess
import math

# https://en.wikipedia.org/wiki/Piano_key_frequencies
def note_freq(n):
    return math.pow(2, (n - 49) / 12) * 440

def gen_beep_command(notes, bpm):
    cmd = ['beep']
    for i, (n, d) in enumerate(notes):
        f = note_freq(n)
        ms = (d / (bpm/60)) * 1000

        cmd += ['-f', str(int(f)), '-l', str(int(ms))]
        if i != len(notes) -1:
            cmd.append('-n')

    return cmd

# First 2 bars of https://musescore.com/user/5032516/scores/6519100 ;)
tempo = 94
melody = [
    (52, 1/2),
    (55, 1/2),

    (57, 1/2),
    (58, 1/2),
    (57, 1/2),
    (55, 1/2),

    (52, 1+1/2),

    (50, 1/4),
    (54, 1/4),

    (52, 1),
]

def main():
    cmd = gen_beep_command(melody, tempo)
    # print(' '.join(cmd))
    subprocess.check_call(cmd)

if __name__ == '__main__':
    main()