import 'react-native-url-polyfill/auto';
import { createClient } from '@supabase/supabase-js';
import * as SecureStore from 'expo-secure-store';
import { AppState } from 'react-native';

const supabaseUrl = process.env.EXPO_PUBLIC_SUPABASE_URL;
const supabaseAnonKey = process.env.EXPO_PUBLIC_SUPABASE_ANON_KEY;

if (!supabaseUrl || !supabaseAnonKey) {
  throw new Error(
    'Missing Supabase config. Copy app/.env.example to app/.env and fill in ' +
      'EXPO_PUBLIC_SUPABASE_URL and EXPO_PUBLIC_SUPABASE_ANON_KEY, then restart expo.',
  );
}

// ---------------------------------------------------------------------------
// SecureStore-backed session storage.
// iOS keychain items are rejected above ~2048 bytes and Supabase sessions are
// larger than that, so values are split into chunks stored under
// `<key>.<n>` with the chunk count under `<key>.count`. The count marker is
// written last: a torn write leaves no marker, which reads back as null
// (signed out) instead of a corrupt session.
// ---------------------------------------------------------------------------
const CHUNK_SIZE = 1800;

async function removeChunks(key: string): Promise<void> {
  const countRaw = await SecureStore.getItemAsync(`${key}.count`);
  const count = countRaw ? Number(countRaw) : 0;
  const deletions: Promise<void>[] = [];
  for (let i = 0; i < count; i++) deletions.push(SecureStore.deleteItemAsync(`${key}.${i}`));
  deletions.push(SecureStore.deleteItemAsync(`${key}.count`));
  deletions.push(SecureStore.deleteItemAsync(key)); // legacy unchunked value
  await Promise.all(deletions);
}

const chunkedSecureStorage = {
  async getItem(key: string): Promise<string | null> {
    const countRaw = await SecureStore.getItemAsync(`${key}.count`);
    if (countRaw == null) return SecureStore.getItemAsync(key);
    const count = Number(countRaw);
    if (!Number.isInteger(count) || count <= 0) return null;
    const chunks = await Promise.all(
      Array.from({ length: count }, (_, i) => SecureStore.getItemAsync(`${key}.${i}`)),
    );
    if (chunks.some((c) => c == null)) return null;
    return chunks.join('');
  },
  async setItem(key: string, value: string): Promise<void> {
    await removeChunks(key);
    const count = Math.ceil(value.length / CHUNK_SIZE) || 1;
    for (let i = 0; i < count; i++) {
      await SecureStore.setItemAsync(`${key}.${i}`, value.slice(i * CHUNK_SIZE, (i + 1) * CHUNK_SIZE));
    }
    await SecureStore.setItemAsync(`${key}.count`, String(count));
  },
  async removeItem(key: string): Promise<void> {
    await removeChunks(key);
  },
};

export const supabase = createClient(supabaseUrl, supabaseAnonKey, {
  auth: {
    storage: chunkedSecureStorage,
    autoRefreshToken: true,
    persistSession: true,
    detectSessionInUrl: false, // OTP codes, not URL callbacks
  },
});

// Refresh tokens only while the app is foregrounded (Supabase's recommended
// React Native pattern).
AppState.addEventListener('change', (state) => {
  if (state === 'active') {
    supabase.auth.startAutoRefresh();
  } else {
    supabase.auth.stopAutoRefresh();
  }
});
