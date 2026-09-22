import { sha256Hex, uuid } from '../util/crypto';
import type { LicensingRepository } from './repository';
import type { ActivationRequest, AiPool, DeviceActivation, LicenseView, SchoolLicense } from './types';
import { LicensingError } from './types';

export interface LicensingServiceOptions {
  now?: () => Date;
  id?: () => string;
  hashCredential?: (value: string) => Promise<string>;
}

export async function hashLicenseCredential(value: string): Promise<string> {
  return sha256Hex(`little-days-school-license\n${value.trim()}`);
}

const FEATURES = {
  SCHOOL_STANDARD: ['school_access', 'classes', 'assignments', 'progress'],
  SCHOOL_AI: ['school_access', 'classes', 'assignments', 'progress', 'standard_ai'],
  SCHOOL_PREMIUM: ['school_access', 'classes', 'assignments', 'progress', 'standard_ai', 'premium_live'],
} as const;

export class SchoolLicensingService {
  private now: () => Date;
  private id: () => string;
  private hash: (value: string) => Promise<string>;

  constructor(private repo: LicensingRepository, options: LicensingServiceOptions = {}) {
    this.now = options.now ?? (() => new Date());
    this.id = options.id ?? uuid;
    this.hash = options.hashCredential ?? hashLicenseCredential;
  }

  async redeemCode(input: Omit<ActivationRequest, 'licenseId'> & { code: string }): Promise<LicenseView> {
    const normalized = input.code.trim();
    if (normalized.length < 8 || normalized.length > 512) throw new LicensingError('invalid_code', 'Activation code is invalid.');
    const license = await this.repo.findLicenseByCredentialHash(await this.hash(normalized));
    if (!license) throw new LicensingError('invalid_code', 'Activation code is invalid.');
    const activation = await this.activate({ ...input, licenseId: license.id });
    return this.view(license.id, input.accountId, activation.installationId);
  }

  async activate(input: ActivationRequest): Promise<DeviceActivation> {
    if (!input.accountId || !input.seatKey || !input.idempotencyKey) throw new LicensingError('invalid_request', 'Account, seat and idempotency key are required.');
    const existingRequest = await this.repo.getIdempotent(`activate:${input.accountId}`, input.idempotencyKey);
    if (existingRequest) {
      if (existingRequest.licenseId !== input.licenseId) throw new LicensingError('idempotency_conflict', 'Idempotency key was reused.');
      return existingRequest;
    }
    return this.repo.runExclusive(input.licenseId, async () => {
      const repeated = await this.repo.getIdempotent(`activate:${input.accountId}`, input.idempotencyKey);
      if (repeated) return repeated;
      const license = await this.requireUsable(input.licenseId);
      const installationId = input.installationId || this.id();
      const existingDevice = await this.repo.findActivationByInstallation(license.id, installationId);
      if (existingDevice) {
        if (existingDevice.accountId !== input.accountId || existingDevice.seatKey !== input.seatKey) throw new LicensingError('activation_conflict', 'Installation is already assigned.');
        await this.repo.saveIdempotent(`activate:${input.accountId}`, input.idempotencyKey, existingDevice);
        return existingDevice;
      }
      const active = await this.repo.listActiveActivations(license.id);
      const seats = new Set(active.map((x) => x.seatKey));
      if (!seats.has(input.seatKey) && seats.size >= license.seatCount) throw new LicensingError('seat_limit', 'No school seats remain.');
      if (active.length >= license.deviceLimit) throw new LicensingError('device_limit', 'No school device activations remain.');
      if (input.managedDeviceId && active.some((x) => x.managedDeviceId === input.managedDeviceId)) throw new LicensingError('managed_device_conflict', 'Managed device is already active.');
      const activation: DeviceActivation = {
        id: this.id(), licenseId: license.id, schoolId: license.schoolId, accountId: input.accountId,
        installationId, seatKey: input.seatKey, mode: input.managedDeviceId ? 'managed_device' : 'installation',
        managedDeviceId: input.managedDeviceId, activatedAt: this.now().toISOString(), deactivatedAt: null,
      };
      await this.repo.saveActivation(activation);
      await this.repo.saveIdempotent(`activate:${input.accountId}`, input.idempotencyKey, activation);
      return activation;
    });
  }

