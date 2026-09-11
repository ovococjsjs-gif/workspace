import * as T from 'three';
import { M } from './materials';
import type { Weapon } from '../combat/types';

/** Процедурный меч: длина/ширина/качество влияют на геометрию и материал. */
export function makeSword(w: Weapon): T.Group {
  const g = new T.Group();
  const L = w.length, W = w.width;
  // клинок — призма с ребром (шестиугольное сечение)
  const shape = new T.Shape();
  shape.moveTo(-W / 2, 0); shape.lineTo(0, -W * 0.18); shape.lineTo(W / 2, 0);
  shape.lineTo(0, W * 0.18); shape.closePath();
  const blade = new T.ExtrudeGeometry(shape, { depth: L, bevelEnabled: false });
  blade.rotateX(-Math.PI / 2);
  // сужение к острию
  const pos = blade.attributes.position as T.BufferAttribute;
  for (let i = 0; i < pos.count; i++) {
    const y = pos.getY(i); const t = y / L; const k = 1 - Math.pow(t, 3) * 0.95;
    pos.setX(i, pos.getX(i) * k); pos.setZ(i, pos.getZ(i) * k);
  }
  blade.computeVertexNormals();
  const bladeMat = w.quality > 0.8 ? M.steel : w.quality > 0.5 ? M.steelDark : M.steelDark.clone();
  if (w.quality <= 0.5) (bladeMat as T.MeshStandardMaterial).color.set(0x5a5450);
  const b = new T.Mesh(blade, bladeMat); b.castShadow = true; g.add(b);
  // гарда
  const guard = new T.Mesh(new T.BoxGeometry(W * 4.2, 0.03, 0.05), w.quality > 0.8 ? M.gold : M.steelDark);
  guard.position.y = 0; g.add(guard);
  // рукоять и навершие
  const grip = new T.Mesh(new T.CylinderGeometry(0.018, 0.02, 0.22, 6), M.leather); grip.position.y = -0.12; g.add(grip);
  const pommel = new T.Mesh(new T.SphereGeometry(0.03, 6, 5), w.quality > 0.8 ? M.gold : M.steelDark); pommel.position.y = -0.25; g.add(pommel);
  g.userData.tip = new T.Vector3(0, L, 0);
  return g;
}
