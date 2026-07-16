import { StyleSheet, Text, View, type ViewStyle } from 'react-native';

import { colors, fonts, radii } from '@/lib/theme';

type Tone = 'foil' | 'approve' | 'reject' | 'muted';

const toneColor: Record<Tone, string> = {
  foil: colors.foilBright,
  approve: colors.approve,
  reject: colors.reject,
  muted: colors.muted,
};

type Props = {
  /** Stamp word, e.g. "RECEIVED", "APPROVED", "ON THE WAITLIST" */
  label: string;
  tone?: Tone;
  /** Rotation in degrees; passport stamps land slightly crooked. */
  tilt?: number;
  style?: ViewStyle;
};

export function StampBadge({ label, tone = 'foil', tilt = -2, style }: Props) {
  const color = toneColor[tone];
  return (
    <View
      style={[styles.stamp, { borderColor: color, transform: [{ rotate: `${tilt}deg` }] }, style]}
    >
      <Text style={[styles.text, { color }]}>{label}</Text>
    </View>
  );
}

const styles = StyleSheet.create({
  stamp: {
    alignSelf: 'center',
    borderWidth: 1.5,
    borderRadius: radii.sharp + 1,
    paddingVertical: 10,
    paddingHorizontal: 22,
  },
  text: {
    fontFamily: fonts.mono,
    fontSize: 14,
    letterSpacing: 5,
    textTransform: 'uppercase',
  },
});
