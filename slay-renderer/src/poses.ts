import {AnimationMixer, type AnimationClip, Object3D} from 'three';

export function applyPose(mixer: AnimationMixer, clips: AnimationClip[], id: string) {
  const clip = clips.find(candidate => candidate.name === id);
  if (!clip) throw Error('Pose is unavailable: ' + id);
  mixer.stopAllAction();
  mixer.clipAction(clip).reset().play();
  // Apply the stance immediately, including when the next operation exports
  // a screenshot before another animation frame has run.
  mixer.update(0);
}

export function selectBodyFit(garment: Object3D, body: string) {
  garment.traverse(object => {
    if (object.userData.slayBody) object.visible = object.userData.slayBody === body;
  });
}
