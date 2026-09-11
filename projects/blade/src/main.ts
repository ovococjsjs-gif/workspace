import * as T from 'three';
import { buildArena } from './arena';
import { makeHumanoid } from './models/humanoid';
import { makeSword } from './models/sword';
import { M } from './models/materials';
import { makeFighter, startAttack, startBlock, stopBlock, startDodge, tick, damage, stagger, WEAPONS } from './combat/fighter';
import { resolve } from './combat/rules';
import { COST, type Dir, type Fighter } from './combat/types';
import { animate, type AnimState } from './animate';
import { Brain } from './ai';

// ---------- сцена
const renderer = new T.WebGLRenderer({ antialias: true });
renderer.setPixelRatio(Math.min(devicePixelRatio, 2)); renderer.setSize(innerWidth, innerHeight);
renderer.shadowMap.enabled = true; renderer.shadowMap.type = T.PCFSoftShadowMap; renderer.toneMapping = T.ACESFilmicToneMapping; renderer.toneMappingExposure = 1.05;
document.body.appendChild(renderer.domElement);
const scene = new T.Scene(); const camera = new T.PerspectiveCamera(60, innerWidth / innerHeight, 0.1, 200);
const colliders = buildArena(scene);

// ---------- бойцы
interface Actor { f: Fighter; rig: ReturnType<typeof makeHumanoid>; sword: T.Group; pos: T.Vector3; yaw: number; anim: AnimState; vel: T.Vector3; }
function spawn(id: string, wkey: keyof typeof WEAPONS, pal: { cloth: T.Material; armor: T.Material }, x: number, z: number): Actor {
  const f = makeFighter(id, WEAPONS[wkey]); const rig = makeHumanoid(pal); const sword = makeSword(f.weapon);
  sword.rotation.x = -Math.PI / 2; sword.position.set(0, -0.02, 0.06); rig.hand.add(sword);
  rig.root.position.set(x, 0, z); scene.add(rig.root);
  return { f, rig, sword, pos: rig.root.position, yaw: 0, anim: { walk: 0, lean: 0 }, vel: new T.Vector3() };
}
let player = spawn('you', 'arming', { cloth: M.cloth, armor: M.clothB }, 0, 3);
let enemy = spawn('foe', 'rusty', { cloth: M.leather, armor: M.dark }, 0, -3);
let brain = new Brain(0.55, 0.6);

// ---------- ввод
const keys = new Set<string>(); let mouseDX = 0, mouseDY = 0; let lmb = false, rmb = false, lmbT = 0; let camYaw = 0, camPitch = 0.35; let locked = false;
let bladeDir: Dir = 'R'; let dirAccX = 0, dirAccY = 0;
addEventListener('keydown', e => { keys.add(e.code); if (e.code === 'KeyR') restart(); if (e.code === 'Space') { e.preventDefault(); if (startDodge(player.f)) dodgeVec.copy(moveVec.lengthSq() > 0 ? moveVec : back()); } });
addEventListener('keyup', e => keys.delete(e.code));
const start = document.getElementById('start')!;
start.onclick = () => renderer.domElement.requestPointerLock();
document.addEventListener('pointerlockchange', () => { locked = document.pointerLockElement === renderer.domElement; start.style.display = locked ? 'none' : 'flex'; });
addEventListener('mousemove', e => { if (!locked) return; mouseDX += e.movementX; mouseDY += e.movementY; dirAccX = dirAccX * 0.8 + e.movementX; dirAccY = dirAccY * 0.8 + e.movementY;
  // направление клинка — по преобладающему движению мыши
  const ax = Math.abs(dirAccX), ay = Math.abs(dirAccY);
  if (Math.max(ax, ay) > 14) { bladeDir = ax > ay ? (dirAccX < 0 ? 'L' : 'R') : (dirAccY < 0 ? 'O' : 'T'); dirAccX = dirAccY = 0; }
});
addEventListener('mousedown', e => { if (!locked) return; if (e.button === 0) { lmb = true; lmbT = 0; } if (e.button === 2) { rmb = true; startBlock(player.f, bladeDir); } });
addEventListener('mouseup', e => { if (e.button === 0) { if (lmb && lmbT < 0.25) startAttack(player.f, 'light', bladeDir); lmb = false; } if (e.button === 2) { rmb = false; stopBlock(player.f); } });
addEventListener('contextmenu', e => e.preventDefault());
addEventListener('resize', () => { camera.aspect = innerWidth / innerHeight; camera.updateProjectionMatrix(); renderer.setSize(innerWidth, innerHeight); });

