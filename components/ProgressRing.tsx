import React from 'react';
import { View, StyleSheet } from 'react-native';
import { Colors } from '@/lib/theme';

export function ProgressRing({
  progress,
  size = 56,
  strokeWidth = 6,
  color = Colors.primary,
  trackColor = Colors.border,
  children,
}: {
  progress: number;
  size?: number;
  strokeWidth?: number;
  color?: string;
  trackColor?: string;
  children?: React.ReactNode;
}) {
  const radius = (size - strokeWidth) / 2;
  const circumference = 2 * Math.PI * radius;
  const clamped = Math.max(0, Math.min(1, progress));
  const strokeDashoffset = circumference * (1 - clamped);

  return (
    <View style={[styles.container, { width: size, height: size }]}>
      <View style={[styles.track, { width: size, height: size, borderRadius: size / 2, borderWidth: strokeWidth, borderColor: trackColor }]} />
      <View
        style={[
          styles.progress,
          {
            width: size,
            height: size,
            borderRadius: size / 2,
            borderWidth: strokeWidth,
            borderColor: color,
            borderTopColor: clamped > 0 ? color : 'transparent',
            borderRightColor: clamped > 0.25 ? color : 'transparent',
            borderBottomColor: clamped > 0.5 ? color : 'transparent',
            borderLeftColor: clamped > 0.75 ? color : 'transparent',
            transform: [{ rotate: '-90deg' }],
          },
        ]}
      />
      <View style={styles.children}>{children}</View>
    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    alignItems: 'center',
    justifyContent: 'center',
  },
  track: {
    position: 'absolute',
  },
  progress: {
    position: 'absolute',
    overflow: 'hidden',
  },
  children: {
    position: 'absolute',
    alignItems: 'center',
    justifyContent: 'center',
  },
});
