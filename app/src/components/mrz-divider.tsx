import { StyleSheet, Text, View, type ViewStyle } from 'react-native';

import { fonts } from '@/lib/theme';

type Props = {
  /** Override the machine-readable-zone text; '<' fills the remainder. */
  line?: string;
  style?: ViewStyle;
};

const DEFAULT_LINE = 'P<194NETWORK<<FOR<THE<OTHER<ONE<NINETY<FOUR';

// Pad MRZ-style to a fixed width so the strip always reads as a full line.
function mrz(text: string): string {
  return text.toUpperCase().replace(/\s+/g, '<').padEnd(60, '<');
}

export function MrzDivider({ line = DEFAULT_LINE, style }: Props) {
  return (
    <View style={[styles.wrap, style]} accessible={false} importantForAccessibility="no-hide-descendants">
      <Text style={styles.text} numberOfLines={1} ellipsizeMode="clip">
        {mrz(line)}
      </Text>
    </View>
  );
}

const styles = StyleSheet.create({
  wrap: {
    overflow: 'hidden',
  },
  text: {
    fontFamily: fonts.mono,
    fontSize: 11,
    letterSpacing: 1.5,
    lineHeight: 18,
    color: 'rgba(237,232,220,0.35)',
  },
});
