export type SchoolEntitlement = 'SCHOOL_STANDARD' | 'SCHOOL_AI' | 'SCHOOL_PREMIUM';
export type LicenseStatus = 'draft' | 'active' | 'suspended' | 'expired' | 'revoked';
export type LicenseMode = 'per_seat' | 'per_device' | 'pooled';
export type ActivationMode = 'installation' | 'managed_device';

export interface Organization { id: string; name: string; }
export interface School { id: string; organizationId: string; name: string; }
export interface SchoolClass { id: string; schoolId: string; name: string; }
export interface LicenseSeat {
  id: string;
  licenseId: string;
  schoolClassId?: string;
  seatKey: string;
  assignedAt: string;
  releasedAt: string | null;
}
export interface SchoolAiPool {
  licenseId: string;
  kind: 'standard_ai' | 'premium_live';
  allocatedSeconds: number;
  usedSeconds: number;
}

export interface SchoolLicense {
  id: string;
  organizationId: string;
  schoolId: string;
  entitlement: SchoolEntitlement;
  mode: LicenseMode;
  status: LicenseStatus;
  validFrom: string;
  validUntil: string;
  seatCount: number;
  deviceLimit: number;
  standardAiPoolSeconds: number;
  premiumLivePoolSeconds: number;
  standardAiUsedSeconds: number;
  premiumLiveUsedSeconds: number;
  featureFlags: string[];
  activationCodeHash?: string;
  qrTokenHash?: string;
}

export interface DeviceActivation {
  id: string;
  licenseId: string;
  schoolId: string;
  accountId: string;
  installationId: string;
  seatKey: string;
  mode: ActivationMode;
  managedDeviceId?: string;
  activatedAt: string;
  deactivatedAt: string | null;
}

export interface ActivationRequest {
  accountId: string;
  licenseId: string;
  seatKey: string;
  installationId?: string;
  managedDeviceId?: string;
  idempotencyKey: string;
}

export interface LicenseView {
  licenseId: string;
  schoolId: string;
  entitlement: SchoolEntitlement;
  features: string[];
  validUntil: string;
  active: boolean;
  activation?: DeviceActivation;
  usage: {
    standardAi: { usedSeconds: number; remainingSeconds: number };
    premiumLive: { usedSeconds: number; remainingSeconds: number };
  };
}

export type AiPool = 'standard_ai' | 'premium_live';

export class LicensingError extends Error {
  constructor(readonly code: string, message: string) { super(message); }
}
