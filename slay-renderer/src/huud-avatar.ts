import * as T from 'three';

export const seed = (id: string) => [...id].reduce((n, c) => Math.imul(n ^ c.charCodeAt(0), 16777619) >>> 0, 2166136261);
export type Seat = {x: number; z: number; yaw: number; seated: boolean};
export const CUSHION_TOP = .37;
export const WALK_RATE = .95;
export const DOOR = new T.Vector3(0, 0, 3.4);
export const TRANSIT_SPEED = 2.6;
// Sit toward the front of the cushions so shins clear the sofa base.
export function roomPlace(index: number): Seat {
  const seats: Seat[] = [
    ...[-.78, 0, .78].map(x => ({x, z: -1.62, yaw: 0, seated: true})),
    ...[-.7, .08, .86].map(z => ({x: -1.97, z, yaw: Math.PI / 2, seated: true})),
    ...[-.4, .4].map(z => ({x: 1.97, z, yaw: -Math.PI / 2, seated: true})),
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
  animateBody(root, bones, body, 1, false, 0);
  return bones;
}
// Both rigs use the same hip and shin lengths; shoes stay on the floor.
export function animateBody(root: T.Group, bones: Map<string, T.Bone>, _body: string, seated: number, walking: boolean, time: number) {
  root.position.y = -.4 * seated;
  const stride = walking ? Math.sin(time * 9) * .36 : 0;
  for (const [side, sign] of [['Left', 1], ['Right', -1]] as const) {
    bones.get(side + 'UpperLeg')!.rotation.x = -1.42 * seated + stride * sign;
    bones.get(side + 'LowerLeg')!.rotation.x = 1.42 * seated + (walking ? Math.max(0, -stride * sign) * 1.1 : 0);
    bones.get(side + 'UpperArm')!.rotation.set(-stride * sign * .6, 0, sign * -.38);
    bones.get(side + 'LowerArm')!.rotation.x = -.12 - .33 * seated;
  }
}
export function walkPosition(angle: number) {
  return new T.Vector3(Math.sin(angle) * 1.4, 0, .4 + Math.cos(angle) * 1.4);
}
// Door -> front aisle -> arc around the table -> cushion/standing place.
// Reverse this route to leave; the table is never crossed.
export function doorRoute(place: Seat): T.Vector3[] {
  const end = new T.Vector3(place.x, 0, place.z);
  if (!place.seated) return [DOOR.clone(), new T.Vector3(0,0,2.7), new T.Vector3(place.x,0,2.7), end];
  const angle = Math.atan2(place.x, place.z - .4);
  const steps = Math.max(1, Math.ceil(Math.abs(angle) / .22));
  return [DOOR.clone(), new T.Vector3(0,0,2.05), ...Array.from({length:steps+1},(_,i)=>walkPosition(angle*i/steps)), end];
}
export function exitRoute(position: T.Vector3, place: Seat): T.Vector3[] {
  const route=doorRoute(place).reverse();
  // A walking avatar can leave from its current point on the same clear aisle.
  if(position.distanceTo(route[0])>.55){
    const angle=Math.atan2(position.x,position.z-.4),steps=Math.max(1,Math.ceil(Math.abs(angle)/.22));
    return [...Array.from({length:steps+1},(_,i)=>walkPosition(angle*(1-i/steps))),new T.Vector3(0,0,2.05),DOOR.clone()];
  }
  return route;
}
