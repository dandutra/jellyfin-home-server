# 009: BitLocker on C: with a TPM-only protector

**Context:**
- Windows turned on device encryption by itself during the clean install. C: is encrypted, but protection is off and there are no key protectors. In that state the key sits on the drive in the clear, so the encryption protects nothing.
- C: holds the Windows accounts, the restored personal files, and in Phase 2 and 3 the service configs, which include API keys and the Jellyfin user database.
- The laptop sits in the house unattended and sometimes moves between rooms. Theft is the realistic threat.
- After a power cut the server has to boot by itself (Wake on AC) with nobody there to type a PIN.

**Decision:**
- Turn protection on for C: with a **TPM-only** protector. No startup PIN.
- Add a **recovery password** protector first and save the 48-digit key in the password manager before protection goes on.
- The recovery key never goes in the repo, in `local/`, or in a Microsoft account. The local admin account has no Microsoft account to back it up to.
- D: (media) stays unencrypted. It holds replaceable media from legal sources, and encrypting it would cost CPU during playback.

**Consequences:**
- A stolen laptop or a removed NVMe doesn't expose the files on C:. The TPM releases the key only to the unmodified Windows boot chain on this board.
- The laptop still boots by itself after a power cut.
- Firmware changes such as BIOS settings, a BIOS update or Secure Boot changes can make the TPM refuse the key, and the laptop then asks for the recovery key at boot. Before any BIOS change, run `Suspend-BitLocker -MountPoint C: -RebootCount 1`.
- If the recovery key is lost and the TPM refuses, the data on C: is gone. The Phase 2 config backup to the Mac limits what that would cost.
