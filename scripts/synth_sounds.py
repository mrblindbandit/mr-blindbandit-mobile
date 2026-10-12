#!/usr/bin/env python3
"""Synthesizes the Blindbandit ambient ringtone / text-tone pack (additive sine bells + soft pads,
exponential envelopes, stereo echo tail). Output: 44.1 kHz WAV -> MP3 via ffmpeg."""
import math, struct, wave, subprocess, sys, os
SR = 44100
def note(f): return 440.0 * 2 ** ((f - 69) / 12)
def render(events, dur, pad=None):
    n = int(dur * SR); L = [0.0]*n
    for (t, midi, length, amp, bright) in events:
        f = note(midi); s0 = int(t*SR)
        for i in range(int(length*SR)):
            j = s0+i
            if j >= n: break
            x = i/SR; env = (1-math.exp(-x*60)) * math.exp(-x*(3.2/length))
            v = math.sin(2*math.pi*f*x) + bright*0.35*math.sin(2*math.pi*2.0*f*x)*math.exp(-x*6) + bright*0.12*math.sin(2*math.pi*3.01*f*x)*math.exp(-x*9)
            L[j] += amp*env*v
    if pad:
        for i in range(n):
            x = i/SR; e = min(1, x/0.6)*min(1, (dur-x)/0.8)
            L[i] += 0.06*e*sum(math.sin(2*math.pi*note(m)*x + k) for k, m in enumerate(pad))
    peak = max(1e-9, max(abs(v) for v in L)); return [0.8*v/peak for v in L]
def save(name, samples, outdir):
    wav = f"/tmp/{name}.wav"
    with wave.open(wav, "w") as w:
        w.setnchannels(1); w.setsampwidth(2); w.setframerate(SR)
        w.writeframes(b"".join(struct.pack("<h", int(max(-1, min(1, s))*32000)) for s in samples))
    for d in outdir:
        subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", wav, "-af", "aecho=0.8:0.7:180|360:0.25|0.12,loudnorm=I=-16:TP=-1.5",
                        "-ac", "2", "-b:a", "192k", f"{d}/{name}.mp3"], check=True)
def arp(notes, step, length=1.6, amp=1.0, bright=0.6, repeat=1, gap=0.0):
    ev = []; t = 0.0
    for _ in range(repeat):
        for m in notes: ev.append((t, m, length, amp, bright)); t += step
        t += gap
    return ev
RINGS = {
  "ringtone_ambient_dawn":     (arp([62,66,69,74], .32, repeat=3, gap=.6), 6.0, [50,57]),
  "ringtone_ambient_lagoon":   (arp([60,64,67,71,67,64], .28, repeat=2, gap=.5), 6.0, [48,55]),
  "ringtone_ambient_ember":    (arp([57,60,64,69], .36, bright=.9, repeat=3, gap=.4), 6.0, [45,52]),
  "ringtone_ambient_horizon":  (arp([65,69,72,76,72], .3, repeat=2, gap=.7), 6.0, [53,60]),
  "ringtone_ambient_velvet":   (arp([55,62,67,70], .4, bright=.3, repeat=2, gap=.6), 6.0, [43,50]),
  "ringtone_ambient_crown":    (arp([67,71,74,79,74,71], .25, bright=1.0, repeat=2, gap=.5), 6.0, [55,62]),
}
TONES = {
  "notif_ambient_halo":    (arp([76,83], .12, length=1.2), 1.6, None),
  "notif_ambient_ripple":  (arp([72,76,79], .09, length=1.0, bright=.4), 1.4, None),
  "notif_ambient_spark":   (arp([84,88], .07, length=.8, bright=1.0), 1.1, None),
  "notif_ambient_moss":    (arp([67,74], .14, length=1.3, bright=.2), 1.7, None),
  "notif_ambient_lantern": (arp([69,73,76,81], .08, length=1.1), 1.5, None),
  "notif_ambient_tide":    (arp([64,71,76], .16, length=1.4, bright=.3), 1.9, None),
}
if __name__ == "__main__":
    outs = sys.argv[1:] or ["App/Resources/Sounds"]
    for name, (ev, dur, pad) in {**RINGS, **TONES}.items():
        save(name, render(ev, dur, pad), outs); print("made", name)

# Ambient UI theme (Settings → Sounds → "Ambient UI sounds"): soft-bell variants of every UI cue.
UI = {
  "ambient_call_initiated":  (arp([67,71,74], .11, length=.9), 1.2, None),
  "ambient_call_connected":  (arp([62,69,74,78], .09, length=1.0, bright=.5), 1.3, None),
  "ambient_hangup":          (arp([74,69,62], .12, length=.9, bright=.3), 1.2, None),
  "ambient_busy_tone":       (arp([60,60,60], .35, length=.3, bright=.2), 1.3, None),
  "ambient_message_sent":    (arp([79], .1, length=.5, bright=.6), .6, None),
  "ambient_attachment_sent": (arp([74,81], .07, length=.6), .8, None),
  "ambient_voicenote_sent":  (arp([69,76,81], .07, length=.7, bright=.4), .9, None),
  "ambient_typing_ping":     (arp([88], .1, length=.25, amp=.6, bright=.2), .35, None),
  "ambient_notif_delivered": (arp([76,79], .06, length=.4, bright=.3), .55, None),
  "ambient_notif_read":      (arp([79,83], .06, length=.4, bright=.3), .55, None),
  "ambient_ringback_outgoing": (arp([64,71], .5, length=1.2, bright=.3, repeat=2, gap=1.0), 4.0, [52,59]),
}
MORE_TONES = {
  "notif_ambient_bell": (arp([72,79,84], .1, length=1.3, bright=.8), 1.7, None),
  "notif_ambient_mist": (arp([65,72], .18, length=1.5, bright=.1), 2.0, [53]),
}
if __name__ == "__main__" and os.environ.get("EXTRA", "1") == "1":
    for name, (ev, dur, pad) in {**UI, **MORE_TONES}.items():
        save(name, render(ev, dur, pad), outs); print("made", name)
