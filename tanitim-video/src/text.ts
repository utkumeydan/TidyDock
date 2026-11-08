export type Lang = "tr" | "en";

export const text = {
  tr: {
    window: "Notlar.txt",
    hook1: "Pencereyi kapattın.",
    hook2: "Ama uygulama hâlâ çalışıyor.",
    problem: "Dock'un dolup taşıyor.",
    problemStat: (apps: number, gb: string) => `${apps} uygulama arka planda · ${gb} bellek`,
    tagline: "Son pencere kapanınca,\nuygulama da kapansın.",
    freedLabel: "Boşaltılan bellek",
    quit: (name: string) => `${name} kapatıldı`,
    noWindows: "Açık penceresi yoktu",
    freed: (amount: string) => `${amount} boşaltıldı`,
    undo: "Geri Al",
    featuresTitle: "Her şey menü çubuğunda",
    features: [
      ["↺", "Tek tıkla geri al"],
      ["✦", "Şimdi Temizle"],
      ["▤", "Bellek istatistikleri"],
      ["💡", "Akıllı öneriler"],
      ["☾", "Kullanılmayanları kapat"],
      ["⌘", "Kısayollar · 8 dil"],
    ] as [string, string][],
    safetyTitle: "Yanlış uygulamayı asla kapatmaz",
    safety: [
      ["Kaydedilmemiş işine dokunmaz", "⌘Q gibi nazikçe; kaydetmeyi sorar"],
      ["Menü çubuğu uygulamalarına dokunmaz", "Küçültülmüş ve başka masaüstündeki pencereler açık sayılır"],
      ["Pencere içeriğini okumaz", "Takip yok · Analiz yok"],
    ] as [string, string][],
    ctaTitle: "Ücretsiz ve açık kaynak",
    ctaSub: "macOS 13+ · Apple Silicon ve Intel",
  },
  en: {
    window: "Notes.txt",
    hook1: "You closed the window.",
    hook2: "But the app is still running.",
    problem: "Your Dock keeps filling up.",
    problemStat: (apps: number, gb: string) => `${apps} apps in the background · ${gb} of memory`,
    tagline: "Close the last window,\nand the app goes too.",
    freedLabel: "Memory freed",
    quit: (name: string) => `Quit ${name}`,
    noWindows: "No windows were open",
    freed: (amount: string) => `${amount} freed`,
    undo: "Undo",
    featuresTitle: "All from the menu bar",
    features: [
      ["↺", "Undo in one click"],
      ["✦", "Clean Up Now"],
      ["▤", "Memory stats"],
      ["💡", "Smart suggestions"],
      ["☾", "Quit idle apps"],
      ["⌘", "Shortcuts · 8 languages"],
    ] as [string, string][],
    safetyTitle: "Never quits the wrong thing",
    safety: [
      ["Never loses unsaved work", "Gentle like ⌘Q, apps still ask to save"],
      ["Leaves menu bar apps alone", "Minimized and other-desktop windows count as open"],
      ["Never reads window contents", "No tracking · No analytics"],
    ] as [string, string][],
    ctaTitle: "Free and open source",
    ctaSub: "macOS 13+ · Apple silicon and Intel",
  },
};

/** "1,2 GB" in Turkish, "1.2 GB" in English. */
export const gb = (value: number, lang: Lang) =>
  `${value.toFixed(1).replace(".", lang === "tr" ? "," : ".")} GB`;
