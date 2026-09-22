# School Licensing

School entitlement is contract-based and separate from consumer subscription state:

`Organization → School → License → Class → Seat/device → AI pool`

Supported tiers are `SCHOOL_STANDARD`, `SCHOOL_AI`, and `SCHOOL_PREMIUM`; modes are per-seat, per-device, and pooled. Licenses include validity, seat/device limits, Standard and Premium Live pools, status, and feature flags.

The licensing domain implements hashed short/QR credentials, random installation IDs, managed-device identifiers, account isolation, activation idempotency, deactivation, expiration, seat/device enforcement, and serialized quota/activation operations. It intentionally avoids invasive hardware fingerprints.

The normalized route contract is reserved as:

- `POST /v1/license/activate`
- `POST /v1/license/deactivate`
- `GET /v1/license/status`
- `POST /v1/school/code/redeem`

These routes must not be opened until the D1 repository and a strongly serialized production activation coordinator are wired. Closed production currently denies them. The service tests cover invalid codes, expiry, isolation, repeat activation, seat/device limits, managed devices, entitlement features, pool exhaustion, and parallel abuse.

