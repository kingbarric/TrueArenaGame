import * as T from 'three';

export const seed = (id: string) => [...id].reduce((n, c) => Math.imul(n ^ c.charCodeAt(0), 16777619) >>> 0, 2166136261);
export type Seat = {x: number; z: number; yaw: number; seated: boolean};
// Eight couch places, then standing spots on the open side of the sitting room.
export function roomPlace(index: number): Seat {
  const seats: Seat[] = [
    ...[-.78, 0, .78].map(x => ({x, z: -1.9, yaw: 0, seated: true})),
    ...[-.7, .08, .86].map(z => ({x: -2.25, z, yaw: Math.PI / 2, seated: true})),
    ...[-.4, .4].map(z => ({x: 2.25, z, yaw: -Math.PI / 2, seated: true})),
  ];
  if (index < seats.length) return seats[index];
  return {x: [-2.35, -.8, .8, 2.35][(index - 8) % 4], z: 2.35, yaw: Math.PI, seated: false};
}
export function skeletonBones(root: T.Group) {
  const bones = new Map<string, T.Bone>();
  root.traverse(o => {if (o instanceof T.SkinnedMesh) for (const b of o.skeleton.bones) bones.set(b.name, b);});
  return bones;
}
export function seatPose(root: T.Group, body: string) {
  const bones = skeletonBones(root);
  for (const b of bones.values()) b.quaternion.identity();
  for (const side of ['Left', 'Right']) {
    bones.get(side + 'UpperLeg')!.rotation.x = -1.42;
    bones.get(side + 'LowerLeg')!.rotation.x = 1.42;
    bones.get(side + 'UpperArm')!.rotation.z = side === 'Left' ? -.55 : .55;
    bones.get(side + 'LowerArm')!.rotation.x = -.45;
  }
  root.position.y = body === 'male' ? -.38 : -.4;
  return bones;
}
// Smoothly blend the seated posture to standing, then add a modest walking gait.
export function animateBody(root: T.Group, bones: Map<string, T.Bone>, body: string, seated: number, walking: boolean, time: number) {
  root.position.y = (body === 'male' ? -.38 : -.4) * seated;
  const stride = walking ? Math.sin(time * 5) * .24 : 0;
  for (const [side, sign] of [['Left', 1], ['Right', -1]] as const) {
    bones.get(side + 'UpperLeg')!.rotation.x = -1.42 * seated + stride * sign;
    bones.get(side + 'LowerLeg')!.rotation.x = 1.42 * seated + (walking ? Math.max(0, -stride * sign) * 1.1 : 0);
    bones.get(side + 'UpperArm')!.rotation.set(-stride * sign * .6, 0, sign * -.55);
    bones.get(side + 'LowerArm')!.rotation.x = -.12 - .33 * seated;
  }
}
export function walkPosition(angle: number) {
  return new T.Vector3(Math.sin(angle) * 1.4, 0, .4 + Math.cos(angle) * 1.4);
}
