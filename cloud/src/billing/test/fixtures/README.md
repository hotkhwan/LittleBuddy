# Test-only certificate chain (NOT Apple, NOT trusted anywhere)

Generated once with LibreSSL for `apple.test.ts` so the JWS x5c chain
verification in `jws.ts` / `x509.ts` runs offline against a real ECDSA chain:

| file | role |
| --- | --- |
| `root.pem` | self-signed P-384 root, plays "Apple Root CA - G3" in tests (its SHA-256 is pinned by the test, not by production config) |
| `inter.pem` | P-256 intermediate signed by the root, carries OID 1.2.840.113635.100.6.2.1 like Apple's WWDR intermediate |
| `leaf.pem` / `leaf.pkcs8.pem` | P-256 signing leaf + private key, carries OID 1.2.840.113635.100.6.11.1 like Apple's receipt-signing leaf |
| `rogue_root.pem`, `rogue_leaf.pem`, `rogue_leaf.pkcs8.pem` | an unrelated chain whose leaf has the right OID but the wrong root; must be rejected |

The private keys here sign nothing but test vectors. Production pins the real
Apple Root CA - G3 fingerprint from `config.ts` / `APPLE_ROOT_CA_G3_SHA256`.
