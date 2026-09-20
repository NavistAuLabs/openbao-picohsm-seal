# pkcs11 auto-unseal stanza for OpenBao, driving a pico-hsm dongle through
# opensc-pkcs11.so (see unseal-host/ansible for the pcscd/libccid setup
# this depends on).
#
# - This seal type is only compiled into the HSM build of OpenBao
#   (openbao-hsm_<version>_linux_amd64.deb), built with CGO_ENABLED=1
#   and the "hsm" build tag. The regular build does not have it.
# - OpenBao's pkcs11 seal accepts exactly two mechanisms: AES-GCM and
#   RSA-OAEP. The pico-hsm only exposes RSA-OAEP over PKCS#11, so that's
#   the only usable choice here. "CKM_RSA_PKCS_OAEP" is one of two
#   accepted spellings for it (the other is "RSA_PKCS_OAEP").
# - token_label is not a name you pick freely -- it's what opensc-pkcs11
#   reports for the card: the label from the card's CIAInfo file with a
#   "(UserPIN)" suffix appended. Getting this wrong (e.g. "SmartCard-HSM"
#   or a bare "Pico-HSM") makes the unseal fail. Confirm the exact string
#   with `pkcs11-tool --module <lib> -L` before trusting it.
# - key_label must match the label the key was given at the key
#   ceremony, not an arbitrary name.
# - Unsealing at RSA-4096 through this path takes roughly 16 seconds.

seal "pkcs11" {
  lib           = "/usr/lib/x86_64-linux-gnu/opensc-pkcs11.so"
  token_label   = "Pico-HSM (UserPIN)"
  pin           = "<user PIN>"
  key_label     = "bao-seal"
  mechanism     = "CKM_RSA_PKCS_OAEP"
  rsa_oaep_hash = "sha256"
}