  async deactivate(accountId: string, activationId: string): Promise<DeviceActivation> {
    const activation = await this.repo.getActivation(activationId);
    if (!activation || activation.accountId !== accountId) throw new LicensingError('not_found', 'Activation was not found.');
    if (!activation.deactivatedAt) {
      activation.deactivatedAt = this.now().toISOString();
      await this.repo.saveActivation(activation);
    }
    return activation;
  }

  async status(accountId: string, installationId: string): Promise<LicenseView | null> {
    for (const licenseId of await this.findLicenseIds()) {
      const activation = await this.repo.findActivationByInstallation(licenseId, installationId);
      if (activation?.accountId === accountId) return this.view(licenseId, accountId, installationId);
    }
    return null;
  }

  async view(licenseId: string, accountId: string, installationId: string): Promise<LicenseView> {
    const license = await this.repo.getLicense(licenseId);
    if (!license) throw new LicensingError('not_found', 'License was not found.');
    const activation = await this.repo.findActivationByInstallation(licenseId, installationId);
    if (!activation || activation.accountId !== accountId) throw new LicensingError('not_found', 'License was not found.');
    return {
      licenseId, schoolId: license.schoolId, entitlement: license.entitlement,
      features: [...FEATURES[license.entitlement], ...license.featureFlags], validUntil: license.validUntil,
      active: this.isUsable(license), activation,
      usage: this.usage(license),
    };
  }

  async consumeAiPool(licenseId: string, pool: AiPool, seconds: number): Promise<LicenseView['usage']> {
    if (!Number.isInteger(seconds) || seconds <= 0) throw new LicensingError('invalid_usage', 'Usage must be positive whole seconds.');
    return this.repo.runExclusive(licenseId, async () => {
      const license = await this.requireUsable(licenseId);
      if (pool === 'premium_live' && license.entitlement !== 'SCHOOL_PREMIUM') throw new LicensingError('feature_not_entitled', 'Premium Live is not included.');
      if (pool === 'standard_ai' && license.entitlement === 'SCHOOL_STANDARD') throw new LicensingError('feature_not_entitled', 'Standard AI is not included.');
      const usedKey = pool === 'standard_ai' ? 'standardAiUsedSeconds' : 'premiumLiveUsedSeconds';
      const totalKey = pool === 'standard_ai' ? 'standardAiPoolSeconds' : 'premiumLivePoolSeconds';
      if (license[usedKey] + seconds > license[totalKey]) throw new LicensingError('pool_exhausted', 'School AI pool is exhausted.');
      license[usedKey] += seconds;
      await this.repo.saveLicense(license);
      return this.usage(license);
    });
  }

  private async requireUsable(id: string): Promise<SchoolLicense> {
    const license = await this.repo.getLicense(id);
    if (!license) throw new LicensingError('not_found', 'License was not found.');
    if (!this.isUsable(license)) throw new LicensingError('license_inactive', 'School license is not active.');
    return license;
  }

  private isUsable(license: SchoolLicense): boolean {
    const now = this.now().getTime();
    return license.status === 'active' && Date.parse(license.validFrom) <= now && now < Date.parse(license.validUntil);
  }

  private usage(license: SchoolLicense): LicenseView['usage'] {
    return {
      standardAi: { usedSeconds: license.standardAiUsedSeconds, remainingSeconds: Math.max(0, license.standardAiPoolSeconds - license.standardAiUsedSeconds) },
      premiumLive: { usedSeconds: license.premiumLiveUsedSeconds, remainingSeconds: Math.max(0, license.premiumLivePoolSeconds - license.premiumLiveUsedSeconds) },
    };
  }

  private async findLicenseIds(): Promise<string[]> {
    return this.repo.listLicenseIds();
  }
}
