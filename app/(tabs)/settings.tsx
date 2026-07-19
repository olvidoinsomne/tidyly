import React, { useState, useCallback } from 'react';
import {
  View,
  Text,
  ScrollView,
  StyleSheet,
  RefreshControl,
  TouchableOpacity,
  Switch,
  TextInput,
  Alert,
  Share,
} from 'react-native';
import { useFocusEffect } from '@react-navigation/native';
import {
  Crown,
  Bell,
  Moon,
  Calendar,
  Home,
  Sparkles,
  Users,
  Download,
  Trash2,
  Info,
  ChevronRight,
  Star,
  Check,
  Zap,
} from 'lucide-react-native';
import { SafeAreaView } from 'react-native-safe-area-context';
import { Colors, Spacing, BorderRadius, FontSizes, Shadows } from '@/lib/theme';
import {
  fetchSettings,
  updateSettings,
  fetchRooms,
  fetchAllTasks,
  fetchCompletionsInRange,
  todayISO,
  addDays,
} from '@/lib/database';
import type { Settings as SettingsType } from '@/lib/types';

export default function SettingsScreen() {
  const [settings, setSettings] = useState<SettingsType | null>(null);
  const [loading, setLoading] = useState(true);
  const [refreshing, setRefreshing] = useState(false);
  const [editingName, setEditingName] = useState(false);
  const [householdName, setHouseholdName] = useState('');

  const loadData = useCallback(async () => {
    try {
      const s = await fetchSettings();
      setSettings(s);
      setHouseholdName(s.household_name);
    } catch (e) {
      console.error('Failed to load settings', e);
    } finally {
      setLoading(false);
      setRefreshing(false);
    }
  }, []);

  useFocusEffect(
    useCallback(() => {
      loadData();
    }, [loadData])
  );

  const onRefresh = () => {
    setRefreshing(true);
    loadData();
  };

  const toggleSetting = async (key: 'dark_mode' | 'notifications_enabled' | 'week_starts_monday', value: boolean) => {
    if (!settings) return;
    setSettings({ ...settings, [key]: value });
    try {
      await updateSettings({ [key]: value });
    } catch {
      setSettings({ ...settings, [key]: !value });
      Alert.alert('Error', 'Could not update setting.');
    }
  };

  const saveHouseholdName = async () => {
    if (!householdName.trim()) return;
    try {
      await updateSettings({ household_name: householdName.trim() });
      setSettings((prev) => (prev ? { ...prev, household_name: householdName.trim() } : prev));
      setEditingName(false);
    } catch {
      Alert.alert('Error', 'Could not save name.');
    }
  };

  const handleExport = async () => {
    try {
      const [rooms, tasks, completions] = await Promise.all([
        fetchRooms(),
        fetchAllTasks(),
        fetchCompletionsInRange(addDays(todayISO(), -365), todayISO()),
      ]);
      const data = { rooms, tasks, completions, exportDate: new Date().toISOString() };
      const jsonStr = JSON.stringify(data, null, 2);
      await Share.share({ message: jsonStr, title: 'Sweepy Data Export' });
    } catch {
      Alert.alert('Error', 'Could not export data.');
    }
  };

  const handleClearData = () => {
    Alert.alert(
      'Clear All Data',
      'This will permanently delete all rooms, tasks, and completion history. This cannot be undone.',
      [
        { text: 'Cancel', style: 'cancel' },
        {
          text: 'Delete Everything',
          style: 'destructive',
          onPress: () => {
            Alert.alert(
              'Are you absolutely sure?',
              'Type "DELETE" to confirm. This is your last warning.',
              [
                { text: 'Cancel', style: 'cancel' },
                {
                  text: 'Confirm Delete',
                  style: 'destructive',
                  onPress: async () => {
                    Alert.alert('Info', 'Data deletion requires manual database access. Contact support.');
                  },
                },
              ]
            );
          },
        },
      ]
    );
  };

  if (!settings && !loading) {
    return (
      <SafeAreaView style={styles.container} edges={['top']}>
        <View style={styles.errorState}>
          <Text style={styles.errorText}>Could not load settings.</Text>
        </View>
      </SafeAreaView>
    );
  }

  return (
    <SafeAreaView style={styles.container} edges={['top']}>
      <View style={styles.header}>
        <Text style={styles.headerTitle}>Settings</Text>
      </View>

      <ScrollView
        style={styles.scrollView}
        contentContainerStyle={styles.scrollContent}
        showsVerticalScrollIndicator={false}
        refreshControl={<RefreshControl refreshing={refreshing} onRefresh={onRefresh} />}
      >
        {/* Premium Banner */}
        <View style={styles.premiumBanner}>
          <View style={styles.premiumIconWrap}>
            <Crown size={28} color={Colors.textInverse} strokeWidth={2.5} />
          </View>
          <View style={styles.premiumInfo}>
            <Text style={styles.premiumTitle}>Premium Active</Text>
            <Text style={styles.premiumSubtitle}>All features unlocked</Text>
          </View>
          <View style={styles.premiumBadge}>
            <Check size={14} color={Colors.success} strokeWidth={3} />
            <Text style={styles.premiumBadgeText}>PRO</Text>
          </View>
        </View>

        {/* Household Name */}
        <View style={styles.section}>
          <Text style={styles.sectionTitle}>Household</Text>
          <View style={styles.card}>
            <View style={styles.settingRow}>
              <View style={styles.settingLeft}>
                <View style={[styles.settingIcon, { backgroundColor: 'rgba(59, 130, 246, 0.12)' }]}>
                  <Home size={20} color={Colors.primary} strokeWidth={2} />
                </View>
                <View style={styles.settingInfo}>
                  <Text style={styles.settingLabel}>Household Name</Text>
                  {editingName ? (
                    <View style={styles.nameEditRow}>
                      <TextInput
                        style={styles.nameInput}
                        value={householdName}
                        onChangeText={setHouseholdName}
                        autoFocus
                        placeholder="My Home"
                        placeholderTextColor={Colors.textTertiary}
                      />
                      <TouchableOpacity onPress={saveHouseholdName} style={styles.saveNameBtn}>
                        <Check size={16} color={Colors.textInverse} strokeWidth={3} />
                      </TouchableOpacity>
                    </View>
                  ) : (
                    <Text style={styles.settingValue}>{settings?.household_name ?? 'My Home'}</Text>
                  )}
                </View>
              </View>
              {!editingName && (
                <TouchableOpacity onPress={() => setEditingName(true)} style={styles.editBtn}>
                  <Text style={styles.editBtnText}>Edit</Text>
                </TouchableOpacity>
              )}
            </View>
          </View>
        </View>

        {/* Preferences */}
        <View style={styles.section}>
          <Text style={styles.sectionTitle}>Preferences</Text>
          <View style={styles.card}>
            <View style={styles.settingRow}>
              <View style={styles.settingLeft}>
                <View style={[styles.settingIcon, { backgroundColor: 'rgba(245, 158, 11, 0.12)' }]}>
                  <Bell size={20} color={Colors.warning} strokeWidth={2} />
                </View>
                <Text style={styles.settingLabel}>Notifications</Text>
              </View>
              <Switch
                value={settings?.notifications_enabled ?? true}
                onValueChange={(v) => toggleSetting('notifications_enabled', v)}
                trackColor={{ false: Colors.border, true: Colors.primary }}
                thumbColor={Colors.surface}
              />
            </View>
            <View style={styles.divider} />
            <View style={styles.settingRow}>
              <View style={styles.settingLeft}>
                <View style={[styles.settingIcon, { backgroundColor: 'rgba(99, 102, 241, 0.12)' }]}>
                  <Moon size={20} color={Colors.primary} strokeWidth={2} />
                </View>
                <Text style={styles.settingLabel}>Dark Mode</Text>
              </View>
              <Switch
                value={settings?.dark_mode ?? false}
                onValueChange={(v) => toggleSetting('dark_mode', v)}
                trackColor={{ false: Colors.border, true: Colors.primary }}
                thumbColor={Colors.surface}
              />
            </View>
            <View style={styles.divider} />
            <View style={styles.settingRow}>
              <View style={styles.settingLeft}>
                <View style={[styles.settingIcon, { backgroundColor: 'rgba(6, 182, 212, 0.12)' }]}>
                  <Calendar size={20} color={Colors.secondary} strokeWidth={2} />
                </View>
                <Text style={styles.settingLabel}>Week Starts Monday</Text>
              </View>
              <Switch
                value={settings?.week_starts_monday ?? true}
                onValueChange={(v) => toggleSetting('week_starts_monday', v)}
                trackColor={{ false: Colors.border, true: Colors.primary }}
                thumbColor={Colors.surface}
              />
            </View>
          </View>
        </View>

        {/* Premium Features */}
        <View style={styles.section}>
          <Text style={styles.sectionTitle}>Premium Features</Text>
          <View style={styles.card}>
            {[
              { icon: Sparkles, color: Colors.accent, bg: 'rgba(245, 158, 11, 0.12)', label: 'Smart Task Suggestions', desc: 'AI-powered cleaning recommendations' },
              { icon: Users, color: Colors.primary, bg: 'rgba(59, 130, 246, 0.12)', label: 'Unlimited Members', desc: 'Share with your whole household' },
              { icon: Zap, color: Colors.warning, bg: 'rgba(245, 158, 11, 0.12)', label: 'Custom Frequencies', desc: 'Set any repeat schedule' },
              { icon: Star, color: Colors.success, bg: 'rgba(16, 185, 129, 0.12)', label: 'Advanced Analytics', desc: 'Detailed insights & trends' },
              { icon: Download, color: Colors.secondary, bg: 'rgba(6, 182, 212, 0.12)', label: 'Data Export', desc: 'Export your data anytime' },
            ].map((feature, idx) => (
              <View key={idx}>
                {idx > 0 && <View style={styles.divider} />}
                <View style={styles.settingRow}>
                  <View style={styles.settingLeft}>
                    <View style={[styles.settingIcon, { backgroundColor: feature.bg }]}>
                      <feature.icon size={20} color={feature.color} strokeWidth={2} />
                    </View>
                    <View style={styles.settingInfo}>
                      <Text style={styles.settingLabel}>{feature.label}</Text>
                      <Text style={styles.settingDesc}>{feature.desc}</Text>
                    </View>
                  </View>
                  <View style={styles.activeBadge}>
                    <Check size={12} color={Colors.success} strokeWidth={3} />
                    <Text style={styles.activeBadgeText}>Active</Text>
                  </View>
                </View>
              </View>
            ))}
          </View>
        </View>

        {/* Data Management */}
        <View style={styles.section}>
          <Text style={styles.sectionTitle}>Data</Text>
          <View style={styles.card}>
            <TouchableOpacity style={styles.settingRow} onPress={handleExport} activeOpacity={0.7}>
              <View style={styles.settingLeft}>
                <View style={[styles.settingIcon, { backgroundColor: 'rgba(6, 182, 212, 0.12)' }]}>
                  <Download size={20} color={Colors.secondary} strokeWidth={2} />
                </View>
                <Text style={styles.settingLabel}>Export Data</Text>
              </View>
              <ChevronRight size={20} color={Colors.textTertiary} strokeWidth={2} />
            </TouchableOpacity>
            <View style={styles.divider} />
            <TouchableOpacity style={styles.settingRow} onPress={handleClearData} activeOpacity={0.7}>
              <View style={styles.settingLeft}>
                <View style={[styles.settingIcon, { backgroundColor: 'rgba(239, 68, 68, 0.12)' }]}>
                  <Trash2 size={20} color={Colors.error} strokeWidth={2} />
                </View>
                <Text style={[styles.settingLabel, { color: Colors.error }]}>Clear All Data</Text>
              </View>
              <ChevronRight size={20} color={Colors.textTertiary} strokeWidth={2} />
            </TouchableOpacity>
          </View>
        </View>

        {/* About */}
        <View style={styles.section}>
          <Text style={styles.sectionTitle}>About</Text>
          <View style={styles.card}>
            <View style={styles.settingRow}>
              <View style={styles.settingLeft}>
                <View style={[styles.settingIcon, { backgroundColor: Colors.surfaceAlt }]}>
                  <Info size={20} color={Colors.textSecondary} strokeWidth={2} />
                </View>
                <View style={styles.settingInfo}>
                  <Text style={styles.settingLabel}>Version</Text>
                  <Text style={styles.settingValue}>1.0.0 (Premium)</Text>
                </View>
              </View>
            </View>
          </View>
        </View>

        <Text style={styles.footer}>Sweepy Premium · Made with care</Text>

        <View style={{ height: 40 }} />
      </ScrollView>
    </SafeAreaView>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: Colors.background,
  },
  header: {
    paddingHorizontal: Spacing.xl,
    paddingTop: Spacing.xl,
    paddingBottom: Spacing.lg,
  },
  headerTitle: {
    fontSize: FontSizes.xxxl,
    fontWeight: '800',
    color: Colors.text,
  },
  scrollView: {
    flex: 1,
  },
  scrollContent: {
    paddingHorizontal: Spacing.xl,
  },
  premiumBanner: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: Spacing.md,
    backgroundColor: Colors.primary,
    borderRadius: BorderRadius.xl,
    padding: Spacing.xl,
    marginBottom: Spacing.xl,
    ...Shadows.md,
  },
  premiumIconWrap: {
    width: 52,
    height: 52,
    borderRadius: 26,
    backgroundColor: 'rgba(255, 255, 255, 0.2)',
    alignItems: 'center',
    justifyContent: 'center',
  },
  premiumInfo: {
    flex: 1,
  },
  premiumTitle: {
    fontSize: FontSizes.lg,
    fontWeight: '700',
    color: Colors.textInverse,
  },
  premiumSubtitle: {
    fontSize: FontSizes.sm,
    color: 'rgba(255, 255, 255, 0.8)',
    marginTop: 2,
  },
  premiumBadge: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 4,
    paddingHorizontal: 10,
    paddingVertical: 6,
    borderRadius: BorderRadius.pill,
    backgroundColor: 'rgba(255, 255, 255, 0.2)',
  },
  premiumBadgeText: {
    fontSize: FontSizes.xs,
    fontWeight: '700',
    color: Colors.textInverse,
  },
  section: {
    marginBottom: Spacing.xl,
  },
  sectionTitle: {
    fontSize: FontSizes.sm,
    fontWeight: '700',
    color: Colors.textTertiary,
    textTransform: 'uppercase',
    letterSpacing: 0.5,
    marginBottom: Spacing.sm,
    marginLeft: 4,
  },
  card: {
    backgroundColor: Colors.surface,
    borderRadius: BorderRadius.lg,
    padding: Spacing.lg,
    borderWidth: 1,
    borderColor: Colors.border,
    ...Shadows.sm,
  },
  settingRow: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    minHeight: 48,
  },
  settingLeft: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: Spacing.md,
    flex: 1,
  },
  settingIcon: {
    width: 40,
    height: 40,
    borderRadius: 20,
    alignItems: 'center',
    justifyContent: 'center',
  },
  settingInfo: {
    flex: 1,
  },
  settingLabel: {
    fontSize: FontSizes.md,
    fontWeight: '600',
    color: Colors.text,
  },
  settingValue: {
    fontSize: FontSizes.sm,
    color: Colors.textTertiary,
    marginTop: 2,
  },
  settingDesc: {
    fontSize: FontSizes.xs,
    color: Colors.textTertiary,
    marginTop: 2,
  },
  divider: {
    height: 1,
    backgroundColor: Colors.border,
    marginVertical: Spacing.md,
    marginLeft: 56,
  },
  editBtn: {
    paddingHorizontal: Spacing.md,
    paddingVertical: Spacing.sm,
    borderRadius: BorderRadius.md,
    backgroundColor: Colors.surfaceAlt,
  },
  editBtnText: {
    fontSize: FontSizes.sm,
    fontWeight: '600',
    color: Colors.primary,
  },
  nameEditRow: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: Spacing.sm,
    marginTop: 4,
  },
  nameInput: {
    flex: 1,
    backgroundColor: Colors.surfaceAlt,
    borderRadius: BorderRadius.md,
    paddingHorizontal: Spacing.md,
    paddingVertical: Spacing.sm,
    fontSize: FontSizes.sm,
    color: Colors.text,
    borderWidth: 1,
    borderColor: Colors.border,
  },
  saveNameBtn: {
    width: 36,
    height: 36,
    borderRadius: 18,
    backgroundColor: Colors.primary,
    alignItems: 'center',
    justifyContent: 'center',
  },
  activeBadge: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 4,
    paddingHorizontal: 8,
    paddingVertical: 4,
    borderRadius: BorderRadius.pill,
    backgroundColor: 'rgba(16, 185, 129, 0.12)',
  },
  activeBadgeText: {
    fontSize: FontSizes.xs,
    fontWeight: '700',
    color: Colors.success,
  },
  footer: {
    textAlign: 'center',
    fontSize: FontSizes.sm,
    color: Colors.textTertiary,
    marginTop: Spacing.md,
  },
  errorState: {
    flex: 1,
    alignItems: 'center',
    justifyContent: 'center',
  },
  errorText: {
    fontSize: FontSizes.md,
    color: Colors.textTertiary,
  },
});
