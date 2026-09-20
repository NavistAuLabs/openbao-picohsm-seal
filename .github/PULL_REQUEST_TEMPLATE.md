<!--
Branch from `main` and target `main`. See CONTRIBUTING.md.
-->

## What this changes

<!-- One or two sentences. What behaviour is different after this merge? -->

## Why

<!-- The problem this solves. Link the issue if there is one. -->

Closes #

## How it was run

<!--
Required for anything that changes behaviour; delete this section for a
docs-only change. "Looks right" is not evidence — see CONTRIBUTING.md.
-->

- Component: <!-- firmware/ | failover/ | unseal-host/ | ceremony/ -->
- Firmware change — board flashed, pico-hsm ref built, `opensc-tool -an`
  output, result of the ceremony's OAEP round-trip:
- Failover change — hub model, `lsusb` ID, `uhubctl` transcript showing VBUS
  actually dropping:
- Unseal-host change — OS, `pkcs11-tool -L` token label, successful unseal:

## Checklist

- [ ] Run against real hardware, with the result recorded above (skip for
      docs-only changes).
- [ ] Documentation updated if a documented fact changed.
- [ ] `CHANGELOG.md` updated if this touches a firmware patch or the
      boot-guard sequence.
