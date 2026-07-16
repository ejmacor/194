// 194 design system (spec §5). Dark mode only — ink navy ground, gold foil
// accents, paper type. Fonts load in src/app/_layout.tsx via @expo-google-fonts.

export const colors = {
  ink: '#0B1120', // passport-cover navy — app background
  panel: '#0F172B', // raised surfaces / cards
  panelDeep: '#141D33', // avatar wells, inputs on panels
  foil: '#C8A55E', // gold foil — brand, accents
  foilBright: '#E3C888', // highlighted foil — emphasis, CTAs
  foilDark: '#8A6F3B', // gradient tail
  paper: '#EDE8DC', // visa-page off-white — primary text
  muted: '#7C8699', // secondary text
  line: 'rgba(200,165,94,0.22)', // hairline borders
  approve: '#4CAF7D',
  reject: '#C05B5B',
} as const;

// Font family names as registered by useFonts in the root layout.
export const fonts = {
  display: 'Cinzel_500Medium', // headers, the 194 mark — sparingly
  displaySemi: 'Cinzel_600SemiBold',
  body: 'Sora_300Light', // default body
  bodyRegular: 'Sora_400Regular',
  bodyMedium: 'Sora_500Medium',
  bodySemi: 'Sora_600SemiBold', // buttons, emphasis
  mono: 'ShareTechMono_400Regular', // labels, metadata, MRZ accents
} as const;

export const spacing = {
  xs: 4,
  sm: 8,
  md: 16,
  lg: 24,
  xl: 36,
  xxl: 56,
} as const;

export const radii = {
  sharp: 2, // buttons, stamps — crisp, official
  card: 4,
  panel: 6,
} as const;

// The foil CTA gradient (landing page: linear-gradient(160deg, bright, foil)).
export const foilGradient = [colors.foilBright, colors.foil] as const;
