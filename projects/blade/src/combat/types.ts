export type Dir = 'L' | 'R' | 'O' | 'T'; // слева, справа, сверху (overhead), укол (thrust)
export type AttackKind = 'light' | 'heavy';

export interface Weapon {
  name: string;
  length: number;   // м — дальность
  width: number;    // м — визуал
  weight: number;   // кг — скорость и импульс при столкновении
  quality: number;  // 0..1 — выигрыш в столкновении клинков, шанс отбить
  damage: number;
}

export type Phase = 'idle' | 'windup' | 'active' | 'recover' | 'block' | 'parry' | 'dodge' | 'stagger' | 'dead';

export interface Fighter {
  id: string;
  hp: number; maxHp: number;
  st: number; maxSt: number;
  weapon: Weapon;
  dir: Dir;               // текущее направление клинка / стойки
  phase: Phase; t: number; // время внутри фазы
  kind: AttackKind;        // тип текущей атаки
  hitDone: boolean;        // чтобы атака засчиталась один раз
  facingLock: boolean;
}

export const COST = { light: 18, heavy: 34, block: 12, parryOk: -10, dodge: 22, clashLose: 15 } as const;
