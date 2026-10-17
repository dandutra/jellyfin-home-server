# 009: No BitLocker; decrypt C:

**Context:**
- Windows turned on device encryption by itself during the clean install. C: is encrypted, but protection is off and there are no key protectors. In that state the key sits on the drive in the clear, so the encryption protects nothing.
- BitLocker only protects against someone who has the laptop or the drive in their hands: theft, a repair shop, a visitor booting from USB, or a drive sold or thrown away later. It does nothing while Windows is running. Defender ([ADR 008](008-defender-only.md)) and the LAN-only, key-only SSH ([ADR 005](005-ssh-lan-only-no-rdp.md)) cover those attacks.
- The server stays in the apartment. Theft there isn't a realistic concern.
- Turning protection on (TPM-only) was the alternative. It would add a recovery key to keep safe, a `Suspend-BitLocker` step before every BIOS change, and the risk of losing C: if the key is lost.

**Decision:**
- Decrypt C: and leave BitLocker off.
- Stop Windows from turning device encryption back on by itself, so the new SSD (D:) doesn't get encrypted without a key either.

**Consequences:**
- No recovery key to store, and BIOS changes need no extra step.
- Anyone with physical access to the laptop or the drive can read C:. That includes the restored personal files and, later, the service configs with their API keys.
- Before the laptop or a drive leaves the house (repair, sale, disposal), wipe it first. If the server ever moves somewhere less safe, revisit this ADR.
