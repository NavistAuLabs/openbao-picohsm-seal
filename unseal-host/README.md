# unseal-host

Ansible task file and handler for the OpenBao VM, a Python patch script
they run, and the seal stanza itself. Together they make one pico-hsm
dongle reachable by OpenBao's pkcs11 seal.

Files: [`ansible/tasks/picohsm_host.yaml`](ansible/tasks/picohsm_host.yaml),
[`ansible/handlers/main.yaml`](ansible/handlers/main.yaml),
[`ansible/files/patch-libccid-picohsm.py`](ansible/files/patch-libccid-picohsm.py),
[`seal.hcl`](seal.hcl).

## Cloud kernel trap

Debian's genericcloud image ships `linux-image-*-cloud-amd64`, which has
no USB drivers. The task file installs `linux-image-amd64`, finds and
purges every installed `linux-image-*cloud*` package — removing just the
meta-package leaves the versioned kernel packages in place and GRUB keeps
booting them — runs `update-grub`, and reboots, but only when a cloud
kernel was actually removed or the running kernel lacks USB support.

## pcscd + libccid + opensc

Debian's `libccid` 1.5.2 predates the pico-hsm's VID/PID.
[`patch-libccid-picohsm.py`](ansible/files/patch-libccid-picohsm.py) adds
`0x2E8A`/`0x10FD` to `/etc/libccid_Info.plist`, and the
[handler](ansible/handlers/main.yaml) restarts pcscd when the patch
changes anything. pcscd must be unmasked and running.

## Why not sc-hsm-embedded / CT-API

The CT-API driver cannot complete the CCID handshake with the pico-hsm's
TinyUSB stack — the slot enumerates but reports no card present.

## Token label

`Pico-HSM (UserPIN)` is what opensc-pkcs11 reports for this card. Both
`SmartCard-HSM` and a bare `Pico-HSM` fail the unseal. Read the exact
string with:

```
pkcs11-tool --module /usr/lib/x86_64-linux-gnu/opensc-pkcs11.so -L
```

## Mechanism

`CKM_RSA_PKCS_OAEP` with SHA-256 is the only mechanism the pico-hsm
offers over PKCS#11 that OpenBao's seal accepts. At RSA-4096 this takes
about 16.2 seconds per unseal.

## OpenBao build

The pkcs11 seal exists only in the HSM distribution of OpenBao
(`openbao-hsm_<version>_linux_amd64.deb`). The regular build does not
have it.

## Seal migration

From an existing seal, use OpenBao's documented seal-migration flow: the
old seal stanza stays in place with `disabled = "true"`, the new pkcs11
stanza is active, unseal with recovery shares and `migrate: true`, then
drop the old stanza once it converges. See
[OpenBao's seal documentation](https://openbao.org/docs/concepts/seal/).

## Seal config

[`seal.hcl`](seal.hcl) is the pkcs11 seal stanza this all serves.
