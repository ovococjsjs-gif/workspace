import type { Fighter, Dir } from './combat/types';
import { startAttack, startBlock, stopBlock, startDodge, canAct } from './combat/fighter';

const DIRS: Dir[] = ['L', 'R', 'O', 'T'];
/** Простой, но читаемый ИИ: держит дистанцию, чаще ставит клинок навстречу твоему, иногда бьёт и парирует. */
export class Brain {
  cool = 0.8; holdBlock = false; blockT = 0;
  constructor(private aggro = 0.5, private skill = 0.5) {}
  update(me: Fighter, foe: Fighter, dist: number, dt: number): { move: number; holdBlock: boolean } {
    this.cool -= dt; let move = 0;
    if (me.phase === 'dead') return { move: 0, holdBlock: false };
    // дистанция: держимся чуть ближе длины клинка
    const want = me.weapon.length + 0.6;
    if (dist > want + 0.3) move = 1; else if (dist < want - 0.4) move = -1;
    // реакция на замах противника
    if (foe.phase === 'windup' && canAct(me) && Math.random() < this.skill * dt * 14) {
      const r = Math.random();
      if (r < 0.45) { me.dir = mirror(foe.dir); startBlock(me, me.dir); this.holdBlock = true; this.blockT = 0.5; }
      else if (r < 0.65) startDodge(me);
      else if (dist < me.weapon.length + 0.5) startAttack(me, 'light', mirror(foe.dir)); // встречный — на столкновение
    }
    if (this.holdBlock) { this.blockT -= dt; if (this.blockT <= 0) { this.holdBlock = false; stopBlock(me); } }
    // собственная атака
    if (this.cool <= 0 && canAct(me) && dist < me.weapon.length + 0.7 && me.st > 30) {
      if (this.holdBlock) { this.holdBlock = false; stopBlock(me); }
      // бьём туда, где у противника НЕТ клинка (умный) или наугад
      let d: Dir = DIRS[(Math.random() * 4) | 0];
      if (Math.random() < this.skill) { const open = DIRS.filter(x => x !== mirror(foe.dir)); d = open[(Math.random() * open.length) | 0]; }
      startAttack(me, Math.random() < this.aggro * 0.5 ? 'heavy' : 'light', d);
      this.cool = 0.9 + Math.random() * 1.2 * (1.3 - this.aggro);
    }
    if (me.st < 20) move = -1; // отступаем восстановиться
    return { move, holdBlock: this.holdBlock };
  }
}
/** Какое направление клинка нужно, чтобы встретить удар с направлением d. */
export function mirror(d: Dir): Dir { return d === 'L' ? 'R' : d === 'R' ? 'L' : d; }
