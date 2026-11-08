import React from "react";
import { AbsoluteFill, Img, interpolate, spring, staticFile, useCurrentFrame, useVideoConfig, Easing } from "remotion";

export const FONT = '-apple-system, BlinkMacSystemFont, "SF Pro Display", "Helvetica Neue", sans-serif';
export const ACCENT = "#7c86ff";

export const clamp = { extrapolateLeft: "clamp", extrapolateRight: "clamp" } as const;
export const ease = Easing.bezier(0.22, 1, 0.36, 1);

/** Fades a scene in at the start and out at the end. */
export const SceneFade: React.FC<{ duration: number; children: React.ReactNode; fadeIn?: number; fadeOut?: number }> = ({
  duration, children, fadeIn = 10, fadeOut = 10,
}) => {
  const frame = useCurrentFrame();
  const opacity = interpolate(frame, [0, fadeIn, duration - fadeOut, duration], [0, 1, 1, 0], clamp);
  return <AbsoluteFill style={{ opacity }}>{children}</AbsoluteFill>;
};

export const Background: React.FC = () => {
  const frame = useCurrentFrame();
  const shift = interpolate(frame, [0, 960], [0, 30]);
  return (
    <AbsoluteFill
      style={{
        background: `radial-gradient(circle at ${30 + shift}% 20%, #3b3f9e 0%, transparent 55%),
                     radial-gradient(circle at ${80 - shift}% 85%, #8a3f8f 0%, transparent 50%),
                     linear-gradient(160deg, #12142e 0%, #1c1640 55%, #2a1538 100%)`,
      }}
    />
  );
};

/** Big headline text that rises and fades in. */
export const Headline: React.FC<{ children: React.ReactNode; delay?: number; size?: number; top?: number; color?: string }> = ({
  children, delay = 0, size = 64, top = 120, color = "white",
}) => {
  const frame = useCurrentFrame();
  const p = interpolate(frame - delay, [0, 18], [0, 1], { ...clamp, easing: ease });
  return (
    <div
      style={{
        position: "absolute", top, left: 60, right: 60, textAlign: "center",
        fontFamily: FONT, fontWeight: 800, fontSize: size, lineHeight: 1.12, letterSpacing: -1.5,
        color, opacity: p, transform: `translateY(${(1 - p) * 30}px)`, whiteSpace: "pre-line",
        textShadow: "0 6px 30px rgba(0,0,0,0.35)",
      }}
    >
      {children}
    </div>
  );
};

export type DockApp = { key: string; running: boolean; gone?: number; pulse?: number; bounce?: number };

/** A macOS-style Dock. `gone` (0…1) shrinks an app out of the Dock. */
export const Dock: React.FC<{ apps: DockApp[]; bottom?: number; size?: number }> = ({ apps, bottom = 56, size = 92 }) => {
  const gap = 14;
  return (
    <div style={{ position: "absolute", bottom, left: 0, right: 0, display: "flex", justifyContent: "center" }}>
      <div
        style={{
          display: "flex", alignItems: "flex-end", padding: "14px 18px 20px", borderRadius: 34,
          background: "rgba(255,255,255,0.16)", border: "1.5px solid rgba(255,255,255,0.22)",
          backdropFilter: "blur(20px)", boxShadow: "0 20px 60px rgba(0,0,0,0.35)",
        }}
      >
        {apps.map((app) => {
          const gone = app.gone ?? 0;
          const width = (size + gap) * (1 - gone);
          const scale = 1 - gone * 0.8;
          const lift = (app.bounce ?? 0) * -28;
          return (
            <div key={app.key} style={{ width, display: "flex", flexDirection: "column", alignItems: "center", overflow: "visible" }}>
              <div style={{ position: "relative", width: size, height: size, transform: `translateY(${lift}px) scale(${scale})`, opacity: 1 - gone }}>
                {app.pulse ? (
                  <div
                    style={{
                      position: "absolute", inset: -10, borderRadius: 28,
                      border: `4px solid rgba(255,210,90,${app.pulse})`, boxShadow: `0 0 ${30 * app.pulse}px rgba(255,200,80,${app.pulse})`,
                    }}
                  />
                ) : null}
                <Img src={staticFile(`apps/${app.key}.png`)} style={{ width: size, height: size }} />
              </div>
              <div
                style={{
                  width: 7, height: 7, borderRadius: 4, marginTop: 6,
                  background: app.running ? `rgba(255,255,255,${0.9 * (1 - gone)})` : "transparent",
                }}
              />
            </div>
          );
        })}
      </div>
    </div>
  );
};

