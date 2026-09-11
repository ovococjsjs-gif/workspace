import type { AttackKind, Dir, Fighter, Weapon } from './types';
import { COST } from './types';
import { timings, PARRY_WINDOW, DODGE_TIME, STAGGER } from './rules';

export function makeFighter(id: string, weapon: Weapon, hp = 100, st = 100): Fighter {
  return { id, hp, maxHp: hp, st, maxSt: st, weapon, dir: 'R', phase: 'idle', t: 0, kind: 'light', hitDone: false, facingLock: false };
}

export const canAct = (f: Fighter) => f.phase === 'idle' || f.phase === 'block';

export function startAttack(f: Fighter, kind: AttackKind, dir: Dir): boolean {
  if (!canAct(f) || f.st < COST[kind] * 0.5) return false;
  f.st = Math.max(0, f.st - COST[kind]); f.kind = kind; f.dir = dir;
  f.phase = 'windup'; f.t = 0; f.hitDone = false; return true;
}
export function startBlock(f: Fighter, dir: Dir) {
  if (f.phase !== 'idle') return; f.dir = dir; f.phase = 'parry'; f.t = 0;
}
export function stopBlock(f: Fighter) { if (f.phase === 'block' || f.phase === 'parry') { f.phase = 'idle'; f.t = 0; } }
export function startDodge(f: Fighter): boolean {
  if (!canAct(f) || f.st < COST.dodge) return false;
  f.st -= COST.dodge; f.phase = 'dodge'; f.t = 0; return true;
}
export function stagger(f: Fighter) { f.phase = 'stagger'; f.t = 0; }
export function damage(f: Fighter, d: number) { f.hp = Math.max(0, f.hp - d); if (f.hp === 0) { f.phase = 'dead'; f.t = 0; } }

/** Обновление фаз; возвращает true в момент начала active-фазы. */
export function tick(f: Fighter, dt: number, holdingBlock: boolean): void {
  f.t += dt;
  if (f.phase === 'dead') return;
  // реген стамины (не во время атаки)
  const regen = f.phase === 'idle' ? 22 : f.phase === 'block' ? 8 : 0;
  f.st = Math.min(f.maxSt, f.st + regen * dt);
  const tm = timings(f.weapon, f.kind);
  switch (f.phase) {
    case 'windup': if (f.t >= tm.windup) { f.phase = 'active'; f.t = 0; } break;
    case 'active': if (f.t >= tm.active) { f.phase = 'recover'; f.t = 0; } break;
    case 'recover': if (f.t >= tm.recover) { f.phase = 'idle'; f.t = 0; } break;
    case 'parry': if (f.t >= PARRY_WINDOW) { f.phase = holdingBlock ? 'block' : 'idle'; f.t = 0; } break;
    case 'block': if (!holdingBlock) { f.phase = 'idle'; f.t = 0; } break;
    case 'dodge': if (f.t >= DODGE_TIME) { f.phase = 'idle'; f.t = 0; } break;
    case 'stagger': if (f.t >= STAGGER) { f.phase = 'idle'; f.t = 0; } break;
  }
}

export const WEAPONS: Record<string, Weapon> = {
  arming: { name: 'Меч рыцаря', length: 0.85, width: 0.05, weight: 1.3, quality: 0.85, damage: 22 },
  rusty: { name: 'Ржавый клинок', length: 0.75, width: 0.05, weight: 1.2, quality: 0.35, damage: 16 },
  great: { name: 'Двуручник', length: 1.25, width: 0.07, weight: 2.6, quality: 0.7, damage: 34 },
};
