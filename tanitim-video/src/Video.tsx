import React from "react";
import { AbsoluteFill, Img, Sequence, interpolate, staticFile, useCurrentFrame } from "remotion";
import { ACCENT, AppIcon, Background, clamp, Cursor, Dock, DockApp, DocWindow, ease, FONT, Headline, SceneFade, Toast, useSpring } from "./parts";
import { gb, Lang, text } from "./text";

// Scene timings in frames (30 fps).
const S = {
  hook: [0, 105],
  problem: [105, 195],
  reveal: [195, 300],
  demo: [300, 480],
  features: [480, 720],
  safety: [720, 840],
  cta: [840, 960],
} as const;
export const DURATION = 960;

const len = (s: readonly [number, number]) => s[1] - s[0];

export const Video: React.FC<{ lang: Lang }> = ({ lang }) => {
  const t = text[lang];
  return (
    <AbsoluteFill style={{ fontFamily: FONT }}>
      <Background />
      <Sequence from={S.hook[0]} durationInFrames={len(S.hook)}><Hook lang={lang} /></Sequence>
      <Sequence from={S.problem[0]} durationInFrames={len(S.problem)}><Problem lang={lang} /></Sequence>
      <Sequence from={S.reveal[0]} durationInFrames={len(S.reveal)}><Reveal tagline={t.tagline} /></Sequence>
      <Sequence from={S.demo[0]} durationInFrames={len(S.demo)}><Demo lang={lang} /></Sequence>
      <Sequence from={S.features[0]} durationInFrames={len(S.features)}><Features lang={lang} /></Sequence>
      <Sequence from={S.safety[0]} durationInFrames={len(S.safety)}><Safety lang={lang} /></Sequence>
      <Sequence from={S.cta[0]} durationInFrames={len(S.cta)}><Cta lang={lang} /></Sequence>
    </AbsoluteFill>
  );
};

const baseDock = ["finder", "safari", "mail", "notes", "music", "textedit", "preview", "calendar"];

// 1. You close the window, but the app keeps running.
const Hook: React.FC<{ lang: Lang }> = ({ lang }) => {
  const t = text[lang];
  const frame = useCurrentFrame();
  const move = interpolate(frame, [8, 42], [0, 1], { ...clamp, easing: ease });
  const close = interpolate(frame, [48, 58], [0, 1], { ...clamp, easing: ease });
  const pulse = interpolate(frame, [62, 74, 86, 98], [0, 1, 0.35, 1], clamp);
  const apps: DockApp[] = baseDock.map((key) => ({ key, running: ["finder", "safari", "textedit"].includes(key), pulse: key === "textedit" ? pulse : 0 }));
  return (
    <SceneFade duration={len(S.hook)} fadeIn={1}>
      <Headline delay={4}>{t.hook1}</Headline>
      {frame > 60 && <Headline delay={60} top={200} size={52} color="#ffd36e">{t.hook2}</Headline>}
      <DocWindow title={t.window} close={close} y={300} hot={frame > 40 && frame < 50} />
      <Cursor x={interpolate(move, [0, 1], [720, 206])} y={interpolate(move, [0, 1], [700, 316])} pressed={frame > 44 && frame < 52} opacity={1 - interpolate(frame, [70, 85], [0, 1], clamp)} />
      <Dock apps={apps} />
    </SceneFade>
  );
};

// 2. It piles up.
const Problem: React.FC<{ lang: Lang }> = ({ lang }) => {
  const t = text[lang];
  const frame = useCurrentFrame();
  const runningOrder = ["finder", "safari", "textedit", "notes", "preview", "mail", "music", "calendar"];
  const count = Math.min(runningOrder.length, 3 + Math.floor(interpolate(frame, [5, 50], [0, 5], clamp)));
  const memory = interpolate(frame, [5, 50], [1.1, 3.4], clamp);
  const apps: DockApp[] = baseDock.map((key) => {
    const index = runningOrder.indexOf(key);
    const startsAt = 5 + (index - 3) * 9;
    return {
      key, running: index < count,
      bounce: index >= 3 ? Math.max(0, Math.sin(interpolate(frame, [startsAt, startsAt + 12], [0, Math.PI], clamp))) : 0,
    };
  });
  return (
    <SceneFade duration={len(S.problem)}>
      <Headline delay={0} top={330}>{t.problem}</Headline>
      <div
        style={{
          position: "absolute", top: 470, left: 0, right: 0, textAlign: "center", fontSize: 34, fontWeight: 600,
          color: "#ff9a8a", fontVariantNumeric: "tabular-nums", opacity: interpolate(frame, [8, 20], [0, 1], clamp),
        }}
      >
        {t.problemStat(count, gb(memory, lang))}
      </div>
      <Dock apps={apps} />
    </SceneFade>
  );
};

