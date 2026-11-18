import { useEffect, useRef } from 'react';
import { StatusBar } from 'expo-status-bar';
import { useKeepAwake } from 'expo-keep-awake';
import { Accelerometer } from 'expo-sensors';
import * as Haptics from 'expo-haptics';
import * as WebBrowser from 'expo-web-browser';
import * as Linking from 'expo-linking';
import { StyleSheet, View } from 'react-native';
import { WebView } from 'react-native-webview';
import gameHtml from './game/gameHtml';

const HAPTIC = {
  light: Haptics.ImpactFeedbackStyle.Light,
  medium: Haptics.ImpactFeedbackStyle.Medium,
  heavy: Haptics.ImpactFeedbackStyle.Heavy,
};

export default function App() {
  useKeepAwake(); // keep the screen on during a race
  const web = useRef(null);
  const tiltSub = useRef(null);

  const stopTilt = () => {
    if (tiltSub.current) { tiltSub.current.remove(); tiltSub.current = null; }
  };
  const startTilt = () => {
    if (tiltSub.current) return;
    Accelerometer.setUpdateInterval(33);
    // forward gravity (in g) to the game, which turns it into a steering angle
    tiltSub.current = Accelerometer.addListener(({ x, y }) => {
      web.current?.injectJavaScript(`window.__tilt&&window.__tilt(${x.toFixed(3)},${y.toFixed(3)});true;`);
    });
  };
  useEffect(() => stopTilt, []);

  // Google does not allow sign-in inside an embedded web view, so sign-in runs in the system browser
  // and the session tokens come back to the game through the lightsoutgp://auth link.
  const signIn = async (gameUrl) => {
    // the return link is lightsoutgp://auth in the installed app, and exp://<pc>:8081/--/auth when testing in Expo Go
    const redirect = Linking.createURL('auth');
    const url = gameUrl.split('?')[0] + '?provider=google&redirect_to=' + encodeURIComponent(redirect);
    const fail = (m) => web.current?.injectJavaScript(`window.__logpSignInFailed&&window.__logpSignInFailed(${JSON.stringify(m)});true;`);
    try {
      const res = await WebBrowser.openAuthSessionAsync(url, redirect);
      if (res.type !== 'success' || !res.url) { fail('Sign-in was cancelled.'); return; }
      const params = new URLSearchParams((res.url.split('#')[1] || res.url.split('?')[1] || ''));
      const at = params.get('access_token'), rt = params.get('refresh_token');
      if (!at || !rt) { fail(params.get('error_description') || 'Sign-in did not complete.'); return; }
      web.current?.injectJavaScript(`window.__logpSession&&window.__logpSession(${JSON.stringify(at)},${JSON.stringify(rt)});true;`);
    } catch {
      fail('Could not open the sign-in page.');
    }
  };

  // messages from the game: { t: 'buzz', s }, { t: 'tilt', on }, { t: 'signin', url, redirect }
  const onMessage = (event) => {
    let msg;
    try { msg = JSON.parse(event.nativeEvent.data); } catch { return; }
    if (msg.t === 'buzz') Haptics.impactAsync(HAPTIC[msg.s] || HAPTIC.light).catch(() => {});
    else if (msg.t === 'tilt') (msg.on ? startTilt : stopTilt)();
    else if (msg.t === 'signin' && typeof msg.url === 'string' && msg.url.startsWith('https://kuompdrogzkazycrohcr.supabase.co/')) signIn(msg.url);
  };

  return (
    <View style={styles.container}>
      <StatusBar hidden />
      <WebView
        ref={web}
        style={styles.game}
        originWhitelist={['*']}
        source={{ html: gameHtml, baseUrl: 'https://lights-out-gp.local/' }}
        onMessage={onMessage}
        javaScriptEnabled
        domStorageEnabled
        mediaPlaybackRequiresUserAction={false}
        allowsInlineMediaPlayback
        scrollEnabled={false}
        bounces={false}
        overScrollMode="never"
        setSupportMultipleWindows={false}
        textZoom={100}
      />
    </View>
  );
}

const styles = StyleSheet.create({
  container: { flex: 1, backgroundColor: '#07090d' },
  game: { flex: 1, backgroundColor: '#07090d' },
});
