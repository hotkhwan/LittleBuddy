// A MINIMAL X.509 reader: enough DER to pull out of a certificate what chain
// verification needs (the signed TBS bytes, the signature algorithm, the
// signature, the SubjectPublicKeyInfo, validity and extension OIDs) and to
// verify one certificate's ECDSA signature with another's key via WebCrypto.
//
// It is not a general-purpose PKI. It handles what Apple's App Store JWS
// chains contain (ECDSA P-256 / P-384, SHA-256 / SHA-384) and rejects
// anything else loudly. Name constraints, CRLs and OCSP are out of scope:
// Apple's guidance for offline verification is chain + pinned root + the two
// Apple OIDs + validity at the signed date, which is what `verifyChain` does.

export interface DerNode {
  tag: number;
  /** Offset of the first content byte in `buf`. */
  start: number;
  /** Offset one past the last content byte. */
  end: number;
  /** Offset of the tag byte (so the whole TLV can be sliced). */
  tlvStart: number;
  buf: Uint8Array;
}

export function readNode(buf: Uint8Array, offset: number): DerNode {
  if (offset >= buf.length) throw new Error('der: truncated');
  const tag = buf[offset];
  let i = offset + 1;
  if (i >= buf.length) throw new Error('der: truncated length');
  let length = buf[i++];
  if (length & 0x80) {
    const count = length & 0x7f;
    if (count === 0 || count > 4) throw new Error('der: bad length');
    length = 0;
    for (let k = 0; k < count; k++) {
      if (i >= buf.length) throw new Error('der: truncated length');
      length = (length << 8) | buf[i++];
    }
  }
  const start = i;
  const end = start + length;
  if (end > buf.length) throw new Error('der: content overruns buffer');
  return { tag, start, end, tlvStart: offset, buf };
}

export function children(node: DerNode): DerNode[] {
  const out: DerNode[] = [];
  let i = node.start;
  while (i < node.end) {
    const child = readNode(node.buf, i);
    out.push(child);
    i = child.end;
  }
  return out;
}

export function slice(node: DerNode, includeHeader: boolean): Uint8Array {
  return node.buf.slice(includeHeader ? node.tlvStart : node.start, node.end);
}

export function readOid(node: DerNode): string {
  if (node.tag !== 0x06) throw new Error('der: not an OID');
  const bytes = slice(node, false);
  if (bytes.length === 0) throw new Error('der: empty OID');
  const parts: number[] = [];
  const first = bytes[0];
  parts.push(Math.floor(first / 40), first % 40);
  let value = 0;
  for (let i = 1; i < bytes.length; i++) {
    value = value * 128 + (bytes[i] & 0x7f);
    if ((bytes[i] & 0x80) === 0) {
      parts.push(value);
      value = 0;
    }
  }
  return parts.join('.');
}

function readTime(node: DerNode): number {
  const text = new TextDecoder().decode(slice(node, false));
  let year: number;
  let rest: string;
  if (node.tag === 0x17) {
    // UTCTime YYMMDDHHMMSSZ
    const yy = Number(text.slice(0, 2));
    year = yy >= 50 ? 1900 + yy : 2000 + yy;
    rest = text.slice(2);
  } else if (node.tag === 0x18) {
    // GeneralizedTime YYYYMMDDHHMMSSZ
    year = Number(text.slice(0, 4));
    rest = text.slice(4);
  } else {
    throw new Error('der: not a time');
  }
  const month = Number(rest.slice(0, 2));
  const day = Number(rest.slice(2, 4));
  const hour = Number(rest.slice(4, 6));
  const minute = Number(rest.slice(6, 8));
  const second = Number(rest.slice(8, 10));
  return Date.UTC(year, month - 1, day, hour, minute, second);
}

export const OID = Object.freeze({
  ecPublicKey: '1.2.840.10045.2.1',
  prime256v1: '1.2.840.10045.3.1.7',
  secp384r1: '1.3.132.0.34',
  ecdsaWithSha256: '1.2.840.10045.4.3.2',
  ecdsaWithSha384: '1.2.840.10045.4.3.3',
  basicConstraints: '2.5.29.19',
});