// 3. Meet TidyDock.
const Reveal: React.FC<{ tagline: string }> = ({ tagline }) => {
  const frame = useCurrentFrame();
  const pop = useSpring(4, 11);
  const flash = interpolate(frame, [0, 6, 22], [0, 0.55, 0], clamp);
  return (
    <SceneFade duration={len(S.reveal)} fadeIn={1}>
      <AbsoluteFill style={{ background: `rgba(255,255,255,${flash})` }} />
      <AbsoluteFill style={{ alignItems: "center", justifyContent: "center", flexDirection: "column" }}>
        <div style={{ transform: `scale(${pop}) rotate(${(1 - pop) * -12}deg)` }}>
          <AppIcon size={300} glow={0.6} />
        </div>
        <div
          style={{
            marginTop: 28, fontSize: 96, fontWeight: 800, letterSpacing: -3, color: "white",
            opacity: interpolate(frame, [16, 30], [0, 1], clamp), transform: `translateY(${interpolate(frame, [16, 30], [20, 0], { ...clamp, easing: ease })}px)`,
          }}
        >
          TidyDock
        </div>
        <div
          style={{
            marginTop: 18, fontSize: 42, fontWeight: 600, textAlign: "center", lineHeight: 1.25, whiteSpace: "pre-line",
            background: "linear-gradient(90deg, #a8b0ff, #e7a1ff)", WebkitBackgroundClip: "text", color: "transparent",
            opacity: interpolate(frame, [34, 50], [0, 1], clamp),
          }}
        >
          {tagline}
        </div>
      </AbsoluteFill>
    </SceneFade>
  );
};

// 4. The real thing: windows close, apps leave the Dock, the Undo notice shows up.
const Demo: React.FC<{ lang: Lang }> = ({ lang }) => {
  const t = text[lang];
  const frame = useCurrentFrame();
  const quits = [
    { key: "safari", name: "Safari", at: 18, gb: 1.2 },
    { key: "notes", name: lang === "tr" ? "Notlar" : "Notes", at: 70, gb: 0.4 },
    { key: "preview", name: lang === "tr" ? "Önizleme" : "Preview", at: 122, gb: 0.5 },
  ];
  const active = [...quits].reverse().find((q) => frame >= q.at);
  const freed = quits.reduce((sum, q) => sum + q.gb * interpolate(frame, [q.at + 10, q.at + 30], [0, 1], clamp), 0);
  const apps: DockApp[] = baseDock.map((key) => {
    const q = quits.find((item) => item.key === key);
    return { key, running: true, gone: q ? interpolate(frame, [q.at + 8, q.at + 24], [0, 1], { ...clamp, easing: ease }) : 0 };
  });
  const nextWindow = quits.find((q) => frame < q.at + 2);
  const toastP = active ? interpolate(frame, [active.at + 12, active.at + 22, active.at + 46, active.at + 52], [0, 1, 1, 0], clamp) : 0;
  return (
    <SceneFade duration={len(S.demo)}>
      <div style={{ position: "absolute", top: 70, left: 50, fontFamily: FONT, color: "white" }}>
        <div style={{ fontSize: 24, fontWeight: 600, opacity: 0.7 }}>{t.freedLabel}</div>
        <div style={{ fontSize: 76, fontWeight: 800, letterSpacing: -2, fontVariantNumeric: "tabular-nums", color: "#8ff0b5" }}>{gb(freed, lang)}</div>
      </div>
      {nextWindow && (
        <DocWindow
          title={nextWindow.name}
          close={frame >= nextWindow.at - 6 ? interpolate(frame, [nextWindow.at - 6, nextWindow.at + 2], [0, 1], clamp) : 0}
          y={400} x={240} w={600} h={330}
        />
      )}
      {active && (
        <Toast
          icon={`apps/${active.key}.png`}
          title={t.quit(active.name)}
          detail={`${t.noWindows} · ${t.freed(gb(active.gb, lang))}`}
          undo={t.undo}
          progress={toastP}
          top={200}
        />
      )}
      <Dock apps={apps} />
    </SceneFade>
  );
};

