import { deserializeScene } from '../../.ci/freetikz/js/scene.js';
import { generateTikz } from '../../.ci/freetikz/js/tikz.js';

window.mathNotesGenerateTikz = source => {
  const scene = deserializeScene(source);
  return {
    scene: JSON.stringify(scene),
    source: generateTikz(scene).source,
  };
};
