import * as T from 'three';
import { M } from './models/materials';

/** Полуоткрытая площадка: руины круга камней на холме, туман, закат. */
export function buildArena(scene: T.Scene): T.Object3D[] {
  const colliders: T.Object3D[] = [];
  scene.background = new T.Color(0x1a1c26); scene.fog = new T.FogExp2(0x1a1c26, 0.035);
  const hemi = new T.HemisphereLight(0x8fa3c7, 0x2a2016, 0.9); scene.add(hemi);
  const sun = new T.DirectionalLight(0xffc98a, 2.2); sun.position.set(-18, 14, -10); sun.castShadow = true;
  sun.shadow.mapSize.set(2048, 2048); sun.shadow.camera.left = -25; sun.shadow.camera.right = 25; sun.shadow.camera.top = 25; sun.shadow.camera.bottom = -25; sun.shadow.bias = -0.0005;
  scene.add(sun);

  // земля с рельефом
  const geo = new T.PlaneGeometry(90, 90, 90, 90); geo.rotateX(-Math.PI / 2);
  const p = geo.attributes.position as T.BufferAttribute; const col: number[] = [];
  for (let i = 0; i < p.count; i++) {
    const x = p.getX(i), z = p.getZ(i); const r = Math.hypot(x, z);
    const h = r < 9 ? 0 : (r - 9) * 0.12 + Math.sin(x * 0.35) * Math.cos(z * 0.3) * 0.7;
    p.setY(i, h);
    const g = 0.28 + Math.random() * 0.06 + (r < 9 ? 0.1 : 0); col.push(g * 0.85, g, g * 0.55);
  }
  geo.setAttribute('color', new T.Float32BufferAttribute(col, 3)); geo.computeVertexNormals();
  const ground = new T.Mesh(geo, new T.MeshStandardMaterial({ vertexColors: true, roughness: 1, flatShading: true })); ground.receiveShadow = true; scene.add(ground);

  // каменный круг
  for (let i = 0; i < 10; i++) {
    const a = (i / 10) * Math.PI * 2; if (i === 2) continue; // проём
    const h = 2.2 + Math.random() * 1.4;
    const s = new T.Mesh(new T.BoxGeometry(0.9, h, 0.6), i % 3 ? M.stone : M.moss);
    s.position.set(Math.cos(a) * 8, h / 2 - 0.2, Math.sin(a) * 8); s.rotation.y = -a + Math.PI / 2; s.rotation.z = (Math.random() - 0.5) * 0.15;
    s.castShadow = true; s.receiveShadow = true; scene.add(s); colliders.push(s);
  }
  // упавшие колонны и обломки
  const rubble = new T.Mesh(new T.CylinderGeometry(0.4, 0.45, 4, 7), M.stone); rubble.rotation.z = Math.PI / 2; rubble.rotation.y = 0.6; rubble.position.set(3, 0.4, -4); rubble.castShadow = true; scene.add(rubble); colliders.push(rubble);
  // деревья вокруг
  const trunkG = new T.CylinderGeometry(0.18, 0.28, 3, 6), crownG = new T.ConeGeometry(1.6, 4, 7);
  for (let i = 0; i < 70; i++) {
    const a = Math.random() * Math.PI * 2, r = 14 + Math.random() * 26;
    const x = Math.cos(a) * r, z = Math.sin(a) * r; const y = (r - 9) * 0.12 + Math.sin(x * 0.35) * Math.cos(z * 0.3) * 0.7;
    const tr = new T.Mesh(trunkG, M.wood); tr.position.set(x, y + 1.5, z); tr.castShadow = true;
    const cr = new T.Mesh(crownG, i % 2 ? M.grass : M.moss); cr.position.set(x, y + 4.5, z); cr.castShadow = true;
    const sc = 0.8 + Math.random() * 0.7; tr.scale.setScalar(sc); cr.scale.setScalar(sc); scene.add(tr, cr);
  }
  // факелы у проёма
  for (const sx of [-1, 1]) {
    const a = (2 / 10) * Math.PI * 2 + sx * 0.18;
    const pole = new T.Mesh(new T.CylinderGeometry(0.05, 0.06, 1.8, 5), M.wood); pole.position.set(Math.cos(a) * 8.2, 0.9, Math.sin(a) * 8.2); scene.add(pole);
    const fl = new T.PointLight(0xff8a2a, 6, 10, 2); fl.position.copy(pole.position).add(new T.Vector3(0, 1.0, 0)); scene.add(fl);
    const glow = new T.Mesh(new T.SphereGeometry(0.1, 6, 5), new T.MeshBasicMaterial({ color: 0xffb060 })); glow.position.copy(fl.position); scene.add(glow);
    (fl as any).flicker = true;
  }
  return colliders;
}
