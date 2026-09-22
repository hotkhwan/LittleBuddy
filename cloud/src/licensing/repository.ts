import type { DeviceActivation, Organization, School, SchoolClass, SchoolLicense } from './types';

export interface LicensingRepository {
  getOrganization(id: string): Promise<Organization | null>;
  getSchool(id: string): Promise<School | null>;
  getClass(id: string): Promise<SchoolClass | null>;
  getLicense(id: string): Promise<SchoolLicense | null>;
  findLicenseByCredentialHash(hash: string): Promise<SchoolLicense | null>;
  saveLicense(license: SchoolLicense): Promise<void>;
  listActiveActivations(licenseId: string): Promise<DeviceActivation[]>;
  getActivation(id: string): Promise<DeviceActivation | null>;
  findActivationByInstallation(licenseId: string, installationId: string): Promise<DeviceActivation | null>;
  saveActivation(activation: DeviceActivation): Promise<void>;
  getIdempotent(scope: string, key: string): Promise<DeviceActivation | null>;
  saveIdempotent(scope: string, key: string, activation: DeviceActivation): Promise<void>;
  listLicenseIds(): Promise<string[]>;
  runExclusive<T>(licenseId: string, operation: () => Promise<T>): Promise<T>;
}

export class InMemoryLicensingRepository implements LicensingRepository {
  organizations = new Map<string, Organization>();
  schools = new Map<string, School>();
  classes = new Map<string, SchoolClass>();
  licenses = new Map<string, SchoolLicense>();
  activations = new Map<string, DeviceActivation>();
  private idempotency = new Map<string, DeviceActivation>();
  private locks = new Map<string, Promise<void>>();

  async getOrganization(id: string) { return this.organizations.get(id) ?? null; }
  async getSchool(id: string) { return this.schools.get(id) ?? null; }
  async getClass(id: string) { return this.classes.get(id) ?? null; }
  async getLicense(id: string) { const v = this.licenses.get(id); return v ? structuredClone(v) : null; }
  async findLicenseByCredentialHash(hash: string) {
    for (const license of this.licenses.values()) {
      if (license.activationCodeHash === hash || license.qrTokenHash === hash) return structuredClone(license);
    }
    return null;
  }
  async saveLicense(license: SchoolLicense) { this.licenses.set(license.id, structuredClone(license)); }
  async listActiveActivations(licenseId: string) {
    return [...this.activations.values()].filter((x) => x.licenseId === licenseId && !x.deactivatedAt).map((x) => structuredClone(x));
  }
  async getActivation(id: string) { const v = this.activations.get(id); return v ? structuredClone(v) : null; }
  async findActivationByInstallation(licenseId: string, installationId: string) {
    const value = [...this.activations.values()].find((x) => x.licenseId === licenseId && x.installationId === installationId && !x.deactivatedAt);
    return value ? structuredClone(value) : null;
  }
  async saveActivation(activation: DeviceActivation) { this.activations.set(activation.id, structuredClone(activation)); }
  async getIdempotent(scope: string, key: string) { const value = this.idempotency.get(`${scope}:${key}`); return value ? structuredClone(value) : null; }
  async saveIdempotent(scope: string, key: string, activation: DeviceActivation) { this.idempotency.set(`${scope}:${key}`, structuredClone(activation)); }
  async listLicenseIds() { return [...this.licenses.keys()]; }
  async runExclusive<T>(licenseId: string, operation: () => Promise<T>): Promise<T> {
    const previous = this.locks.get(licenseId) ?? Promise.resolve();
    let release!: () => void;
    const current = new Promise<void>((resolve) => { release = resolve; });
    const queued = previous.then(() => current);
    this.locks.set(licenseId, queued);
    await previous;
    try { return await operation(); } finally {
      release();
      if (this.locks.get(licenseId) === queued) this.locks.delete(licenseId);
    }
  }
}
