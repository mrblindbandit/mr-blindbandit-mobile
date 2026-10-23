#!/usr/bin/env python3
"""Reference implementation of Blindbandit suite p256-v1 (SPEC.md §1, §1.7, §16, §17).
Generates vectors/p256-v1.json, shared by iOS, Android and web. Deterministic: all randomness is fixed.
Run: python3 scripts/gen_p256_vectors.py > vectors/p256-v1.json
"""
import base64, hashlib, hmac, json, math, struct
from cryptography.hazmat.primitives.asymmetric import ec
from cryptography.hazmat.primitives.ciphers.aead import AESGCM
from cryptography.hazmat.primitives.kdf.hkdf import HKDF
from cryptography.hazmat.primitives import hashes, serialization

def b64u(b): return base64.urlsafe_b64encode(b).rstrip(b"=").decode()
def priv(hexs): return ec.derive_private_key(int(hexs, 16), ec.SECP256R1())
def pub(k): return k.public_key().public_bytes(serialization.Encoding.X962, serialization.PublicFormat.UncompressedPoint)
def dh(a, b): return a.exchange(ec.ECDH(), b.public_key())
def hkdf(ikm, salt, info, n=32): return HKDF(hashes.SHA256(), n, salt, info).derive(ikm)
def hm(k, d): return hmac.new(k, d, hashlib.sha256).digest()

