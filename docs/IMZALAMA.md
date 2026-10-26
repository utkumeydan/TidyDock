# Kalıcı imza kurulumu (ücretsiz, bir kez yapılır)

## Neden gerekli?

macOS, Erişilebilirlik iznini uygulamanın **imzasına** bağlar. Şu an TidyDock her derlemede rastgele, geçici bir imza (ad-hoc) alıyor. macOS her yeni derlemeyi başka bir uygulama sanıyor ve izni unutuyor.

Kendi sertifikanla imzalarsan imza her sürümde aynı kalır. İzni bir kez verirsin, güncellemelerden sonra da korunur. Bu sertifika ücretsizdir; Apple Developer hesabı gerekmez.

## 1. Sertifikayı oluştur

1. **Anahtar Zinciri Erişimi** uygulamasını aç. Spotlight'ta (⌘ Boşluk) "Anahtar Zinciri" yazman yeterli. Bulamazsan Terminal'de şunu çalıştır:
   ```bash
   open "/System/Library/CoreServices/Applications/Keychain Access.app"
   ```
2. Üst menüden **Anahtar Zinciri Erişimi › Sertifika Yardımcısı › Sertifika Oluştur…** seç.
3. Açılan pencereyi şöyle doldur:
   - **Ad:** `TidyDock Development` (harfi harfine böyle yaz)
   - **Kimlik Türü:** Kendinden İmzalı Kök
   - **Sertifika Türü:** Kod İmzalama
4. **Oluştur**'a, ardından **Devam**'a ve **Bitti**'ye bas.

## 2. Sertifikaya güven ver

1. Anahtar Zinciri Erişimi'nde sol tarafta **oturum açma** anahtar zincirini, üstte **Sertifikalar** sekmesini seç.
2. Listede **TidyDock Development**'a çift tıkla.
3. **Güven** bölümünü aç. **Kod İmzalama** satırını **Her Zaman Güven** yap.
4. Pencereyi kapat. Mac parolanı ister; gir.

## 3. Kontrol et

Terminal'de şunu çalıştır:

```bash
security find-identity -v -p codesigning
```

Çıktıda şuna benzer bir satır görmelisin:

```
1) 3F2A…  "TidyDock Development"
     1 valid identities found
```

## 4. Derle ve izni son kez ver

```bash
cd ~/Desktop/AI/TidyDock
./scripts/build-app.sh
```

Çıktıda `Signing with identity: TidyDock Development` yazmalı. Derleme betiği sertifikayı kendiliğinden bulur.

İlk seferde macOS "codesign anahtar zincirinizdeki anahtarı kullanmak istiyor" diye sorar. Mac parolanı girip **Her Zaman İzin Ver**'e bas; bir daha sormaz.

Ardından eski izin kayıtlarını temizleyip uygulamayı aç:

```bash
tccutil reset Accessibility io.github.utkumeydan.TidyDock
open build/TidyDock.app
```

Karşılama ekranındaki adımlarla izni ver. **Bu son sefer.** Bundan sonraki her derlemede izin kalır.

## 5. Yedekle

Bu sertifika artık TidyDock'un kimliği. Kaybedersen yeni sertifikayla imzalanan ilk sürümde kullanıcıların izni yeniden vermesi gerekir. Bu yüzden yedekle:

1. Anahtar Zinciri Erişimi'nde **TidyDock Development**'a sağ tıkla › **"TidyDock Development" Öğesini Dışa Aktar…**
2. Biçim olarak **Kişisel Bilgi Değişimi (.p12)** seç ve güçlü bir parola ver.
3. `.p12` dosyasını güvenli bir yerde sakla (şifreli bir disk ya da parola yöneticisi gibi). **Asla depoya ekleme.** `.gitignore` zaten `*.p12` dosyalarını dışarıda tutuyor.

GitHub'da otomatik yayın için aynı `.p12` dosyasını kullanacaksın. Bu adımlar [YAYINLAMA.md](YAYINLAMA.md) dosyasının 2. bölümünde. Orada sertifika adı olarak `TidyDock Development` kullanman yeterli. İstersen ayrı bir `TidyDock Release` sertifikası da oluşturabilirsin; ama o zaman kendi derlediğin sürümle GitHub'dakinin imzası farklı olur.

## Sorun giderme

| Belirti | Çözüm |
|---|---|
| `0 valid identities found` | 2. adımı atlamış olabilirsin: Kod İmzalama için "Her Zaman Güven" seçilmeli. |
| Derleme `Signing with identity: -` diyor | Sertifikanın adı tam olarak `TidyDock Development` olmalı. |
| `errSecInternalComponent` hatası | Anahtar zinciri kilitli. `security unlock-keychain` çalıştır, ardından tekrar dene. |
| İzin verdim ama "İzin bekleniyor" diyor | Bu sertifikayla ilk derlemede bir kez `tccutil reset …` gerekiyor (4. adım). |
