# 008: The LG spun forever on a heavy MKV

**Phase:** 3 · **Date:** 2026-10-21 · **Time lost:** ~20 min

## Problem
The end-to-end test film showed up in Jellyfin on the LG, but pressing play gave a spinner that ran for more than five minutes. The file was a public-domain 4K remux: HEVC Main 10 at about 80 Mbit/s, FLAC audio, two SRT tracks, in MKV. The Phase 2 test clip, 4K HEVC at 40 Mbit/s in MP4, had played directly on the same TV.

## What I tried
1. Looked for a stuck conversion. No `ffmpeg` was running: Jellyfin had told the LG to play the file directly. Its log showed only the TV's player dropping a `/Sessions/Playing` report after about 70 seconds.
2. Suspected the TV's Wi-Fi couldn't carry 80 Mbit/s. I logged the server's upload every 5 seconds while the film was started again. The TV pulled two bursts at up to 99 Mbit/s, about 50 to 90 MB in all, then asked for nothing more. A slow link would have kept pulling at whatever rate it got. This looked like a player that filled its buffer and couldn't start.

## Root cause
The LG's player couldn't handle this file, even though Jellyfin's profile for it allowed direct play. It's either the bitrate or FLAC in MKV. I didn't split the two because one setting fixes both.

## Fix
In the LG's Jellyfin app, **Settings → Playback → Home network quality: 40 Mbps**. Jellyfin then converted it with Quick Sync (`h264_qsv`, AAC audio) at 1.8x real time, with CPU around 36%, and it played with subtitles. Files at or below 40 Mbit/s still play directly. On the Fire TV the same film converted to 1080p at 3.5x real time with no setting.

## What I learned
"Direct play" is only what the client says it supports. Watching the bytes on the wire told a stalled player apart from a slow link in one try, without guessing. A bitrate cap per client is a cheap safety net, because the server can convert anything above it.