export interface ParsedCertificate {
  der: Uint8Array;
  tbs: Uint8Array;
  signatureAlgorithmOid: string;
  /** DER-encoded ECDSA signature (SEQUENCE { r, s }). */
  signature: Uint8Array;
  spki: Uint8Array;
  curve: 'P-256' | 'P-384';
  notBeforeMs: number;
  notAfterMs: number;
  extensionOids: string[];
  isCa: boolean;
}

export function parseCertificate(der: Uint8Array): ParsedCertificate {
  const cert = readNode(der, 0);
  if (cert.tag !== 0x30) throw new Error('x509: not a SEQUENCE');
  const [tbsNode, sigAlgNode, sigNode] = children(cert);
  if (!tbsNode || !sigAlgNode || !sigNode) throw new Error('x509: malformed certificate');

  const tbsChildren = children(tbsNode);
  let index = 0;
  if (tbsChildren[0]?.tag === 0xa0) index = 1; // [0] EXPLICIT version
  // serial(0) sigAlg(1) issuer(2) validity(3) subject(4) spki(5) ...
  const validity = tbsChildren[index + 3];
  const spkiNode = tbsChildren[index + 5];
  if (!validity || !spkiNode) throw new Error('x509: malformed tbsCertificate');
  const [notBefore, notAfter] = children(validity);

  const spkiChildren = children(spkiNode);
  const algorithm = children(spkiChildren[0]);
  const keyOid = readOid(algorithm[0]);
  if (keyOid !== OID.ecPublicKey) throw new Error(`x509: unsupported key algorithm ${keyOid}`);
  const curveOid = readOid(algorithm[1]);
  let curve: 'P-256' | 'P-384';
  if (curveOid === OID.prime256v1) curve = 'P-256';
  else if (curveOid === OID.secp384r1) curve = 'P-384';
  else throw new Error(`x509: unsupported curve ${curveOid}`);

  const extensionOids: string[] = [];
  let isCa = false;
  for (let k = index + 6; k < tbsChildren.length; k++) {
    const node = tbsChildren[k];
    if (node.tag !== 0xa3) continue; // [3] EXPLICIT extensions
    const extSeq = children(node)[0];
    for (const ext of children(extSeq)) {
      const parts = children(ext);
      const oid = readOid(parts[0]);
      extensionOids.push(oid);
      if (oid === OID.basicConstraints) {
        const octets = parts[parts.length - 1];
        const inner = readNode(slice(octets, false), 0);
        const flags = children(inner);
        isCa = flags.length > 0 && flags[0].tag === 0x01 && slice(flags[0], false)[0] !== 0;
      }
    }
  }

  const signatureBits = slice(sigNode, false);
  if (signatureBits[0] !== 0) throw new Error('x509: unexpected unused bits in signature');

  return {
    der,
    tbs: slice(tbsNode, true),
    signatureAlgorithmOid: readOid(children(sigAlgNode)[0]),
    signature: signatureBits.slice(1),
    spki: slice(spkiNode, true),
    curve,
    notBeforeMs: readTime(notBefore),
    notAfterMs: readTime(notAfter),
    extensionOids,
    isCa,
  };
}

export async function importSpki(spki: Uint8Array, curve: 'P-256' | 'P-384'): Promise<CryptoKey> {
  return crypto.subtle.importKey('spki', spki as BufferSource, { name: 'ECDSA', namedCurve: curve }, false, ['verify']);
}

/** DER ECDSA-Sig-Value { r INTEGER, s INTEGER } -> raw r||s as WebCrypto wants. */
export function derSignatureToRaw(der: Uint8Array, size: number): Uint8Array {
  const seq = readNode(der, 0);
  const [r, s] = children(seq);
  const out = new Uint8Array(size * 2);
  const put = (node: DerNode, at: number) => {
    let bytes = slice(node, false);
    while (bytes.length > size && bytes[0] === 0) bytes = bytes.slice(1);
    if (bytes.length > size) throw new Error('ecdsa: integer too long');
    out.set(bytes, at + size - bytes.length);
  };
  put(r, 0);
  put(s, size);
  return out;
}