// ---------- HUD
const $ = (s: string) => document.querySelector<HTMLElement>(s)!;
const logEl = $('#log'); const logs: string[] = [];
function log(s: string) { logs.push(s); if (logs.length > 6) logs.shift(); logEl.innerHTML = logs.map((l, i) => `<div style="opacity:${0.4 + 0.6 * (i + 1) / logs.length}">${l}</div>`).join(''); }
function hud() {
  $('#hp i').style.width = `${player.f.hp}%`; $('#st i').style.width = `${player.f.st}%`;
  $('#ehp i').style.width = `${enemy.f.hp}%`; $('#est i').style.width = `${enemy.f.st}%`;
  for (const d of ['L', 'R', 'O', 'T']) $(`#dir .${d}`).classList.toggle('on', d === bladeDir);
}

// ---------- бой
const moveVec = new T.Vector3(), dodgeVec = new T.Vector3(); const back = () => new T.Vector3().subVectors(player.pos, enemy.pos).setY(0).normalize();
const NAMES: Record<Dir, string> = { L: 'слева', R: 'справа', O: 'сверху', T: 'уколом' };
function strike(att: Actor, def: Actor) {
  const dist = att.pos.distanceTo(def.pos); if (dist > att.f.weapon.length + 0.9) { att.f.hitDone = true; return; }
  const who = att === player ? 'Ты' : 'Враг', whom = att === player ? 'врага' : 'тебя';
  const o = resolve(att.f, def.f); att.f.hitDone = true; flash(def, o.type);
  switch (o.type) {
    case 'hit': damage(def.f, o.dmg); if (att.f.kind === 'heavy' && def.f.phase !== 'dead') stagger(def.f); log(`${who} ${att.f.kind === 'heavy' ? 'мощно ' : ''}бьёшь ${NAMES[att.f.dir]} — <b style="color:#e66">${o.dmg}</b> урона ${whom}`); shake = att.f.kind === 'heavy' ? 0.35 : 0.15; break;
    case 'blocked': def.f.st = Math.max(0, def.f.st - o.stDrain); if (o.breaks) { stagger(def.f); log(`${who}: удар ${NAMES[att.f.dir]} <b style="color:#fa4">пробил блок</b> — стамина кончилась`); } else log(`${who}: удар ${NAMES[att.f.dir]} <span style="color:#9cf">заблокирован</span>`); break;
    case 'parried': stagger(att.f); def.f.st = Math.min(def.f.maxSt, def.f.st - COST.parryOk); log(`<b style="color:#fd6">ПАРИРОВАНИЕ!</b> ${who} открыт`); shake = 0.25; break;
    case 'dodged': log(`${who}: удар ${NAMES[att.f.dir]} ушёл в пустоту — уворот`); break;
    case 'clash': {
      if (o.winner === 'att') { stagger(def.f); log(`<b style="color:#fd6">Клинки сошлись</b> — ${who.toLowerCase()} продавил, соперник сбит`); }
      else if (o.winner === 'def') { stagger(att.f); log(`<b style="color:#fd6">Клинки сошлись</b> — ${who.toLowerCase()} отброшен`); }
      else { att.f.phase = 'recover'; att.f.t = 0; def.f.phase = 'recover'; def.f.t = 0; att.f.st -= COST.clashLose * 0.5; def.f.st -= COST.clashLose * 0.5; log(`<b style="color:#fd6">Клинки сошлись</b> — оба отскочили`); }
      shake = 0.3; sparks(att, def); break;
    }
  }
}
let shake = 0;
function flash(a: Actor, kind: string) {
  const c = kind === 'hit' ? 0xff3020 : kind === 'parried' ? 0xffe070 : kind === 'clash' ? 0xffc040 : 0x88aaff;
  for (const m of a.rig.meshes) { const mm = (m.material as T.MeshStandardMaterial); if (!mm.userData.base) { mm.userData.base = mm.emissive.getHex(); } mm.emissive.setHex(c); mm.emissiveIntensity = 0.6; }
  setTimeout(() => { for (const m of a.rig.meshes) { const mm = m.material as T.MeshStandardMaterial; mm.emissive.setHex(mm.userData.base ?? 0); } }, 110);
}
const sparkGeo = new T.BufferGeometry(); const sparkPos = new Float32Array(60 * 3); sparkGeo.setAttribute('position', new T.BufferAttribute(sparkPos, 3));
const sparkPts = new T.Points(sparkGeo, new T.PointsMaterial({ color: 0xffd080, size: 0.08, transparent: true })); sparkPts.visible = false; scene.add(sparkPts);
const sparkVel: T.Vector3[] = Array.from({ length: 60 }, () => new T.Vector3()); let sparkT = 0;
function sparks(a: Actor, b: Actor) { const p = a.pos.clone().lerp(b.pos, 0.5).setY(1.3); for (let i = 0; i < 60; i++) { sparkPos.set([p.x, p.y, p.z], i * 3); sparkVel[i].set(Math.random() - .5, Math.random() * .8, Math.random() - .5).multiplyScalar(6); } sparkT = 0.5; sparkPts.visible = true; }

