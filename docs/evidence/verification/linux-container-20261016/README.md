# Linux dedicated server with Windows clients (2026-10-16)

The first time a Critterweight Linux build ran. The machine was this Windows 10 PC, with Docker Desktop on WSL2.
- **Server:** the packaged **Linux dedicated server**, in a Debian 12 (glibc 2.36) container from an image
  already on the machine. Nothing was downloaded.
- **Clients:** two **packaged Windows clients**, joining it through the mapped UDP port.

This is real Linux user space on a real Linux kernel. It is not Ubuntu 24.04 and not a Steam Deck, and it is
still one PC (loopback through Docker's port mapping).

## What it found

**A cross-platform bug.** The clients joined, but every match was refused at the start:
"Your copy of arena 'the_gullet' differs from the host's (content hash)."

Godot 4.5.1's `JSON.stringify` writes the same double with 17 significant digits on Windows and 18 on
Linux, for example `1.6000000000000001` against `1.60000000000000009`. Every hash taken over JSON text with
fractional numbers therefore differed between the platforms:
- arena content hashes, compared by peers before a match and by arena package imports;
- run-state checksums, used by save envelopes and party-run tickets.

The diff of the arena's canonical data on the two platforms showed only that digit difference
(`game -- --arena-hash <id> --out file.json`, added for this).

**Fix:** `Canon` (`game/src/core/canon.gd`) hashes whole floats as ints and every other float as its exact
IEEE-754 bytes, so the hashed text has no float formatting in it. `Saves.checksum` and
`ArenaDef.content_hash` use it. Older checksums and package hashes, written by earlier builds, are still
accepted (`Saves.checksum_matches`, `ArenaDef.content_hash_legacy`). Regression test: test_persistence
`test_checksums_do_not_depend_on_float_text`.

## Result after the fix

| Check | Result |
|---|---|
| `--arena-hash the_gullet`: Linux server package vs Windows game package | identical (`71993310…`) |
| The Linux server starts from a config file | listening on UDP 7777, protocol 5, playlist loaded (`server_container.txt`) |
| Two Windows clients join, play the duel to a result | both connected and both got the authoritative result; the scripted attacker landed 40 hits (`alice.json`, `bob.json`) |
| Network stats seen by the clients | 30 snapshots/s, 47 ms interpolation, 14-15 ms RTT |
| `docker stop` | with `docker run --init`: exit 143 in 0.4 s. Without `--init` the server runs as PID 1, which ignores SIGTERM, and Docker kills it after the timeout (exit 137). For a graceful stop use the TCP admin `shutdown` or the console (SERVER.md). |

Not covered yet: the Linux **game** package (it needs a GPU and a display), Ubuntu 24.04 itself, the
Steam Deck, two machines.