BUCKETS = [256, 512, 1024, 2048, 4096]
def padded_len(n):
    for b in BUCKETS:
        if n + 1 <= b: return b
    return ((n + 1 + 4095) // 4096) * 4096
def pad(p): return p + b"\x80" + b"\x00" * (padded_len(len(p)) - len(p) - 1)
def unpad(p): return p[:p.rstrip(b"\x00")[:-1].__len__()] if p.rstrip(b"\x00").endswith(b"\x80") else None

def padme(n):
    if n <= 1: return n
    e = math.floor(math.log2(n)); s = math.floor(math.log2(e)) + 1; z = e - s
    m = (1 << z) - 1
    return (n + m) & ~m

def safety_fingerprint(sign_pubs, handle):
    keys = b"".join(sorted(sign_pubs))
    h = b"\x00\x01" + keys + handle.encode()
    for _ in range(5200):
        h = hashlib.sha512(h + keys).digest()
    return h[:30]
def digits(fp):
    return [f"{int.from_bytes(fp[i*5:i*5+5],'big') % 100000:05d}" for i in range(6)]

# Fixed key material (test only!)
A_sign = priv("1" * 64); A_dh = priv("2" * 64)
B_sign = priv("3" * 64); B_dh = priv("4" * 64)
B_spk = priv("5" * 64); B_opk = priv("6" * 64); A_ek = priv("7" * 64)
A_dev, B_dev = "d_alice_iphone", "d_bob_pixel"
spk_sig_note = "ECDSA P-256 SHA-256 over raw spk_pub (65 bytes), P1363 r||s; randomized, so only verification is tested"
spk_sig = B_sign.sign(pub(B_spk), ec.ECDSA(hashes.SHA256()))
from cryptography.hazmat.primitives.asymmetric.utils import decode_dss_signature
r, s = decode_dss_signature(spk_sig); spk_sig_raw = r.to_bytes(32, "big") + s.to_bytes(32, "big")

DH1 = dh(A_dh, B_spk); DH2 = dh(A_ek, B_dh); DH3 = dh(A_ek, B_spk); DH4 = dh(A_ek, B_opk)
info = b"BB-X3DH-v1" + A_dev.encode() + B_dev.encode()
SK = hkdf(DH1 + DH2 + DH3 + DH4, b"\x00" * 32, info)
SK_noopk = hkdf(DH1 + DH2 + DH3, b"\x00" * 32, info)
chain = []; ck = SK
for n in range(3):
    mk = hm(ck, b"\x01"); nck = hm(ck, b"\x02")
    chain.append({"n": n, "ck": b64u(ck), "mk": b64u(mk)}); ck = nck

msg_id = "6f1c2b8e-0000-4000-8000-000000000001"
payload = {"t": "text", "body": "Hello Bob, this is encrypted.", "sent_at": 1761200000, "expires_in": 0}
payload_json = json.dumps(payload, separators=(",", ":"), sort_keys=True).encode()
CEK = bytes(range(32)); content_nonce = bytes([0xA0 + i for i in range(12)])
content_ad = ("bb1:" + msg_id + ":" + A_dev).encode()
ciphertext = AESGCM(CEK).encrypt(content_nonce, pad(payload_json), content_ad)
wrap_nonce = bytes([0xB0 + i for i in range(12)])
wrap_ad = b"bb1" + pub(A_sign) + pub(B_sign)
wrapped = AESGCM(base64.urlsafe_b64decode(chain[0]["mk"] + "=")).encrypt(wrap_nonce, CEK, wrap_ad)
envelope = {"v": 1, "suite": "p256-v1", "type": "msg", "sender_device_id": A_dev, "msg_id": msg_id,
    "nonce": b64u(content_nonce), "ciphertext": b64u(ciphertext),
    "keys": [{"device_id": B_dev, "handle": "bob", "prekey": {"ek": b64u(pub(A_ek)), "spk_id": 17, "opk_id": 433, "ik": b64u(pub(A_dh)), "isk": b64u(pub(A_sign))},
              "n": 0, "pn": 0, "wrapped": b64u(wrapped), "nonce": b64u(wrap_nonce)}], "sig": None}

fpA = safety_fingerprint([pub(A_sign)], "alice"); fpB = safety_fingerprint([pub(B_sign)], "bob")
groups = digits(fpA) + digits(fpB)  # handle order: alice < bob

# attachments: 64 KiB segments, nonce = base_nonce XOR big-endian(index) in last 8 bytes
att_key = bytes([0x11] * 32); att_base = bytes([0x22] * 12)
att_plain = bytes((i * 7) % 256 for i in range(70000))
att_padded = att_plain + b"\x00" * (padme(len(att_plain)) - len(att_plain))
SEG = 65536; out = b""
for idx in range(0, (len(att_padded) + SEG - 1) // SEG):
    nonce = att_base[:4] + (int.from_bytes(att_base[4:], "big") ^ idx).to_bytes(8, "big")
    out += AESGCM(att_key).encrypt(nonce, att_padded[idx*SEG:(idx+1)*SEG], b"bb-att-v1" + struct.pack(">I", idx))

delete_target = "6f1c2b8e-0000-4000-8000-000000000002"
v = {
  "suite": "p256-v1", "version": 1,
  "notes": {
    "encoding": "base64url without padding; public keys are 65-byte uncompressed X9.63 points; private keys are 32-byte big-endian scalars (hex); signatures are P1363 r||s (64 bytes)",
    "ecdh": "shared secret = 32-byte x coordinate",
    "x3dh": "DH1=ECDH(IKdh_A,SPK_B) DH2=ECDH(EK_A,IKdh_B) DH3=ECDH(EK_A,SPK_B) DH4=ECDH(EK_A,OPK_B) (optional); SK=HKDF-SHA256(salt=32x00, ikm=DH1||DH2||DH3[||DH4], info='BB-X3DH-v1'||A_device||B_device, L=32)",
    "chain": "CK_0=SK; MK_n=HMAC-SHA256(CK_n,0x01); CK_{n+1}=HMAC-SHA256(CK_n,0x02). One session per (sender device -> recipient device), identified by prekey.ek",
    "wrap": "keys[].wrapped = AES-256-GCM(key=MK_n, nonce=keys[].nonce, pt=CEK, ad='bb1'||IKsign_A||IKsign_B) as ciphertext||tag",
    "content": "ciphertext = AES-256-GCM(key=CEK, nonce, pt=pad(payload JSON), ad='bb1:'+msg_id+':'+sender_device_id) as ciphertext||tag",
    "padding": "ISO/IEC 7816-4 (0x80 then 0x00) to the smallest of 256,512,1024,2048,4096 that fits len+1, else next multiple of 4096",
    "safety_number": "per user: keys=concat(sorted signing pubs); h='\\x00\\x01'||keys||handle; repeat 5200: h=SHA512(h||keys); fp=h[0:30]; 6 groups = big-endian uint40 of each 5 bytes mod 100000, 5 digits; both users concatenated in ascending handle order; QR bbsafety:1:<handleA>:<hex fpA>:<handleB>:<hex fpB>",
    "attachment": "pad zeros to padme(len); 65536-byte segments; seg nonce = base[0:4] || (base[4:12] as u64 BE XOR index); ad='bb-att-v1'||u32BE(index); blob=concat(seg ct||tag); sha256 over blob",
    "delete_control": "payload {t:'delete', target_msg_id, sig}; sig = ECDSA-P256-SHA256 by sender IKsign over utf8('bb-delete:'+target_msg_id)",
    "spk_signature": spk_sig_note
  },
  "keys": {
    "alice": {"handle": "alice", "device_id": A_dev, "sign_priv_hex": "1"*64, "sign_pub": b64u(pub(A_sign)), "dh_priv_hex": "2"*64, "dh_pub": b64u(pub(A_dh)), "ek_priv_hex": "7"*64, "ek_pub": b64u(pub(A_ek))},
    "bob": {"handle": "bob", "device_id": B_dev, "sign_priv_hex": "3"*64, "sign_pub": b64u(pub(B_sign)), "dh_priv_hex": "4"*64, "dh_pub": b64u(pub(B_dh)),
            "spk_id": 17, "spk_priv_hex": "5"*64, "spk_pub": b64u(pub(B_spk)), "spk_sig": b64u(spk_sig_raw), "opk_id": 433, "opk_priv_hex": "6"*64, "opk_pub": b64u(pub(B_opk))}
  },
  "x3dh": {"dh1": b64u(DH1), "dh2": b64u(DH2), "dh3": b64u(DH3), "dh4": b64u(DH4), "info": b64u(info), "sk": b64u(SK), "sk_without_opk": b64u(SK_noopk)},
  "chain": chain,
  "message": {"msg_id": msg_id, "payload_json": payload_json.decode(), "padded_len": padded_len(len(payload_json)), "cek": b64u(CEK),
              "content_nonce": b64u(content_nonce), "content_ad": content_ad.decode(), "wrap_nonce": b64u(wrap_nonce), "envelope": envelope},
  "padding": [{"len": n, "padded_len": padded_len(n)} for n in [0, 1, 255, 256, 511, 1000, 4095, 4096, 10000]],
  "padme": [{"len": n, "padded_len": padme(n)} for n in [1, 100, 1000, 70000, 1048576, 5000001]],
  "safety_number": {"alice_fp_hex": fpA.hex(), "bob_fp_hex": fpB.hex(), "groups": groups, "display": " ".join(groups),
                    "qr": f"bbsafety:1:alice:{fpA.hex()}:bob:{fpB.hex()}"},
  "attachment": {"key": b64u(att_key), "base_nonce": b64u(att_base), "plain_len": len(att_plain), "plain_rule": "byte i = (i*7) mod 256",
                 "padded_len": len(att_padded), "blob_len": len(out), "sha256_hex": hashlib.sha256(out).hexdigest()},
  "hkdf_rfc5869_case1": {"ikm_hex": "0b"*22, "salt_hex": "000102030405060708090a0b0c", "info_hex": "f0f1f2f3f4f5f6f7f8f9", "l": 42,
                          "okm_hex": hkdf(bytes.fromhex("0b"*22), bytes.fromhex("000102030405060708090a0b0c"), bytes.fromhex("f0f1f2f3f4f5f6f7f8f9"), 42).hex()},
}
# self-check
assert unpad(pad(payload_json)) == payload_json
assert v["hkdf_rfc5869_case1"]["okm_hex"].startswith("3cb25f25faacd57a90434f64d0362f2a")
print(json.dumps(v, indent=2))