// 5. Features, shown on the real menu and settings.
const Features: React.FC<{ lang: Lang }> = ({ lang }) => {
  const t = text[lang];
  const frame = useCurrentFrame();
  const menuIn = useSpring(4, 16);
  const swap = interpolate(frame, [118, 136], [0, 1], { ...clamp, easing: ease });
  return (
    <SceneFade duration={len(S.features)}>
      <Headline delay={0} top={56} size={54}>{t.featuresTitle}</Headline>
      <div style={{ position: "absolute", left: 50, top: 170, width: 470, height: 820 }}>
        <Img
          src={staticFile(`shots/${lang}-menu.png`)}
          style={{
            position: "absolute", width: 470, borderRadius: 18, boxShadow: "0 30px 80px rgba(0,0,0,0.5)",
            opacity: 1 - swap, transform: `translateX(${(1 - menuIn) * -120}px) scale(${1 - swap * 0.05})`,
          }}
        />
        <Img
          src={staticFile(`shots/${lang}-general.png`)}
          style={{
            position: "absolute", height: 720, borderRadius: 18, boxShadow: "0 30px 80px rgba(0,0,0,0.5)",
            opacity: swap, transform: `translateX(${(1 - swap) * -60}px)`,
          }}
        />
      </div>
      <div style={{ position: "absolute", left: 580, top: 230, right: 40, display: "flex", flexDirection: "column", gap: 22 }}>
        {t.features.map(([icon, label], i) => {
          const p = interpolate(frame, [20 + i * 22, 36 + i * 22], [0, 1], { ...clamp, easing: ease });
          return (
            <div
              key={label}
              style={{
                display: "flex", alignItems: "center", gap: 18, padding: "18px 22px", borderRadius: 20,
                background: "rgba(255,255,255,0.09)", border: "1.5px solid rgba(255,255,255,0.12)",
                opacity: p, transform: `translateX(${(1 - p) * 60}px)`,
              }}
            >
              <div
                style={{
                  width: 54, height: 54, borderRadius: 14, display: "grid", placeItems: "center", fontSize: 28, color: "white",
                  background: ["#3b82f6", "#8b5cf6", "#14b8a6", "#eab308", "#6366f1", "#ec4899"][i],
                }}
              >
                {icon}
              </div>
              <div style={{ fontSize: 29, fontWeight: 650, color: "white", whiteSpace: "nowrap" }}>{label}</div>
            </div>
          );
        })}
      </div>
    </SceneFade>
  );
};

// 6. Safe by design.
const Safety: React.FC<{ lang: Lang }> = ({ lang }) => {
  const t = text[lang];
  const frame = useCurrentFrame();
  const icons = ["✓", "☰", "🔒"];
  const colors = ["#22c55e", "#3b82f6", "#a855f7"];
  return (
    <SceneFade duration={len(S.safety)}>
      <Headline delay={0} top={130} size={58}>{t.safetyTitle}</Headline>
      <div style={{ position: "absolute", top: 330, left: 90, right: 90, display: "flex", flexDirection: "column", gap: 34 }}>
        {t.safety.map(([title, sub], i) => {
          const p = interpolate(frame, [12 + i * 14, 28 + i * 14], [0, 1], { ...clamp, easing: ease });
          return (
            <div key={title} style={{ display: "flex", alignItems: "center", gap: 26, opacity: p, transform: `translateY(${(1 - p) * 30}px)` }}>
              <div style={{ width: 84, height: 84, borderRadius: 24, background: colors[i], display: "grid", placeItems: "center", fontSize: 42, color: "white", flexShrink: 0 }}>
                {icons[i]}
              </div>
              <div>
                <div style={{ fontSize: 38, fontWeight: 750, color: "white" }}>{title}</div>
                <div style={{ fontSize: 26, color: "rgba(255,255,255,0.65)", marginTop: 6 }}>{sub}</div>
              </div>
            </div>
          );
        })}
      </div>
    </SceneFade>
  );
};

// 7. Call to action.
const Cta: React.FC<{ lang: Lang }> = ({ lang }) => {
  const t = text[lang];
  const frame = useCurrentFrame();
  const pop = useSpring(0, 13);
  return (
    <SceneFade duration={len(S.cta)} fadeOut={1}>
      <AbsoluteFill style={{ alignItems: "center", justifyContent: "center", flexDirection: "column" }}>
        <div style={{ transform: `scale(${pop})` }}>
          <AppIcon size={220} glow={0.55} />
        </div>
        <div style={{ marginTop: 22, fontSize: 84, fontWeight: 800, letterSpacing: -2.5, color: "white" }}>TidyDock</div>
        <div style={{ marginTop: 10, fontSize: 40, fontWeight: 650, color: "#c9cdff", opacity: interpolate(frame, [10, 24], [0, 1], clamp) }}>{t.ctaTitle}</div>
        <div style={{ marginTop: 8, fontSize: 28, color: "rgba(255,255,255,0.6)", opacity: interpolate(frame, [16, 30], [0, 1], clamp) }}>{t.ctaSub}</div>
        <div
          style={{
            marginTop: 44, padding: "22px 40px", borderRadius: 999, fontSize: 36, fontWeight: 700, color: "white",
            background: `linear-gradient(135deg, ${ACCENT}, #a37dff)`, boxShadow: "0 16px 40px rgba(110,90,255,0.45)",
            opacity: interpolate(frame, [24, 38], [0, 1], clamp), transform: `scale(${interpolate(frame, [24, 38], [0.9, 1], { ...clamp, easing: ease })})`,
          }}
        >
          github.com/utkumeydan/TidyDock
        </div>
      </AbsoluteFill>
    </SceneFade>
  );
};
