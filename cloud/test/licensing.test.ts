import { describe, expect, it } from 'vitest';
import {
  InMemoryLicensingRepository, LicensingError, SchoolLicensingService, hashLicenseCredential,
  type SchoolEntitlement, type SchoolLicense,
} from '../src/licensing';

const NOW = new Date('2026-09-22T00:00:00.000Z');

async function setup(overrides: Partial<SchoolLicense> = {}) {
  const repo = new InMemoryLicensingRepository();
  repo.organizations.set('org-a', { id: 'org-a', name: 'Learning Group' });
  repo.schools.set('school-a', { id: 'school-a', organizationId: 'org-a', name: 'Little School' });
  repo.classes.set('class-a', { id: 'class-a', schoolId: 'school-a', name: 'Sunflowers' });
  const license: SchoolLicense = {
    id: 'license-a', organizationId: 'org-a', schoolId: 'school-a', entitlement: 'SCHOOL_PREMIUM', mode: 'pooled',
    status: 'active', validFrom: '2026-09-01T00:00:00.000Z', validUntil: '2027-09-01T00:00:00.000Z',
    seatCount: 2, deviceLimit: 3, standardAiPoolSeconds: 100, premiumLivePoolSeconds: 50,
    standardAiUsedSeconds: 0, premiumLiveUsedSeconds: 0, featureFlags: ['custom_lessons'],
    activationCodeHash: await hashLicenseCredential('ABCD-1234'), qrTokenHash: await hashLicenseCredential('qr-secret-token'), ...overrides,
  };
  await repo.saveLicense(license);
  let sequence = 0;
  const service = new SchoolLicensingService(repo, { now: () => NOW, id: () => `random-id-${++sequence}` });
  return { repo, service, license };
}

const activation = (n = 1) => ({ accountId: `account-${n}`, licenseId: 'license-a', seatKey: `student-${n}`, installationId: `install-${n}`, idempotencyKey: `idem-${n}` });
const rejectsCode = async (promise: Promise<unknown>, code: string) => {
  await expect(promise).rejects.toMatchObject({ code });
};

describe('school license activation', () => {
  it('redeems hashed short and QR credentials without storing plaintext', async () => {
    const { repo, service } = await setup();
    const short = await service.redeemCode({ ...activation(1), code: 'ABCD-1234' });
    expect(short.active).toBe(true);
    expect(short.features).toContain('premium_live');
    expect(short.features).toContain('custom_lessons');
    await service.redeemCode({ ...activation(2), code: 'qr-secret-token' });
    expect((await repo.getLicense('license-a'))?.activationCodeHash).not.toContain('ABCD-1234');
  });

  it('rejects an invalid code and expired, suspended, or future licenses', async () => {
    const { service } = await setup();
    await rejectsCode(service.redeemCode({ ...activation(), code: 'WRONG-000' }), 'invalid_code');
    for (const patch of [
      { validUntil: '2026-09-22T00:00:00.000Z' }, { status: 'suspended' as const }, { validFrom: '2026-10-01T00:00:00.000Z' },
    ]) {
      const fixture = await setup(patch);
      await rejectsCode(fixture.service.activate(activation()), 'license_inactive');
    }
  });

  it('enforces independent seat and device limits', async () => {
    const seats = await setup({ seatCount: 1, deviceLimit: 3 });
    await seats.service.activate(activation(1));
    await rejectsCode(seats.service.activate(activation(2)), 'seat_limit');
    const devices = await setup({ seatCount: 3, deviceLimit: 1 });
    await devices.service.activate(activation(1));
    await rejectsCode(devices.service.activate(activation(2)), 'device_limit');
  });

  it('is idempotent, supports generated installation IDs, and rejects cross-license key reuse', async () => {
    const { repo, service } = await setup();
    const input = { accountId: 'a', licenseId: 'license-a', seatKey: 's', idempotencyKey: 'same' };
    const first = await service.activate(input);
    const duplicate = await service.activate(input);
    expect(duplicate).toEqual(first);
    expect(first.installationId).toMatch(/^random-id-/);
    expect(await repo.listActiveActivations('license-a')).toHaveLength(1);
    await rejectsCode(service.activate({ ...input, licenseId: 'other' }), 'idempotency_conflict');
  });

  it('supports managed-device activation, deactivation, and idempotent deactivation', async () => {
    const { service } = await setup();
    const active = await service.activate({ ...activation(), managedDeviceId: 'mdm-opaque-17' });
    expect(active.mode).toBe('managed_device');
    expect((await service.status('account-1', 'install-1'))?.active).toBe(true);
    expect((await service.status('other-account', 'install-1'))).toBeNull();
    const stopped = await service.deactivate('account-1', active.id);
    expect(stopped.deactivatedAt).toBe(NOW.toISOString());
    expect(await service.deactivate('account-1', active.id)).toEqual(stopped);
  });

  it('isolates activation ownership and installation IDs', async () => {
    const { service } = await setup();
    const active = await service.activate(activation());
    await rejectsCode(service.deactivate('attacker', active.id), 'not_found');
    await rejectsCode(service.activate({ ...activation(2), installationId: 'install-1' }), 'activation_conflict');
  });
});

describe('school entitlement and AI pools', () => {
  it.each<[SchoolEntitlement, string[], string[]]>([
    ['SCHOOL_STANDARD', ['classes'], ['standard_ai', 'premium_live']],
    ['SCHOOL_AI', ['standard_ai'], ['premium_live']],
    ['SCHOOL_PREMIUM', ['standard_ai', 'premium_live'], []],
  ])('maps %s features', async (entitlement, present, absent) => {
    const { service } = await setup({ entitlement });
    await service.activate(activation());
    const view = await service.view('license-a', 'account-1', 'install-1');
    for (const feature of present) expect(view.features).toContain(feature);
    for (const feature of absent) expect(view.features).not.toContain(feature);
  });

  it('meters both pools, rejects overage, and enforces tier access', async () => {
    const { service } = await setup();
    expect((await service.consumeAiPool('license-a', 'standard_ai', 70)).standardAi.remainingSeconds).toBe(30);
    expect((await service.consumeAiPool('license-a', 'premium_live', 50)).premiumLive.remainingSeconds).toBe(0);
    await rejectsCode(service.consumeAiPool('license-a', 'premium_live', 1), 'pool_exhausted');
    const standard = await setup({ entitlement: 'SCHOOL_STANDARD' });
    await rejectsCode(standard.service.consumeAiPool('license-a', 'standard_ai', 1), 'feature_not_entitled');
  });

  it('serializes parallel activation and pool consumption to prevent quota bypass', async () => {
    const activations = await setup({ seatCount: 1, deviceLimit: 1 });
    const results = await Promise.allSettled([activations.service.activate(activation(1)), activations.service.activate(activation(2))]);
    expect(results.filter((x) => x.status === 'fulfilled')).toHaveLength(1);
    const pool = await setup({ standardAiPoolSeconds: 10 });
    const usage = await Promise.allSettled([pool.service.consumeAiPool('license-a', 'standard_ai', 7), pool.service.consumeAiPool('license-a', 'standard_ai', 7)]);
    expect(usage.filter((x) => x.status === 'fulfilled')).toHaveLength(1);
  });
});
