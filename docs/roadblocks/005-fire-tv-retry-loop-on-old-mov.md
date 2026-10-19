# 005: The Fire TV looped on Big Buck Bunny without ever starting it

**Phase:** 2 · **Date:** 2026-10-19 · **Time lost:** ~45 min

## Problem
On the Fire TV Stick (Jellyfin Android TV 0.19.10), the 4K HEVC test clip played, but *Big Buck Bunny* never started. The LG and the Mac's browser played both.

The server log showed the app trying to play the file as it is (direct play), failing within half a second, and trying again, about three times a second, for over ten minutes:

```
User "<user>" started playback of '"Big Buck Bunny"' ("Jellyfin Android TV" "0.19.10")
User "<user>" stopped playback of '"Big Buck Bunny"' at "0"ms ("Jellyfin Android TV" "0.19.10")
```

There was no transcode log, so the server never got a request to convert the file. Force-stopping the app ended the loop.

## What I tried
The original file was Blender's `big_buck_bunny_1080p_h264.mov`: H.264 1080p, 5.1 AAC, and a QuickTime timecode track (`tmcd`). The 4K clip that played had no audio at all. I made 2-minute copies with ffmpeg, changing one thing at a time, and played each on the Fire TV:

| Copy | Container | Audio | Timecode track | Fire TV |
|---|---|---|---|---|
| Original | `.mov` (2008) | 5.1 AAC | yes | loops |
| A | `.mp4` | 5.1 AAC | yes* | plays |
| B | `.mp4` | stereo AAC | yes* | plays |
| C | `.mov` | 5.1 AAC | no | plays |
| Full remux | `.mp4` | 5.1 AAC | yes | plays |

\* ffmpeg adds a `tmcd` track to MP4 by default when the video stream carries a timecode tag. I didn't check A and B for it at the time. The full remux, made with the same command and no `-t`, has one, so A and B almost certainly did too.

After C, I wrongly blamed the timecode track. The full-length remux kept that track and played, which ruled it out.

## Root cause
Something in how the original 2008 file was packaged. It wasn't the video, the 5.1 audio, the `.mov` format, the timecode track or the length. Every copy ffmpeg rewrote played, and only the original failed. I deleted the original before inspecting its layout, so I can't say exactly what it was. The likely suspects are the index (`moov`) position and an old edit list. The Android TV app retries a failed direct play forever instead of falling back to a server-side transcode.

## Fix
Repackaged the file without re-encoding (the video and audio are copied bit for bit):

```powershell
& 'C:\Program Files\Jellyfin\Server\ffmpeg.exe' -i big_buck_bunny_1080p_h264.mov `
    -map 0:v:0 -map 0:a:0 -c copy -movflags +faststart 'Big Buck Bunny (2008).mp4'
```

Step 6 of the runbook now does this straight after the download.

## What I learned
Change one thing per test copy, and check what the tool actually wrote before reading the result. I assumed copy A had no timecode track, because I hadn't asked for one, and that led me to a wrong conclusion. Also, keep the original until the cause is known, not just until the replacement checks out. A file that plays on one client can still break another, so every client gets tested.
