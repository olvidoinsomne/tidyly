import React from 'react';
import { View, Text, StyleSheet } from 'react-native';
import { ProgressRing } from './ProgressRing';
import { Colors, Spacing, FontSizes } from '@/lib/theme';

export function StatCard({
  label,
  value,
  sublabel,
  progress,
  color = Colors.primary,
  icon,
}: {
  label: string;
  value: string | number;
  sublabel?: string;
  progress?: number;
  color?: string;
  icon?: React.ReactNode;
}) {
  return (
    <View style={styles.card}>
      {progress !== undefined ? (
        <ProgressRing progress={progress} size={64} color={color}>
          <Text style={styles.ringValue}>{value}</Text>
        </ProgressRing>
      ) : (
        <View style={styles.iconWrap}>{icon}</View>
      )}
      <Text style={styles.label}>{label}</Text>
      {sublabel ? <Text style={styles.sublabel}>{sublabel}</Text> : null}
    </View>
  );
}

const styles = StyleSheet.create({
  card: {
    backgroundColor: Colors.surface,
    borderRadius: 16,
    padding: Spacing.lg,
    alignItems: 'center',
    gap: Spacing.sm,
    borderWidth: 1,
    borderColor: Colors.border,
  },
  iconWrap: {
    width: 56,
    height: 56,
    borderRadius: 28,
    backgroundColor: Colors.surfaceAlt,
    alignItems: 'center',
    justifyContent: 'center',
  },
  ringValue: {
    fontSize: FontSizes.lg,
    fontWeight: '700',
    color: Colors.text,
  },
  label: {
    fontSize: FontSizes.sm,
    fontWeight: '600',
    color: Colors.textSecondary,
    textAlign: 'center',
  },
  sublabel: {
    fontSize: FontSizes.xs,
    color: Colors.textTertiary,
    textAlign: 'center',
  },
});