/** A plain document window with traffic lights. `close` (0…1) animates it away. */
export const DocWindow: React.FC<{ title: string; close: number; x?: number; y?: number; w?: number; h?: number; hot?: boolean }> = ({
  title, close, x = 190, y = 230, w = 700, h = 420, hot = false,
}) => {
  if (close >= 1) return null;
  const scale = 1 - close * 0.12;
  return (
    <div
      style={{
        position: "absolute", left: x, top: y, width: w, height: h, borderRadius: 22, background: "#fbfbfd",
        boxShadow: "0 40px 90px rgba(0,0,0,0.45)", opacity: 1 - close, transform: `scale(${scale})`, overflow: "hidden",
      }}
    >
      <div style={{ height: 54, display: "flex", alignItems: "center", padding: "0 22px", gap: 12, borderBottom: "1px solid #e6e6ea" }}>
        {["#ff5f57", "#febc2e", "#28c840"].map((c, i) => (
          <div key={c} style={{ width: 17, height: 17, borderRadius: 9, background: c, boxShadow: hot && i === 0 ? "0 0 0 4px rgba(255,95,87,0.35)" : undefined }} />
        ))}
        <div style={{ flex: 1, textAlign: "center", marginRight: 80, fontFamily: FONT, fontWeight: 600, fontSize: 22, color: "#4a4a50" }}>{title}</div>
      </div>
      {[0.85, 0.7, 0.92, 0.6, 0.78, 0.5].map((wPart, i) => (
        <div key={i} style={{ margin: "26px 34px 0", height: 15, width: `${wPart * 88}%`, borderRadius: 8, background: "#dcdce2" }} />
      ))}
    </div>
  );
};

export const Cursor: React.FC<{ x: number; y: number; pressed?: boolean; opacity?: number }> = ({ x, y, pressed, opacity = 1 }) => (
  <svg width="40" height="54" viewBox="0 0 20 27" style={{ position: "absolute", left: x, top: y, opacity, transform: `scale(${pressed ? 0.88 : 1})`, transformOrigin: "0 0" }}>
    <path d="M1 1 L1 22 L6 17 L10 26 L14 24 L10 15 L17 15 Z" fill="black" stroke="white" strokeWidth="1.6" strokeLinejoin="round" />
  </svg>
);

/** The "Quit … · Undo" notice from the app. */
export const Toast: React.FC<{ icon: string; title: string; detail: string; undo: string; progress: number; top?: number }> = ({
  icon, title, detail, undo, progress, top = 70,
}) => {
  if (progress <= 0) return null;
  return (
    <div
      style={{
        position: "absolute", top: top + (1 - progress) * -20, right: 40, width: 600, padding: "20px 22px", borderRadius: 26,
        display: "flex", alignItems: "center", gap: 18, background: "rgba(246,246,250,0.96)",
        boxShadow: "0 24px 60px rgba(0,0,0,0.4)", opacity: progress, fontFamily: FONT,
      }}
    >
      <Img src={staticFile(icon)} style={{ width: 64, height: 64 }} />
      <div style={{ flex: 1 }}>
        <div style={{ fontWeight: 700, fontSize: 26, color: "#16161a" }}>{title}</div>
        <div style={{ fontSize: 20, color: "#6b6b75", marginTop: 4 }}>{detail}</div>
      </div>
      <div style={{ padding: "10px 18px", borderRadius: 12, background: "#e2e2e8", fontWeight: 600, fontSize: 21, color: "#1f1f24" }}>{undo}</div>
    </div>
  );
};

export const AppIcon: React.FC<{ size: number; glow?: number }> = ({ size, glow = 0.5 }) => (
  <Img
    src={staticFile("tidydock.png")}
    style={{ width: size, height: size, filter: `drop-shadow(0 ${size * 0.12}px ${size * 0.25}px rgba(110,90,255,${glow}))` }}
  />
);

export const useSpring = (delay: number, damping = 14) => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();
  return spring({ frame: frame - delay, fps, config: { damping, mass: 0.8 } });
};
