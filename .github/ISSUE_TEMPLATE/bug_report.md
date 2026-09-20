---
name: Bug report
about: Report a problem with openbao-picohsm-seal
title: ""
labels: bug
assignees: ""
---

**Before you paste anything:** ceremony output, Ansible logs, and eFuse
summaries can carry PINs, key material, or other secrets. Redact
`SO_PIN`/`USER_PIN` values, any escrowed key material, and anything you would
not otherwise publish.

If this is a security issue, do not open an issue — see SECURITY.md.

## Environment

- Component: <!-- firmware/ | failover/ | unseal-host/ | ceremony/ -->
- pico-hsm ref (tag or commit):
- Board:
- Hub model (for failover/):
- Host OS (for unseal-host/):

## What happened

## What you expected to happen

## What you ran

<!-- The exact command(s) or Ansible task you ran. -->

## What you observed

<!--
Log lines, opensc-tool/pkcs11-tool output, a uhubctl transcript, etc.
Redact secrets first.
-->
