// Import an externally generated RSA seal key onto a pico-hsm dongle,
// wrapped under a DKEK share the card already holds.
//
// This exists because `sc-hsm-tool --unwrap-key` accepts only a
// SmartCard-HSM key blob and cannot import a PEM, and no OpenSC-native
// converter exists. scsh does the wrap AND the import itself over PCSC
// -- sc-hsm-tool is not involved at all.
//
// Run from the unpacked scsh directory (classpath is relative):
//
//   java -Xmx1024m -Dsun.security.smartcardio.t1GetResponse=false \
//        -Dorg.bouncycastle.asn1.allow_unsafe_integer=true \
//        -Djava.library.path=./lib -cp './bin:lib/*' \
//        de.cardcontact.scdp.engine.ScriptRunner import-seal-key.js
//
// NOTE: `./scsh3 <file>` does NOT run a script -- it opens a REPL and
// ignores the argument. ScriptRunner is the non-interactive entrypoint.
//
// Values below are placeholders. Populate at ceremony time and
// do not commit real ones. Rehearsed end-to-end on the bench unit
// 2026-07-30: wrap 8s, import 44s, verified by decrypting on-device a
// message encrypted with the escrowed PEM's public half.

var DKEK = require("scsh/sc-hsm/DKEK").DKEK;
var SmartCardHSM = require("scsh/sc-hsm/SmartCardHSM").SmartCardHSM;
var HSMKeyStore = require("scsh/sc-hsm/HSMKeyStore").HSMKeyStore;

// The .pbe produced by `sc-hsm-tool --create-dkek-share`, as hex, plus
// its password. Same share must already be imported on the card via
// `sc-hsm-tool --import-dkek-share`, or the key will be unusable.
var SHARE_HEX = "<hex of the .pbe DKEK share file>";
var SHARE_PWD = "<DKEK share password>";

// PKCS#12 holding the seal key. Build from the escrowed PEM:
//   openssl req -new -x509 -key seal.pem -out seal.crt -days 3650 -subj "/CN=bao-seal"
//   openssl pkcs12 -export -inkey seal.pem -in seal.crt -out seal.p12 -name baoseal
// The certificate is only a carrier for the public key; nothing consumes it.
var P12_PATH = "<absolute path to seal.p12>";
var P12_PWD  = "<p12 password>";

var USER_PIN  = "<user PIN>";
var KEY_LABEL = "bao-seal";
var READER    = "Pol Henarejos Pico Key HID Interface";

// --- wrap under the DKEK ------------------------------------------------
var plain = DKEK.decryptKeyShare(new ByteString(SHARE_HEX, HEX),
                                 new ByteString(SHARE_PWD, ASCII));
var crypto = new Crypto();
var dkek = new DKEK(crypto);
dkek.importDKEKShare(plain);

// Non-zero here confirms the share decrypted correctly. (The card's own
// `sc-hsm-tool` status shows an all-zero KCV for UNAUTHENTICATED reads --
// that is by design and not a fault.)
print("DKEK_KCV=" + dkek.getKCV().toString(HEX));

var p12 = new KeyStore("BC", "PKCS12", P12_PATH, P12_PWD);
var alias = p12.getAliases()[0];
var key = new Key();
key.setType(Key.PRIVATE);
key.setID(alias);
p12.getKey(key);
var pubkey = p12.getCertificate(alias).getPublicKey();
print("KEYSIZE=" + pubkey.getSize());

var blob = dkek.encodeKey(key, pubkey);
print("BLOBLEN=" + blob.length);

// --- import onto the card ----------------------------------------------
var card = new Card(READER);
var sc = new SmartCardHSM(card);
sc.verifyUserPIN(new ByteString(USER_PIN, ASCII));
print("PIN_OK");

var ks = new HSMKeyStore(sc);
ks.importRSAKey(KEY_LABEL, blob, pubkey.getSize());
print("IMPORT_OK label=" + KEY_LABEL);

card.close();
