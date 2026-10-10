import {AnimationClip, AnimationMixer, Bone, Euler, Group, LoopOnce, Object3D, Quaternion, QuaternionKeyframeTrack, Vector3, VectorKeyframeTrack} from 'three';
import {applyPose} from './poses.ts';

export const SHOWCASE_SECONDS = 5;
const WALK_SECONDS = 1.8;
// Preserve the authored stride/foot planting while playing the gait faster.
const GAIT_SECONDS = 3.2;
const TURN_START = 2.3, TURN_SECONDS = 2.1;
const smooth = (t: number) => {const x = Math.max(0, Math.min(1, t)); return x * x * (3 - 2 * x);};
const rotation = (x = 0, y = 0, z = 0) => new Quaternion().setFromEuler(new Euler(x, y, z));

// A small authored runway gait for the shared starter rig. Two-bone leg IK
// keeps the planted ankle still while the body advances; shoe joints retain
// a level sole. All channels are keyed so an earlier pose cannot leak in.
export function catwalkClip(body: Object3D): AnimationClip {
  body.updateMatrixWorld(true);
  const bones = new Map<string, Bone>();
  body.traverse(o => {if (o instanceof Bone) bones.set(o.name, o);});
  const hips = bones.get('Hips');
  if (!hips) throw Error('This avatar needs a runway animation rig');
  const legs = ['Left', 'Right'].map(side => {
    const upper = bones.get(side + 'UpperLeg'), lower = bones.get(side + 'LowerLeg'), foot = bones.get(side + 'Foot');
    if (!upper || !lower || !foot) throw Error('This avatar needs rigged legs for the catwalk');
    const hip = upper.getWorldPosition(new Vector3()), knee = lower.getWorldPosition(new Vector3()), ankle = foot.getWorldPosition(new Vector3());
    return {side, hip, ankle, thigh: knee.clone().sub(hip), shin: ankle.clone().sub(knee)};
  });
  const times: number[] = [], values = new Map([...bones.keys()].map(name => [name, [] as number[]]));
  const hipValues: number[] = [];
  for (let frame = 0; frame <= 96; frame++) {
    const time = GAIT_SECONDS * frame / 96, phase = time / 1.6, wave = Math.sin(phase * Math.PI * 2);
    times.push(time);
    const delta = new Vector3(.008 * wave, -.018 + .005 * (1 - Math.cos(phase * Math.PI * 4)), 0);
    hipValues.push(...hips.position.clone().add(delta).toArray());
    const poses = new Map<string, Quaternion>();
    poses.set('LeftUpperArm', rotation(.16 * wave, 0, -.40));
    poses.set('RightUpperArm', rotation(-.16 * wave, 0, .40));
    poses.set('LeftLowerArm', rotation(-.08, 0, -.04));
    poses.set('RightLowerArm', rotation(-.08, 0, .04));
    poses.set('Chest', rotation(.012, .025 * wave, .018 * wave));
    poses.set('Head', rotation(0, -.02 * wave));
    for (const [index, leg] of legs.entries()) {
      const p = (phase + index * .5) % 1, swing = Math.max(0, (p - .6) / .4);
      const stride = .65 / GAIT_SECONDS * 1.6 * .6 / 2;
      const ankle = leg.ankle.clone();
      ankle.z += p < .6 ? stride * (1 - 2 * p / .6) : stride * (-1 + 2 * smooth(swing));
      ankle.y += .055 * Math.sin(Math.PI * swing);
      const hip = leg.hip.clone().add(delta), direction = ankle.clone().sub(hip);
      const a = leg.thigh.length(), b = leg.shin.length(), d = Math.min(direction.length(), a + b - .0001);
      direction.normalize();
      const along = (a * a - b * b + d * d) / (2 * d);
      const bend = new Vector3(0, 0, 1).addScaledVector(direction, -direction.z).normalize();
      const knee = hip.clone().addScaledVector(direction, along).addScaledVector(bend, Math.sqrt(Math.max(0, a * a - along * along)));
      const upper = new Quaternion().setFromUnitVectors(leg.thigh.clone().normalize(), knee.clone().sub(hip).normalize());
      const lowerWorld = new Quaternion().setFromUnitVectors(leg.shin.clone().normalize(), ankle.clone().sub(knee).normalize());
      poses.set(leg.side + 'UpperLeg', upper);
      poses.set(leg.side + 'LowerLeg', upper.clone().invert().multiply(lowerWorld));
      poses.set(leg.side + 'Foot', lowerWorld.clone().invert());
    }
    for (const name of bones.keys()) values.get(name)!.push(...(poses.get(name) ?? new Quaternion()).toArray());
  }
  return new AnimationClip('slay_catwalk', GAIT_SECONDS, [
    ...[...values].map(([name, quaternions]) => new QuaternionKeyframeTrack(name + '.quaternion', times, quaternions)),
    new VectorKeyframeTrack('Hips.position', times, hipValues),
  ]);
}

