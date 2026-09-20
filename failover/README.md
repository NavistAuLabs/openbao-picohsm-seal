# failover

Ansible role fragment for the hypervisor, plus an OpenTofu snippet for
Proxmox. Together they make sure exactly one of the two seal dongles is
powered and passed through to the OpenBao VM, and let a wedged or dead
dongle be swapped for its spare with one command.

Files: [`ansible/tasks/seal_dongle.yaml`](ansible/tasks/seal_dongle.yaml), the
three templates in [`ansible/templates/`](ansible/templates/), and
[`proxmox-usb-mapping.tf`](proxmox-usb-mapping.tf).

## Hub requirement

The hub must be a VIA Labs VL822 (`2109:*`). It cuts VBUS only in USB 2.0 mode — it does not over USB 3 (`mvp/uhubctl#451`) — and only on ports 2 and 3; ports 1 and 4 disconnect data but leave VBUS live. A USB-A→C adapter without USB 3 forces 2.0 mode. Short USB-A extension cables space the dongles into ports 2 and 3.

Verify on arrival: plug something with an LED into the port and watch it go dark on `uhubctl -a off`.

## Why one dongle is powered

Both dongles report `2e8a:10fd` and the same token label. The passthrough layer cannot tell them apart, so only one can ever be powered at a time or the VM could bind either one.

## Why a boot guard

Hub port power does not survive a power cut — the hub comes back with all ports on. The boot guard unit runs `Before=pve-guests.service` so the VM sees exactly one dongle by the time it starts.

## Sequence

Both off → spare on → ATR probe → spare off → production on. This means the spare is verified on every boot instead of sitting as an untested cold standby.

## Why ATR, not enumeration

A wedged dongle keeps enumerating on USB while its card application is dead (upstream pico-hsm issue #9, reproduced here) — `lsusb` would call it healthy. The probe uses `opensc-tool -an` instead, which needs no PIN, no key, and no PKCS#11 module, so nothing secret lives on the hypervisor.

## Fail-open

Every path in the boot guard exits 0. A spare that fails its probe must not block the unseal.

## Variables

| Variable | Meaning |
|---|---|
| `proto_seal_hub_location` | `uhubctl -l` location, e.g. `1-2` |
| `proto_seal_prod_port` | hub port number for the production dongle |
| `proto_seal_spare_port` | hub port number for the spare dongle |
| `proto_seal_settle_seconds` | delay after a power change (default 3) |
| `proto_seal_metrics_dir` | node_exporter textfile dir; metric skipped if absent |

The role is skipped entirely while `proto_seal_hub_location` is unset.

## Metric

`seal_dongle_spare_healthy` — gauge, 1 or 0, written by the boot guard.

## `seal-dongle-swap`

Three forms: `seal-dongle-swap`, `--status`, `--probe`. Safe to run while OpenBao is live, because the dongle is only used at unseal time. A swap is not persisted until `proto_seal_prod_port` and `proto_seal_spare_port` are updated and the role re-run.

## Proxmox

[`proxmox-usb-mapping.tf`](proxmox-usb-mapping.tf) maps the dongle by VID/PID, not hub port path, so a swap needs no OpenTofu change. Raw `host=` passthrough needs root; a hardware mapping (Proxmox VE 8.1+) works with an API token holding `Mapping.Use`.
