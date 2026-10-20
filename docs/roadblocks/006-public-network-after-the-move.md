# 006: After moving the server, nothing could reach it

**Phase:** 3 · **Date:** 2026-10-20 · **Time lost:** ~30 min, plus one missed backup pull

## Problem
After the kill-switch test I shut the server down, moved it and the router to their final spot, and powered both back on. The router had been unplugged too. The next morning the Mac's 04:13 backup pull had failed (`FAILED: ssh to homeserver failed`), and SSH, Jellyfin (8096) and qBittorrent's web page (8080) all timed out from the Mac.

## What I tried
1. Assumed the server was off overnight. It wasn't: it had been up since 19:16 the evening before, and its own 03:30 backup had worked.
2. Checked whether it had a new address. The Mac's ARP table and mDNS (`dns-sd -G v4 homeserver.local`) both had it at its reserved address, so the DHCP reservation still worked. It was on the network and answering ARP, but every TCP port timed out.
3. Every inbound rule I made (SSH, Jellyfin, qBittorrent) is limited to the **Private** firewall profile. A dropped connection on every port at a known-good address pointed there. At the laptop, Settings showed the Ethernet network as **Public**.

## Root cause
Windows didn't recognize the network after the move. The NetworkProfile event log shows it identifying the Ethernet connection 30 seconds after boot and creating a new profile, `Network`, instead of reusing the one from before. New networks start as Public, and the Public profile has none of my rules, so the firewall dropped everything. I don't know exactly which part of the network's fingerprint changed in the move.

## Fix
Set the Ethernet network to Private in Settings at the laptop. SSH, Jellyfin and qBittorrent answered straight away, and a manual `launchctl kickstart` pulled the missed backup.

## What I learned
Scoping firewall rules to the Private profile is the right default, but it means the server's reachability depends on a label Windows can reset on its own. After any change to the network (moving the server or the router, a new router, a router reset), check the network profile first. A server that answers ARP but drops every port is a firewall problem, not a network problem.