export class Showcase {
  private elapsed = 0;
  private finishPose = 'confident';
  private phase = '';
  private completion?: {resolve: (pose: string) => void; reject: (reason: Error) => void};
  private walking = false;
  private clip?: AnimationClip;
  private root: Group;
  private body: Object3D;
  private mixer: AnimationMixer;
  private clips: AnimationClip[];
  private onState: (playing: boolean, phase: string) => void;
  constructor(root: Group, body: Object3D, mixer: AnimationMixer,
    clips: AnimationClip[], onState: (playing: boolean, phase: string) => void = () => {}) {
    this.root = root; this.body = body; this.mixer = mixer;
    this.clips = clips; this.onState = onState;
  }
  get playing() {return !!this.completion;}
  play(pose = 'confident'): Promise<string> {
    if (this.playing) throw Error('A show off is already playing');
    if (!this.clips.some(clip => clip.name === pose)) throw Error('The finishing pose is unavailable');
    this.mixer.stopAllAction(); this.root.position.set(0, 0, 0); this.root.rotation.set(0, 0, 0);
    this.body.updateMatrixWorld(true);
    this.clip ??= catwalkClip(this.body);
    const action = this.mixer.clipAction(this.clip).reset().setLoop(LoopOnce, 1).setEffectiveTimeScale(GAIT_SECONDS / WALK_SECONDS);
    action.clampWhenFinished = true; action.play(); this.mixer.update(0);
    this.elapsed = 0; this.walking = true; this.finishPose = pose; this.root.position.z = -.65;
    const promise = new Promise<string>((resolve, reject) => {this.completion = {resolve, reject};});
    this.notify('Walking to the stage');
    return promise;
  }
  private notify(phase: string) {if (phase !== this.phase) {this.phase = phase; this.onState(this.playing, phase);}}
  update(seconds: number) {
    if (!this.playing) return;
    const old = this.elapsed;
    this.elapsed = Math.min(SHOWCASE_SECONDS, old + Math.max(0, seconds));
    if (this.walking) {
      this.mixer.update(Math.min(this.elapsed - old, Math.max(0, WALK_SECONDS - old)));
      this.root.position.z = -.65 * (1 - Math.min(1, this.elapsed / WALK_SECONDS));
      if (this.elapsed >= WALK_SECONDS) {
        const walk = this.mixer.clipAction(this.clip!);
        const pose = this.mixer.clipAction(this.clips.find(c => c.name === this.finishPose)!).reset().play();
        pose.crossFadeFrom(walk, .25, false); this.walking = false;
        this.mixer.update(Math.max(0, this.elapsed - WALK_SECONDS));
      }
    } else this.mixer.update(this.elapsed - old);
    this.root.rotation.y = Math.PI * 2 * smooth((this.elapsed - TURN_START) / TURN_SECONDS);
    this.notify(this.elapsed < WALK_SECONDS ? 'Walking to the stage' : this.elapsed < TURN_START ? 'Strike a pose' : this.elapsed < TURN_START + TURN_SECONDS ? 'Show every angle' : 'Own the spotlight');
    this.root.updateMatrixWorld(true);
    if (this.elapsed >= SHOWCASE_SECONDS) {
      const done = this.completion!; this.completion = undefined;
      this.reset(this.finishPose); this.onState(false, 'Finished'); this.phase = '';
      done.resolve(this.finishPose);
    }
  }
  private reset(pose: string) {
    this.mixer.stopAllAction(); this.root.position.set(0, 0, 0); this.root.rotation.set(0, 0, 0);
    applyPose(this.mixer, this.clips, pose); this.root.updateMatrixWorld(true);
  }
  stop(reason = 'Show off cancelled') {
    if (!this.completion) return;
    const done = this.completion; this.completion = undefined;
    this.reset(this.finishPose); this.phase = ''; this.onState(false, 'Stopped'); done.reject(new Error(reason));
  }
}
