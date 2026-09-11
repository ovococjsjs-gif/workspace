import * as T from 'three';
import type { Rig } from './models/humanoid';
import type { Fighter, Dir } from './combat/types';
import { timings, PARRY_WINDOW, DODGE_TIME } from './combat/rules';

const lerp = T.MathUtils.lerp, damp = T.MathUtils.damp;
const ease = (t: number) => t * t * (3 - 2 * t);

/** Целевые углы правой руки (плечо x,y,z; локоть x) для позы клинка по направлению. */
function stancePose(dir: Dir): [number, number, number, number] {
  switch (dir) {
    case 'L': return [-0.9, 0.0, 0.9, -1.2];
    case 'R': return [-0.9, 0.0, -0.5, -1.3];
    case 'O': return [-2.4, 0.0, 0.3, -0.9];
    case 'T': return [-1.3, 0.0, 0.1, -1.5];
  }
}
function swingPose(dir: Dir): [number, number, number, number] {
  switch (dir) {
    case 'L': return [-1.3, 0.0, -1.0, -0.2];
    case 'R': return [-1.3, 0.0, 1.2, -0.2];
    case 'O': return [-0.3, 0.0, 0.0, -0.1];
    case 'T': return [-1.55, 0.0, 0.0, 0.0];
  }
}

export interface AnimState { walk: number; lean: number; }

export function animate(rig: Rig, f: Fighter, dt: number, speed: number, moveDir: T.Vector3, st: AnimState) {
  st.walk += dt * speed * 6;
  const wAmp = Math.min(1, speed / 3);
  // ноги
  const s = Math.sin(st.walk), c = Math.sin(st.walk + Math.PI);
  rig.rLeg.rotation.x = s * 0.6 * wAmp; rig.lLeg.rotation.x = c * 0.6 * wAmp;
  rig.rShin.rotation.x = Math.max(0, -s) * 0.9 * wAmp; rig.lShin.rotation.x = Math.max(0, -c) * 0.9 * wAmp;
  rig.hips.position.y = 0.95 + Math.abs(Math.sin(st.walk)) * 0.04 * wAmp;
  rig.lArm.rotation.x = c * 0.4 * wAmp - 0.2; rig.lFore.rotation.x = -0.4;

  // правая рука: по фазе
  let target = stancePose(f.dir); let torsoY = 0, torsoX = 0; let k = 14;
  const tm = timings(f.weapon, f.kind);
  const sw = swingPose(f.dir), sp = stancePose(f.dir);
  const yawDir = f.dir === 'L' ? 1 : f.dir === 'R' ? -1 : 0;
  if (f.phase === 'windup') {
    const p = ease(Math.min(1, f.t / tm.windup)); const over = f.kind === 'heavy' ? 1.35 : 1.1;
    target = sp.map((v, i) => v * over + (i === 0 ? -0.2 * p : 0)) as typeof sp; torsoY = -yawDir * 0.5 * p; torsoX = f.dir === 'O' ? -0.25 * p : 0; k = 18;
  } else if (f.phase === 'active') {
    const p = ease(Math.min(1, f.t / tm.active));
    target = sp.map((v, i) => lerp(v, sw[i], p)) as typeof sp; torsoY = yawDir * 0.6 * p - yawDir * 0.5 * (1 - p); torsoX = f.dir === 'O' ? 0.35 * p : f.dir === 'T' ? 0.2 * p : 0; k = 60;
  } else if (f.phase === 'recover') {
    const p = ease(Math.min(1, f.t / tm.recover));
    target = sw.map((v, i) => lerp(v, sp[i], p)) as typeof sp; torsoY = yawDir * 0.6 * (1 - p); torsoX = (f.dir === 'O' ? 0.35 : f.dir === 'T' ? 0.2 : 0) * (1 - p); k = 10;
  } else if (f.phase === 'block' || f.phase === 'parry') {
    const b = stancePose(f.dir); target = [b[0] - 0.4, b[1], b[2] * 0.6, b[3] - 0.3];
    if (f.phase === 'parry') { const p = 1 - f.t / PARRY_WINDOW; target[2] += yawDir * 0.5 * p; }
    k = 30;
  } else if (f.phase === 'dodge') {
    const p = f.t / DODGE_TIME; rig.hips.position.y = 0.95 - Math.sin(p * Math.PI) * 0.25; torsoX = 0.5 * Math.sin(p * Math.PI);
  } else if (f.phase === 'stagger') {
    torsoX = -0.35 * Math.sin(Math.min(1, f.t / 0.7) * Math.PI); target = [-0.3, 0.5, -0.8, -0.6];
  } else if (f.phase === 'dead') {
    const p = Math.min(1, f.t / 0.6); rig.root.rotation.x = -Math.PI / 2 * ease(p); rig.hips.position.y = lerp(0.95, 0.25, ease(p)); return;
  }
  rig.rArm.rotation.x = damp(rig.rArm.rotation.x, target[0], k, dt);
  rig.rArm.rotation.y = damp(rig.rArm.rotation.y, target[1], k, dt);
  rig.rArm.rotation.z = damp(rig.rArm.rotation.z, target[2], k, dt);
  rig.rFore.rotation.x = damp(rig.rFore.rotation.x, target[3], k, dt);
  rig.torso.rotation.y = damp(rig.torso.rotation.y, torsoY, k, dt);
  rig.torso.rotation.x = damp(rig.torso.rotation.x, torsoX + st.lean, k, dt);
  // наклон в сторону движения
  st.lean = damp(st.lean, moveDir.length() * 0.12, 6, dt);
}
