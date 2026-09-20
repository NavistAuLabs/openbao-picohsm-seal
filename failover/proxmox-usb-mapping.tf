# Proxmox USB passthrough for the pico-hsm seal dongle.
#
# Raw `host = "2e8a:10fd"` passthrough fails for a non-root API token with
# "only root can set 'usb0' config for real devices" (Proxmox bug 5765).
# A hardware mapping (Proxmox VE 8.1+) works with an API token that holds
# the `Mapping.Use` privilege instead.
#
# The mapping is by VID/PID, not hub port path. Both dongles share this ID;
# the boot guard in ansible/ guarantees only one is ever powered, so the
# mapping cannot bind the wrong unit. A failover swap therefore needs no
# change here.

# =============================================================================
# USB resource mapping — pico-hsm seal dongle
# =============================================================================
resource "proxmox_virtual_environment_hardware_mapping_usb" "pico_hsm" {
  name    = "PicoHSM"
  comment = "pico-hsm seal dongle (2e8a:10fd) - OpenBao pkcs11 seal"

  map = [
    {
      id   = "2e8a:10fd"
      node = "pve1"
    }
  ]
}

resource "proxmox_virtual_environment_vm" "openbao" {
  node_name = "pve1"

  # ... the rest of your VM definition ...

  # USB resource mapping so a non-root API token can configure it
  usb {
    mapping = proxmox_virtual_environment_hardware_mapping_usb.pico_hsm.name
  }

  lifecycle {
    prevent_destroy = true
  }
}
