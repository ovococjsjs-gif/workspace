import type { AttackKind, Dir, Fighter, Weapon } from './types';
import { COST } from './types';

/** Тайминги фаз (сек). Тяжёлая — медленнее, зависит от веса оружия. */
export function timings(w: Weapon, kind: AttackKind) {
  const k = 0.85 + w.weight * 0.1;
  return kind === 'light'
    ? { windup: 0.22 * k, active: 0.12, recover: 0.30 * k }
    : { windup: 0.48 * k, active: 0.16, recover: 0.55 * k };
}
export const PARRY_WINDOW = 0.16; // сек после нажатия блока — парирование
export const DODGE_TIME = 0.42; export const DODGE_IFRAMES: [number, number] = [0.05, 0.30];
export const STAGGER = 0.7;

/** Противоположные направления: клинки встречаются, если атакующий бьёт в сторону, где стоит клинок обороняющегося. */
export function opposes(a: Dir, b: Dir): boolean {
  // зеркало: удар слева (L) встречает клинок, стоящий справа у оппонента с его точки зрения — L<->R; верх и укол — только сами с собой.
  return (a === 'L' && b === 'R') || (a === 'R' && b === 'L') || (a === 'O' && b === 'O') || (a === 'T' && b === 'T');
}

export type Outcome =
  | { type: 'hit'; dmg: number }
  | { type: 'blocked'; stDrain: number; breaks: boolean }
  | { type: 'parried' }
  | { type: 'dodged' }
  | { type: 'clash'; winner: 'att' | 'def' | 'none' };

/** Сила атаки в столкновении клинков. */
export function clashPower(f: Fighter, kind: AttackKind): number {
  const w = f.weapon;
  const base = kind === 'heavy' ? 1.6 : 1.0;
  const stam = 0.6 + 0.4 * (f.st / f.maxSt);          // усталость ослабляет
  return base * (0.7 + w.weight * 0.15) * (0.7 + w.quality * 0.6) * stam;
}

/** Разрешение удара атакующего `att` по `def` в момент активной фазы. */
export function resolve(att: Fighter, def: Fighter, rnd = Math.random): Outcome {
  // 1. уворот
  if (def.phase === 'dodge' && def.t >= DODGE_IFRAMES[0] && def.t <= DODGE_IFRAMES[1]) return { type: 'dodged' };
  // 2. встречный удар — столкновение клинков, если направления совпали
  if ((def.phase === 'windup' || def.phase === 'active') && opposes(att.dir, def.dir)) {
    const pa = clashPower(att, att.kind), pd = clashPower(def, def.kind);
    const ratio = pa / (pa + pd);
    const r = rnd();
    const winner = r < ratio - 0.15 ? 'att' : r > ratio + 0.15 ? 'def' : 'none';
    return { type: 'clash', winner };
  }
  // 3. парирование: блок поставлен только что и в нужную сторону
  if (def.phase === 'parry' && opposes(att.dir, def.dir)) return { type: 'parried' };
  // 4. блок: клинок в нужную сторону; тяжёлая атака и низкая стамина могут пробить
  if ((def.phase === 'block' || def.phase === 'parry') && opposes(att.dir, def.dir)) {
    const drain = COST.block + (att.kind === 'heavy' ? 22 : 6) * (0.8 + att.weapon.weight * 0.1) * (1.1 - def.weapon.quality * 0.3);
    const breaks = def.st - drain <= 0;
    return { type: 'blocked', stDrain: drain, breaks };
  }
  // 5. попадание; направление, куда не выставлен клинок, — чистое
  const mult = att.kind === 'heavy' ? 1.7 : 1.0;
  const q = 0.75 + att.weapon.quality * 0.35;
  return { type: 'hit', dmg: Math.round(att.weapon.damage * mult * q) };
}
