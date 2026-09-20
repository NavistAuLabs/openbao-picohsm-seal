# Contributing

Outside contributions are welcome. This document covers the branch model, the
evidence a change needs to carry, what is in scope for this repo, and a note
on the documentation style.

## Branch model

- Fork the repository, branch from `main` (`feat/…`, `fix/…`, `docs/…`), and
  open your pull request against `main`.
- There are no releases, release assets or CI. `main` is what people use;
  pin a commit if you need something stable.

## Your change has to have been run

This is hardware. There is no test suite that can tell you a change is
correct, because the interesting failures are a wedged dongle, a hub that
does not actually cut VBUS, or a token label the seal driver doesn't
recognise. State what you ran, in the pull request description:

- **A firmware change:** the board you flashed it to, the pico-hsm ref you
  built, the `opensc-tool -an` output, and the result of the ceremony's OAEP
  round-trip.
- **A failover change:** the hub model and `lsusb` ID, and a `uhubctl`
  transcript showing VBUS actually dropping.
- **An unseal-host change:** the OS, the `pkcs11-tool -L` token label, and a
  successful unseal.

Documentation-only changes need none of this. "Looks right" is not evidence
for this project.

## Scope

**In scope:**

- Fixes to the three firmware patches.
- New pico-hsm refs that build and pass the ceremony.
- Corrections to any documented fact.

**Out of scope:**

- New board targets without a tested build.
- Generalising the Ansible fragments into a reusable role or collection.
- Disaster-recovery procedures — escrow, restore drills. This repo states
  that the PEM must be escrowed and stops there; it stays that way here.
- CI workflows.

If you are unsure whether something is in scope, open an issue before writing
the PR.

## Documentation style

The README's Requirements and Bring-up sections use short, controlled-language
sentences: one idea per sentence, active voice, twenty words or fewer per
instruction. The explanatory sections (How it works, Why these choices,
Security notes) use ordinary prose. Keep that split when you edit either — it
is deliberate, not inconsistent.

## Code of conduct

This project follows the [Contributor Covenant](CODE_OF_CONDUCT.md). Reports
go to `foss+conduct@navist.com.au`.