function restart() {
  for (const a of [player, enemy]) scene.remove(a.rig.root);
  player = spawn('you', 'arming', { cloth: M.cloth, armor: M.clothB }, 0, 3);
  enemy = spawn('foe', 'rusty', { cloth: M.leather, armor: M.dark }, 0, -3);
  brain = new Brain(0.55, 0.6); logs.length = 0; log('Новый бой. Направление клинка задаётся движением мыши перед ударом.');
}
log('Направь клинок мышью (индикатор в центре), ЛКМ — удар, ПКМ в момент вражеского удара — парирование.');

// ---------- цикл
const clock = new T.Clock(); const tmp = new T.Vector3();
function step() {
  const dt = Math.min(0.033, clock.getDelta());
  // камера
  camYaw -= mouseDX * 0.0022; camPitch = T.MathUtils.clamp(camPitch + mouseDY * 0.0018, -0.2, 1.1); mouseDX = mouseDY = 0;
  if (lmb) { lmbT += dt; if (lmbT >= 0.25 && player.f.phase !== 'windup') { startAttack(player.f, 'heavy', bladeDir); lmb = false; } }
  // движение игрока
  const fwd = new T.Vector3(-Math.sin(camYaw), 0, -Math.cos(camYaw)), right = new T.Vector3(fwd.z, 0, -fwd.x);
  moveVec.set(0, 0, 0); if (keys.has('KeyW')) moveVec.add(fwd); if (keys.has('KeyS')) moveVec.sub(fwd); if (keys.has('KeyD')) moveVec.add(right); if (keys.has('KeyA')) moveVec.sub(right);
  moveVec.normalize();
  const pf = player.f.phase; const speedMul = pf === 'idle' ? 3.2 : pf === 'block' || pf === 'parry' ? 1.6 : pf === 'dodge' ? 0 : pf === 'recover' ? 1.2 : 0.6;
  const want = moveVec.clone().multiplyScalar(speedMul); if (pf === 'dodge') want.copy(dodgeVec).multiplyScalar(7 * Math.max(0, 1 - player.f.t / 0.42));
  player.vel.lerp(want, 1 - Math.exp(-14 * dt)); player.pos.addScaledVector(player.vel, dt);
  // враг
  const toP = tmp.subVectors(player.pos, enemy.pos).setY(0); const dist = toP.length(); toP.normalize();
  const dec = brain.update(enemy.f, player.f, dist, dt);
  const ef = enemy.f.phase; const eSpeed = ef === 'idle' ? 2.4 : ef === 'block' ? 1.2 : ef === 'dodge' ? -6 * Math.max(0, 1 - enemy.f.t / 0.42) : 0;
  enemy.vel.lerp(toP.clone().multiplyScalar(ef === 'dodge' ? eSpeed : dec.move * eSpeed), 1 - Math.exp(-10 * dt)); enemy.pos.addScaledVector(enemy.vel, dt);
  // не проходим друг сквозь друга и через камни, не выходим за круг
  if (dist < 0.9) { const push = toP.clone().multiplyScalar((0.9 - dist) * 0.5); player.pos.add(push); enemy.pos.sub(push); }
  for (const a of [player, enemy]) { const r = Math.hypot(a.pos.x, a.pos.z); if (r > 7.2) a.pos.multiplyScalar(7.2 / r); for (const c of colliders) { const d = a.pos.distanceTo(c.position.clone().setY(0)); if (d < 1.0) a.pos.add(a.pos.clone().sub(c.position.clone().setY(0)).normalize().multiplyScalar(1.0 - d)); } }
  // поворот: всегда лицом к противнику (lock-on)
  player.yaw = Math.atan2(-toP.x, -toP.z); enemy.yaw = Math.atan2(toP.x, toP.z);
  player.rig.root.rotation.y = player.yaw; enemy.rig.root.rotation.y = enemy.yaw;
  // фазы и удары
  for (const [a, b, hold] of [[player, enemy, rmb], [enemy, player, dec.holdBlock]] as const) {
    tick(a.f, dt, hold);
    if (a.f.phase === 'active' && !a.f.hitDone) strike(a, b);
  }
  animate(player.rig, player.f, dt, player.vel.length(), moveVec, player.anim);
  animate(enemy.rig, enemy.f, dt, enemy.vel.length(), toP, enemy.anim);
  if (player.f.phase === 'dead' && player.f.t < dt * 2) log('<b>Ты пал.</b> R — заново.'); if (enemy.f.phase === 'dead' && enemy.f.t < dt * 2) log('<b style="color:#8f8">Победа.</b> R — заново.');
  // искры
  if (sparkT > 0) { sparkT -= dt; for (let i = 0; i < 60; i++) { sparkVel[i].y -= 15 * dt; sparkPos[i * 3] += sparkVel[i].x * dt; sparkPos[i * 3 + 1] += sparkVel[i].y * dt; sparkPos[i * 3 + 2] += sparkVel[i].z * dt; } sparkGeo.attributes.position.needsUpdate = true; (sparkPts.material as T.PointsMaterial).opacity = sparkT * 2; if (sparkT <= 0) sparkPts.visible = false; }
  // факелы
  scene.traverse(o => { if ((o as any).flicker) (o as T.PointLight).intensity = 5 + Math.sin(performance.now() * 0.02 + o.position.x) * 1.2 + Math.random(); });
  // камера за плечом
  const camTarget = player.pos.clone().add(new T.Vector3(0, 1.5, 0)).add(right.clone().multiplyScalar(0.6));
  const camPos = camTarget.clone().add(new T.Vector3(Math.sin(camYaw) * Math.cos(camPitch), Math.sin(camPitch), Math.cos(camYaw) * Math.cos(camPitch)).multiplyScalar(3.6));
  camera.position.lerp(camPos, 1 - Math.exp(-12 * dt));
  if (shake > 0) { shake -= dt; camera.position.add(new T.Vector3((Math.random() - .5), (Math.random() - .5), 0).multiplyScalar(shake * 0.25)); }
  camera.lookAt(camTarget.clone().lerp(enemy.pos.clone().setY(1.2), 0.25));
  hud(); renderer.render(scene, camera); requestAnimationFrame(step);
}
step();
