# Security policy

## Supported versions

Security fixes go onto the most recent tag. There are no long-term support
branches.

| Version | Supported |
| ------- | --------- |
| 0.1.x   | Yes       |
| < 0.1   | No        |

## Report a vulnerability

Report vulnerabilities privately through
[GitHub Security Advisories](https://github.com/NavistAuLabs/openbao-picohsm-seal/security/advisories/new).
Do not open a public issue for a vulnerability.

Include the component (`firmware/`, `failover/`, `unseal-host/`, or
`ceremony/`), the pico-hsm tag or commit you built, the board, the hub model,
the host OS, and what you observed. Expect an acknowledgement within seven
days.

## Before you report

1. **Vulnerabilities in pico-hsm or pico-keys-sdk themselves go upstream**, at
   [github.com/polhenarejos/pico-hsm/security](https://github.com/polhenarejos/pico-hsm/security).
   This repo's own attack surface is the three build patches, the ceremony and
   failover scripts, the Ansible fragments, and the documentation — not the
   firmware's cryptographic implementation.
2. **Known and accepted:** stock pico-hsm v6.6 accepts an unauthenticated
   eFuse burn over USB (rescue applet INS `0x1D`). This repo mitigates it with
   the `FORCE_BUTTON_WAIT` build flag and
   [`ceremony/rescue-apdu.sh`](ceremony/rescue-apdu.sh). Reports that restate
   it will be closed with a pointer to this paragraph.
3. **Both dongles hold the same key by design.** That is a documented
   trade-off — it is what lets the spare stand in for the production unit —
   not a vulnerability.
