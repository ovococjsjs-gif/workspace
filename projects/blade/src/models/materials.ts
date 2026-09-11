import * as T from 'three';
export const mat = (color: number, rough = 0.85, metal = 0) =>
  new T.MeshStandardMaterial({ color, roughness: rough, metalness: metal, flatShading: true });
export const M = {
  skin: mat(0xd9a982), cloth: mat(0x4a3b2a), clothB: mat(0x263140), leather: mat(0x2e2218),
  steel: mat(0xb9bec6, 0.35, 0.9), steelDark: mat(0x6d7178, 0.5, 0.8), gold: mat(0xc9a13b, 0.4, 0.9),
  wood: mat(0x5a3d22), stone: mat(0x6e6a63), grass: mat(0x4c6a3a), moss: mat(0x3d5a30), dark: mat(0x1b1d22),
};
