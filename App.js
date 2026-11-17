import { useEffect, useRef } from 'react';
import { StatusBar } from 'expo-status-bar';
import { useKeepAwake } from 'expo-keep-awake';
import { Accelerometer } from 'expo-sensors';
import * as Haptics from 'expo-haptics';
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

  // messages from the game: { t: 'buzz', s: 'light' | 'medium' | 'heavy' } and { t: 'tilt', on }
  const onMessage = (event) => {
    let msg;
    try { msg = JSON.parse(event.nativeEvent.data); } catch { return; }
    if (msg.t === 'buzz') Haptics.impactAsync(HAPTIC[msg.s] || HAPTIC.light).catch(() => {});
    else if (msg.t === 'tilt') (msg.on ? startTilt : stopTilt)();
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
