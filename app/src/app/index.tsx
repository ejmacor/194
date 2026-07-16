// Milestone 2 scaffold check — exercises the theme, fonts, and brand
// components so the setup is verifiable in Expo Go. Replaced by the gate
// (email → OTP → claim_gate_status) in Milestone 3.

import { ScrollView, StyleSheet, Text, View } from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';

import { FoilButton } from '@/components/foil-button';
import { MrzDivider } from '@/components/mrz-divider';
import { StampBadge } from '@/components/stamp-badge';
import { colors, fonts, spacing } from '@/lib/theme';

export default function ScaffoldCheck() {
  return (
    <SafeAreaView style={styles.safe} edges={['top', 'bottom']}>
      <ScrollView contentContainerStyle={styles.scroll}>
        <Text style={styles.eyebrow}>Members only · Verified at the border</Text>
        <Text style={styles.mark}>194</Text>
        <Text style={styles.tagline}>
          195 countries. <Text style={styles.taglineStrong}>Yours made it.</Text>
        </Text>

        <MrzDivider style={styles.block} />

        <View style={styles.stampRow}>
          <StampBadge label="Received" tone="foil" tilt={-2} />
          <StampBadge label="Approved" tone="approve" tilt={2} />
          <StampBadge label="Waitlist" tone="muted" tilt={-1} />
        </View>

        <View style={styles.buttons}>
          <FoilButton title="Present passport" onPress={() => {}} />
          <FoilButton title="Sign out" variant="ghost" onPress={() => {}} />
          <FoilButton title="Processing" loading />
        </View>

        <MrzDivider line="1940000000USA<EXCLUDED<<<<<2026<<MEMBERS<ONLY" style={styles.block} />

        <Text style={styles.footer}>Scaffold check · Milestone 2 · Expo SDK 57</Text>
      </ScrollView>
    </SafeAreaView>
  );
}

const styles = StyleSheet.create({
  safe: {
    flex: 1,
    backgroundColor: colors.ink,
  },
  scroll: {
    flexGrow: 1,
    justifyContent: 'center',
    paddingHorizontal: spacing.lg,
    paddingVertical: spacing.xl,
  },
  eyebrow: {
    fontFamily: fonts.mono,
    fontSize: 12,
    letterSpacing: 4,
    textTransform: 'uppercase',
    color: colors.foil,
    textAlign: 'center',
  },
  mark: {
    fontFamily: fonts.display,
    fontSize: 124,
    lineHeight: 132,
    letterSpacing: 6,
    color: colors.foilBright,
    textAlign: 'center',
    marginTop: spacing.md,
  },
  tagline: {
    fontFamily: fonts.body,
    fontSize: 19,
    color: colors.paper,
    textAlign: 'center',
    marginTop: spacing.sm,
  },
  taglineStrong: {
    fontFamily: fonts.bodyMedium,
    color: colors.foilBright,
  },
  block: {
    marginVertical: spacing.xl,
  },
  stampRow: {
    flexDirection: 'row',
    justifyContent: 'center',
    gap: spacing.md,
    flexWrap: 'wrap',
  },
  buttons: {
    gap: spacing.md,
    marginTop: spacing.xl,
  },
  footer: {
    fontFamily: fonts.mono,
    fontSize: 10,
    letterSpacing: 2,
    textTransform: 'uppercase',
    color: colors.muted,
    textAlign: 'center',
    marginTop: spacing.xxl,
  },
});