function hashForSignatureOid(oid: string): 'SHA-256' | 'SHA-384' {
  if (oid === OID.ecdsaWithSha256) return 'SHA-256';
  if (oid === OID.ecdsaWithSha384) return 'SHA-384';
  throw new Error(`x509: unsupported signature algorithm ${oid}`);
}

/** Is `cert` signed by `issuer`'s key? */
export async function verifyCertificateSignature(cert: ParsedCertificate, issuer: ParsedCertificate): Promise<boolean> {
  const hash = hashForSignatureOid(cert.signatureAlgorithmOid);
  const key = await importSpki(issuer.spki, issuer.curve);
  const raw = derSignatureToRaw(cert.signature, issuer.curve === 'P-256' ? 32 : 48);
  return crypto.subtle.verify({ name: 'ECDSA', hash }, key, raw as BufferSource, cert.tbs as BufferSource);
}

export interface ChainPolicy {
  /** Lower-case hex SHA-256 of the trusted root's DER. */
  trustedRootSha256Hex: string;
  /** OIDs the leaf must carry (Apple: 1.2.840.113635.100.6.11.1). */
  requiredLeafOids: string[];
  /** OIDs at least one intermediate must carry (Apple: 1.2.840.113635.100.6.2.1). */
  requiredIntermediateOids: string[];
  /** The instant at which every certificate must be valid. */
  effectiveTimeMs: number;
}

export interface ChainResult {
  ok: boolean;
  reason: string;
  leaf: ParsedCertificate | null;
}

/**
 * Verifies `x5c` (leaf first, root last, base64 DER each) against a policy.
 * Returns the leaf on success; the caller verifies the JWS with its key.
 */
export async function verifyChain(x5c: string[], policy: ChainPolicy, sha256Hex: (b: Uint8Array) => Promise<string>, base64Decode: (s: string) => Uint8Array): Promise<ChainResult> {
  if (!Array.isArray(x5c) || x5c.length < 2) return { ok: false, reason: 'chain_too_short', leaf: null };
  let certs: ParsedCertificate[];
  try {
    certs = x5c.map((b64) => parseCertificate(base64Decode(b64)));
  } catch (error) {
    return { ok: false, reason: `unparseable_certificate: ${(error as Error).message}`, leaf: null };
  }
  const root = certs[certs.length - 1];
  const fingerprint = await sha256Hex(root.der);
  if (fingerprint !== policy.trustedRootSha256Hex.toLowerCase()) return { ok: false, reason: 'untrusted_root', leaf: null };

  for (let i = 0; i < certs.length; i++) {
    const cert = certs[i];
    if (policy.effectiveTimeMs < cert.notBeforeMs || policy.effectiveTimeMs > cert.notAfterMs) {
      return { ok: false, reason: `certificate_${i}_not_valid_at_effective_time`, leaf: null };
    }
    const issuer = i + 1 < certs.length ? certs[i + 1] : cert; // root is self-signed
    if (i + 1 < certs.length && !issuer.isCa) return { ok: false, reason: `certificate_${i + 1}_is_not_a_ca`, leaf: null };
    let signed = false;
    try {
      signed = await verifyCertificateSignature(cert, issuer);
    } catch (error) {
      return { ok: false, reason: `signature_check_failed_${i}: ${(error as Error).message}`, leaf: null };
    }
    if (!signed) return { ok: false, reason: `bad_signature_on_certificate_${i}`, leaf: null };
  }

  const leaf = certs[0];
  for (const oid of policy.requiredLeafOids) {
    if (!leaf.extensionOids.includes(oid)) return { ok: false, reason: `leaf_missing_oid_${oid}`, leaf: null };
  }
  const intermediates = certs.slice(1, -1);
  for (const oid of policy.requiredIntermediateOids) {
    if (!intermediates.some((c) => c.extensionOids.includes(oid))) return { ok: false, reason: `intermediate_missing_oid_${oid}`, leaf: null };
  }
  return { ok: true, reason: 'ok', leaf };
}
