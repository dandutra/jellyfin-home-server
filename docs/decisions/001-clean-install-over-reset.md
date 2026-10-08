# 001: Clean install from USB, not "Reset this PC"

**Context:** The laptop has years of use and probably malware. Windows' built-in *Reset this PC → Remove everything* runs from the existing install and its recovery partition, the same system I don't trust. Malware that survives a reset (in the recovery image, the boot chain or the firmware) is rare but real.

**Decision:**
- Build install media on a separate, clean machine (the Mac).
- Delete **every** partition, recovery included, and install fresh.
- Update the BIOS from the firmware's own flash tool (F12), not from Windows.
- Enable Secure Boot.

**Consequences:**
- More work: the USB stick has to be built on macOS, which runs into FAT32's 4 GiB file limit.
- No OEM recovery partition afterwards. Fine, since the USB stick does that job.
- The machine ends up as known-good as it can get without replacing hardware.
