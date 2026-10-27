// The titles that light the site. All are Blender open movies under Creative
// Commons Attribution, credited on /credits/. Lights are baked from each
// poster by scripts/build_art.py.
import lights from './light.json';

export interface Title {
  id: string;
  name: string;
  year: number;
  genre: string;
  license: string;
  link: string;
  poster: boolean;
  backdrop: boolean;
}

export const titles = {
  singularity: { id: 'singularity', name: 'Singularity', year: 2026, genre: 'Adventure', license: 'CC BY', link: 'https://studio.blender.org/projects/singularity/', poster: true, backdrop: false },
  cosmos: { id: 'cosmos', name: 'Cosmos Laundromat', year: 2015, genre: 'Fantasy', license: 'CC BY 4.0', link: 'https://studio.blender.org/projects/cosmos-laundromat/', poster: true, backdrop: true },
  sprite: { id: 'sprite', name: 'Sprite Fright', year: 2021, genre: 'Comedy', license: 'CC BY 4.0', link: 'https://studio.blender.org/projects/sprite-fright/', poster: true, backdrop: false },
  charge: { id: 'charge', name: 'Charge', year: 2022, genre: 'Action', license: 'CC BY 4.0', link: 'https://studio.blender.org/projects/charge/', poster: true, backdrop: true },
  sintel: { id: 'sintel', name: 'Sintel', year: 2010, genre: 'Fantasy', license: 'CC BY 3.0', link: 'https://durian.blender.org/', poster: true, backdrop: true },
  spring: { id: 'spring', name: 'Spring', year: 2019, genre: 'Fantasy', license: 'CC BY 4.0', link: 'https://studio.blender.org/projects/spring/', poster: true, backdrop: true },
  tos: { id: 'tos', name: 'Tears of Steel', year: 2012, genre: 'Science Fiction', license: 'CC BY 3.0', link: 'https://mango.blender.org/', poster: true, backdrop: true },
  bbb: { id: 'bbb', name: 'Big Buck Bunny', year: 2008, genre: 'Comedy', license: 'CC BY 3.0', link: 'https://peach.blender.org/', poster: true, backdrop: false },
} satisfies Record<string, Title>;

export type TitleId = keyof typeof titles;
export type LightId = keyof typeof lights | 'lamp';

export const LAMP = '#8a8a99';
export const lightOf = (id: LightId) =>
  id === 'lamp' ? { light: LAMP, fill: '#b9b9c6' } : lights[id];

export const poster = (id: TitleId) => `/art/${id}-poster.webp`;
export const poster2x = (id: TitleId) => `/art/${id}-poster@2x.webp`;
export const backdrop = (id: TitleId, small = false) => `/art/${id}-backdrop${small ? '-s' : ''}.webp`;
/** A still that leads a screen by itself (scripts/build_art.py, STILLS). */
export type StillId = 'tosbridge' | 'singopen' | 'singfind' | 'singadd' | 'singget' | 'singready' | 'singslide';
export const still = (id: StillId, small = false) => `/art/${id}-backdrop${small ? '-s' : ''}.webp`;
export const room = (id: LightId) => (id === 'lamp' ? '' : `/art/${id}-room.webp`);

/** The attributes that make a section light the room with a title. */
export const lit = (id: LightId) => {
  const { light, fill } = lightOf(id);
  return { 'data-light': id, 'data-room': room(id) || undefined, 'data-l': light, 'data-f': fill };
};
