// Bundled content: the SAME files the game ships, imported at build time so
// the Worker needs no filesystem and the server stays the lesson authority
// (security finding M2 in docs/ALIZ_TUTOR_SECURITY_FINDINGS.md). Add a line
// here when a lesson file is added under game/content/tutor/lessons/.
import allowlistFile from '../../../game/content/tutor/assets_allowlist.json';
import animals from '../../../game/content/tutor/lessons/animals_cat_dog.json';
import colors from '../../../game/content/tutor/lessons/colors_red_blue.json';
import englishColorsFruits from '../../../game/content/tutor/lessons/english_colors_fruits.json';
import everyday from '../../../game/content/tutor/lessons/everyday_cup_spoon.json';
import numbers from '../../../game/content/tutor/lessons/numbers_one_two_three.json';
import welcome from '../../../game/content/tutor/lessons/welcome_choose.json';
import { DEFAULT_ASSET_ALLOWLIST } from './turn_validator';

export const RAW_LESSONS: unknown[] = [animals, colors, englishColorsFruits, everyday, numbers, welcome];

function readAllowlist(raw: unknown): { ids: string[]; source: 'file' | 'default' } {
  const r = raw as Record<string, unknown> | unknown[];
  const list = Array.isArray(r) ? r : (r.assets ?? r.allowlist ?? r.ids ?? r.assetIds);
  if (Array.isArray(list)) {
    const ids = list
      .map((entry) => (typeof entry === 'string' ? entry : entry && ((entry as Record<string, unknown>).id ?? (entry as Record<string, unknown>).assetId)))
      .filter((id): id is string => typeof id === 'string' && id.length > 0);
    if (ids.length) return { ids, source: 'file' };
  }
  return { ids: [...DEFAULT_ASSET_ALLOWLIST], source: 'default' };
}

export const ASSET_ALLOWLIST = readAllowlist(allowlistFile);
