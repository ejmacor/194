import { LinearGradient } from 'expo-linear-gradient';
import { ActivityIndicator, Pressable, StyleSheet, Text, View } from 'react-native';

import { colors, foilGradient, fonts, radii } from '@/lib/theme';

type Props = {
  title: string;
  onPress?: () => void;
  disabled?: boolean;
  loading?: boolean;
  /** 'solid' = gold-foil CTA (default); 'ghost' = hairline outline, quiet actions */
  variant?: 'solid' | 'ghost';
};

export function FoilButton({ title, onPress, disabled, loading, variant = 'solid' }: Props) {
  const inactive = disabled || loading;
  const label = (
    <Text style={[styles.label, variant === 'ghost' && styles.labelGhost]}>{title}</Text>
  );

  return (
    <Pressable
      onPress={onPress}
      disabled={inactive}
      style={({ pressed }) => [pressed && !inactive && styles.pressed, inactive && styles.inactive]}
      accessibilityRole="button"
      accessibilityState={{ disabled: !!inactive, busy: !!loading }}
    >
      {variant === 'solid' ? (
        <LinearGradient
          colors={foilGradient}
          start={{ x: 0, y: 0 }}
          end={{ x: 0.6, y: 1 }}
          style={styles.base}
        >
          {loading ? <ActivityIndicator size="small" color={colors.ink} /> : label}
        </LinearGradient>
      ) : (
        <View style={[styles.base, styles.ghost]}>
          {loading ? <ActivityIndicator size="small" color={colors.foilBright} /> : label}
        </View>
      )}
    </Pressable>
  );
}

const styles = StyleSheet.create({
  base: {
    alignItems: 'center',
    justifyContent: 'center',
    paddingVertical: 17,
    paddingHorizontal: 32,
    borderRadius: radii.sharp,
    minHeight: 52,
  },
  ghost: {
    borderWidth: 1,
    borderColor: colors.line,
    backgroundColor: 'transparent',
  },
  label: {
    fontFamily: fonts.bodySemi,
    fontSize: 13,
    letterSpacing: 2.8,
    textTransform: 'uppercase',
    color: colors.ink,
  },
  labelGhost: {
    color: colors.muted,
  },
  pressed: {
    opacity: 0.85,
  },
  inactive: {
    opacity: 0.55,
  },
});
