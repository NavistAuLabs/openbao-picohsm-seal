# OpenSCDP Smart Card Shell — provenance

Importing an externally generated seal key onto a pico-hsm is impossible
without scsh, because `sc-hsm-tool --unwrap-key` cannot take a PEM.

## Pin

| Field | Value |
|---|---|
| Upstream | `openscdp.org/scsh3/` (CardContact Systems GmbH) |
| Version | 3.18.77 (engine reports 3.18.110) |
| Artifact | `scsh-3.18.77.zip` (the plain File Archive) |
| Size | 17,181,832 bytes |
| sha256 | `1e5a065b7888a660a088956d110ce5539e85b76cf3c3f02eb57e4d3104bcf280` |
| Licence | **GPL v2** — redistribution permitted |
| Fetched | 2026-07-30 |
| Source URL | `https://www.openscdp.org/download/scsh3/scsh-3.18.77.zip` |

Requires a JRE; none is bundled in this archive (upstream's JRE-bundled
variant is Windows-only). Rehearsed against **OpenJDK 22** (GraalVM CE
22.0.2). Pin the JDK you rehearse with — a Java upgrade is a change to
the ceremony.

## Not vendored

The zip itself is not in this repo. Download it from the source URL
above, check its sha256 against the pin, and place it beside
`seal-key-ceremony.sh` (or point `SCSH_ZIP` at it). The ceremony script
refuses to proceed with a zip whose hash does not match the pin.

## Usage

`./scsh3 <file>` does **not** run a script — it opens a REPL and ignores
the argument. Piping (`echo 'load("x.js")' | ./scsh3`) starts the script
but kills it with `InterruptedException` when stdin closes mid-run. The
non-interactive entrypoint is `ScriptRunner`:

```
unzip scsh-3.18.77.zip && cd scsh-3.18.77
cp ../import-seal-key.js .
java -Xmx1024m -Dsun.security.smartcardio.t1GetResponse=false \
     -Dorg.bouncycastle.asn1.allow_unsafe_integer=true \
     -Djava.library.path=./lib -cp './bin:lib/*' \
     de.cardcontact.scdp.engine.ScriptRunner import-seal-key.js
```

`import-seal-key.js` (this directory) does the whole job — DKEK wrap and
card import over PCSC. `sc-hsm-tool` is not involved.

## Rehearsal record (2026-07-30)

Proven end-to-end on one dongle with a throwaway RSA-4096 key:

| Step | Result |
|---|---|
| `openssl genrsa -4096` | instant |
| DKEK wrap (`DKEK.encodeKey`) | 8s, 1099-byte blob |
| Import over PCSC (`HSMKeyStore.importRSAKey`) | 44s total |
| Verify: decrypt on-device a message encrypted with the escrowed PEM's public half | **PASS** |
| RSA-4096 `CKM_RSA_PKCS_OAEP` decrypt | **16.2s** |

The verification step is the one that matters: it proves the device
holds exactly the key that was escrowed, not merely *a* working key.

**RSA-4096 OAEP decrypt costs 16.2s**, against 3.7s measured at
RSA-2048. That is the real per-unseal latency and should be expected in
OpenBao's startup time.

### Gotchas found during the rehearsal

- **`pkcs11-tool --label` does not select the key for `--decrypt`.** With
  two keys on the token it silently used the wrong one and failed with
  `CKR_ENCRYPTED_DATA_INVALID`. Use `--id`. This looks exactly like a
  corrupt-ciphertext or bad-import failure and is neither.
- The DKEK share password KDF is 3 rounds of 10,000,000 MD5 iterations.
  scsh has a fast path; without it the fallback loop is very slow.
- The PKCS#12's certificate is only a carrier for the public key —
  `encodeKey(pri, pub)` needs both halves. A throwaway self-signed cert
  is fine; nothing stores or checks it.
