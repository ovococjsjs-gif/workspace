import * as T from 'three';
import { M } from './materials';

export interface Rig {
  root: T.Group; hips: T.Group; torso: T.Group; head: T.Group;
  rArm: T.Group; rFore: T.Group; lArm: T.Group; lFore: T.Group;
  rLeg: T.Group; rShin: T.Group; lLeg: T.Group; lShin: T.Group; hand: T.Group;
  meshes: T.Mesh[];
}

function box(w: number, h: number, d: number, m: T.Material, y = 0): T.Mesh {
  const mesh = new T.Mesh(new T.BoxGeometry(w, h, d), m); mesh.position.y = y;
  mesh.castShadow = true; mesh.receiveShadow = true; return mesh;
}

/** Низкополигональный гуманоид с иерархией суставов. Рост ~1.8м. */
export function makeHumanoid(palette: { cloth: T.Material; armor: T.Material }): Rig {
  const meshes: T.Mesh[] = [];
  const add = (p: T.Object3D, m: T.Mesh) => { p.add(m); meshes.push(m); return m; };
  const root = new T.Group();
  const hips = new T.Group(); hips.position.y = 0.95; root.add(hips);
  add(hips, box(0.34, 0.18, 0.22, palette.cloth, 0.05));
  const torso = new T.Group(); torso.position.y = 0.14; hips.add(torso);
  add(torso, box(0.40, 0.50, 0.24, palette.armor, 0.25));
  add(torso, box(0.46, 0.10, 0.28, palette.armor, 0.50)); // плечи
  const head = new T.Group(); head.position.y = 0.58; torso.add(head);
  add(head, box(0.22, 0.24, 0.24, M.skin, 0.14));
  add(head, box(0.24, 0.10, 0.26, M.steelDark, 0.24)); // шлем-обод

  const limb = (parent: T.Object3D, x: number, y: number, upper: [number, T.Material], lower: [number, T.Material], girth: number) => {
    const a = new T.Group(); a.position.set(x, y, 0); parent.add(a);
    add(a, box(girth, upper[0], girth, upper[1], -upper[0] / 2));
    const f = new T.Group(); f.position.y = -upper[0]; a.add(f);
    add(f, box(girth * 0.9, lower[0], girth * 0.9, lower[1], -lower[0] / 2));
    return [a, f] as const;
  };
  const [rArm, rFore] = limb(torso, -0.27, 0.48, [0.30, palette.armor], [0.28, M.skin], 0.11);
  const [lArm, lFore] = limb(torso, 0.27, 0.48, [0.30, palette.armor], [0.28, M.skin], 0.11);
  const [rLeg, rShin] = limb(hips, -0.11, 0, [0.42, palette.cloth], [0.42, M.leather], 0.14);
  const [lLeg, lShin] = limb(hips, 0.11, 0, [0.42, palette.cloth], [0.42, M.leather], 0.14);
  // ступни
  add(rShin, box(0.14, 0.08, 0.24, M.leather, -0.40)).position.z = 0.04;
  add(lShin, box(0.14, 0.08, 0.24, M.leather, -0.40)).position.z = 0.04;
  const hand = new T.Group(); hand.position.y = -0.30; rFore.add(hand);
  add(hand, box(0.09, 0.09, 0.09, M.skin));
  return { root, hips, torso, head, rArm, rFore, lArm, lFore, rLeg, rShin, lLeg, lShin, hand, meshes };
}
