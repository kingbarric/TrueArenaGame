// Hair uses the downloaded MakeHuman CC0 system pack. Lipstick is a fitted
// CC0-body overlay; the nose hoop is an original lightweight mesh.
const hair = (id, name, source, cost, colours = ['black']) => ({id: `female-hair-${id}`, name,
  category: 'hair', tags: ['casual', 'formal'], colours, cost,
  asset: ['female', `hair/${source}/${source}.obj`, `hair/${source}/${source}_diffuse.png`]});
const lipstick = (id, name, colour, colours) => ({id: `female-lipstick-${id}`, name,
  category: 'makeup', tags: ['romantic', 'party'], colours, cost: 0,
  asset: ['female', 'proxymeshes/female1605/female1605.obj', null, {lips: true, colour}]});
export const femaleBeauty = [
  hair('bob', 'Chic Bob', 'bob01', 0),
  hair('ponytail', 'Sleek Ponytail', 'ponytail01', 80, ['brown']),
  hair('long', 'Long & Flowing', 'long01', 120, ['brown']),
  lipstick('nude', 'Peach Nude', [.56, .25, .18, 1], ['nude']),
  lipstick('cocoa', 'Cocoa Gloss', [.22, .065, .035, 1], ['brown']),
  lipstick('coral', 'Coral Kiss', [.85, .10, .07, 1], ['coral']),
  lipstick('berry', 'Berry Wine', [.38, .02, .12, 1], ['burgundy']),
  lipstick('pink', 'Hot Pink', [.90, .035, .27, 1], ['pink']),
  {id: 'female-nose-ring-gold', name: 'Gold Nose Hoop', category: 'accessories',
    tags: ['casual', 'party'], colours: ['gold'], cost: 0,
    asset: ['female', 'proxymeshes/female1605/female1605.obj', null,
      {noseRing: true, colour: [.75, .45, .12, 1]}]},
];
