import {Euler, Quaternion} from 'three';

// Joint centres in the shared MakeHuman world space, not a horizontal T-pose.
// Each body and its garments share a fitted upper-body bind skeleton;
// foot joints stay compatible for the body-specific unisex shoe meshes.
const joints = [
  ['Root', -1, [0, 0, 0]], ['Hips', 0, [0, .92, .035]],
  ['Spine', 1, [0, 1.10, .025]], ['Chest', 2, [0, 1.33, .025]],
  ['Neck', 3, [0, 1.54, .025]], ['Head', 4, [0, 1.68, .025]],
  ['LeftUpperArm', 3, [.23, 1.43, .025]], ['LeftLowerArm', 6, [.40, 1.21, .025]], ['LeftHand', 7, [.56, 1.03, .035]],
  ['RightUpperArm', 3, [-.23, 1.43, .025]], ['RightLowerArm', 9, [-.40, 1.21, .025]], ['RightHand', 10, [-.56, 1.03, .035]],
  ['LeftUpperLeg', 1, [.15, .86, .035]], ['LeftLowerLeg', 12, [.19, .48, .015]], ['LeftFoot', 13, [.21, .10, .035]],
  ['RightUpperLeg', 1, [-.15, .86, .035]], ['RightLowerLeg', 15, [-.19, .48, .015]], ['RightFoot', 16, [-.21, .10, .035]],
];
export function rigFor(body) {
  const male = body === 'male';
  const fit = {
    Spine: [0, male ? 1.19 : 1.10, .025], Chest: [0, male ? 1.45 : 1.33, .025],
    Neck: [0, male ? 1.70 : 1.52, .025], Head: [0, male ? 1.82 : 1.66, .025],
    LeftUpperArm: [male ? .26 : .215, male ? 1.53 : 1.40, .025],
    LeftLowerArm: [male ? .45 : .39, male ? 1.31 : 1.18, .025],
    LeftHand: [male ? .60 : .51, male ? 1.14 : .99, .035],
  };
  for (const name of ['UpperArm', 'LowerArm', 'Hand']) {
    const position = fit['Left' + name]; fit['Right' + name] = [-position[0], position[1], position[2]];
  }
  const positions = joints.map(([name, , position]) => fit[name] ?? position);
  return {worldPositions: positions, bones: joints.map(([name, parent], index) => [name, parent,
    parent < 0 ? positions[index] : positions[index].map((value, axis) => value - positions[parent][axis])])};
}

const clamp = value => Math.max(0, Math.min(1, value));
function blend(a, b, amount) {
  const t = clamp(amount);
  return {joints: [a, b, 0, 0], weights: [1 - t, t, 0, 0]};
}
export function skinWeights([x, y], {hair = false, shoes = false, ankleBoot = false, skirt = false, headHeight = 1.51, body} = {}) {
  const side = x >= 0 ? 0 : 3;
  if (hair) return blend(5, 5, 0);
  if (shoes) return ankleBoot ? blend(14 + side, 13 + side, (y - .13) / .13) : blend(14 + side, 14 + side, 0);
  if (y > headHeight) return blend(5, 5, 0);
  if (body === 'male' && y > .90) y -= .13;
  // Hands and sleeves are below the shoulder, extending diagonally outwards.
  if (Math.abs(x) > .18 && y > 1.38 - Math.abs(x) * .85 && y <= headHeight) {
    const distance = Math.abs(x);
    if (distance < .32) return blend(3, 6 + side, (distance - .18) / .14);
    if (distance < .38) return blend(6 + side, 7 + side, (distance - .32) / .12);
    return blend(7 + side, 8 + side, (distance - .48) / .10);
  }
  if (y < .88) {
    if (skirt) {
      // A skirt hem follows each leg, smoothly bridged across the centre.
      // Hip-only weights leave the walking thighs outside the fabric.
      const amount = clamp((.88 - y) / .19), left = clamp(.5 + x / .22);
      const knee = clamp((.57 - y) / .16);
      return {joints: [1, 12, 15, x >= 0 ? 13 : 16],
        weights: [1 - amount, amount * (1 - knee) * left,
          amount * (1 - knee) * (1 - left), amount * knee]};
    }
    if (y < .20) return blend(14 + side, 13 + side, (y - .10) / .12);
    if (y < .55) return blend(13 + side, 12 + side, (y - .42) / .18);
    return blend(12 + side, 1, (y - .73) / .16);
  }
  if (y < 1.14) return blend(1, 2, (y - .94) / .17);
  if (y < 1.42) return blend(2, 3, (y - 1.17) / .18);
  return blend(4, 5, (y - 1.48) / .10);
}

// Rotations are relative to the source A-pose. These are distinct full-body
// fashion stances, with a small breathing cycle rather than a root-only turn.
export const poses = {
  idle: {LeftUpperArm: [0, 0, -.38], RightUpperArm: [0, 0, .38]},
  signature: {LeftUpperArm: [0, 0, -.42], RightUpperArm: [0, 0, .42], Head: [0, .10, -.04]},
  confident: {LeftUpperArm: [-.12, 0, -.35], LeftLowerArm: [-.14, 0, -1.10], LeftHand: [0, 0, .15],
    RightUpperArm: [0, 0, .40], Chest: [0, -.10, 0], Head: [0, .12, .05]},
  editorial: {RightUpperArm: [-.12, 0, .35], RightLowerArm: [-.14, 0, 1.10], RightHand: [0, 0, -.15],
    LeftUpperArm: [0, 0, -.44], Hips: [0, .12, 0], Chest: [0, -.16, -.035], Head: [0, -.16, -.09]},
  celebrate: {LeftUpperArm: [0, -.12, 1.32], RightUpperArm: [0, .12, -1.32],
    LeftLowerArm: [0, 0, .25], RightLowerArm: [0, 0, -.25], Head: [-.06, 0, 0]},
};
export function poseQuaternion(pose, bone, breathing = 0) {
  const angles = [...(poses[pose][bone] ?? [0, 0, 0])];
  if (bone === 'Chest') angles[0] += breathing * .012;
  if (bone === 'Head') angles[1] += breathing * .012;
  return new Quaternion().setFromEuler(new Euler(...angles)).toArray();
}
