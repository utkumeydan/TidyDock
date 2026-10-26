# Yayınlama rehberi (geliştirici için)

Bu rehber, Apple Developer hesabı olmadan TidyDock'u GitHub'da yayınlama adımlarını anlatır. 1–4 arası adımlar yalnızca bir kez yapılır.

## 1. GitHub deposunu oluştur

```bash
cd TidyDock
git add . && git commit -m "TidyDock v0.1.0"
gh repo create utkumeydan/TidyDock --public --source . --push
```

## 2. Kendinden imzalı sertifikayı GitHub'a ekle

Her sürüm aynı sertifikayla imzalanırsa kullanıcıların Erişilebilirlik izni güncellemelerden sonra korunur.

1. Sertifikayı henüz oluşturmadıysan [IMZALAMA.md](IMZALAMA.md) dosyasındaki adımları izle.
2. Aynı dosyanın 5. bölümünde anlatıldığı gibi sertifikayı `.p12` olarak dışa aktar.
3. GitHub gizli değişkenlerine ekle:
   ```bash
   gh secret set SIGNING_CERT_P12 < <(base64 -i TidyDock.p12)
   gh secret set SIGNING_CERT_PASSWORD     # .p12 parolası
   gh secret set SIGNING_IDENTITY --body "TidyDock Development"
   ```
4. `.p12` dosyasını güvenli bir yerde sakla ve **asla depoya ekleme**.

## 3. Sparkle anahtarlarını oluştur

```bash
mkdir -p /tmp/sparkle
curl -L https://github.com/sparkle-project/Sparkle/releases/download/2.10.1/Sparkle-2.10.1.tar.xz | tar -xJ -C /tmp/sparkle
/tmp/sparkle/bin/generate_keys            # genel anahtarı yazdırır, özel anahtarı Anahtar Zinciri'ne kaydeder
/tmp/sparkle/bin/generate_keys -x sparkle-private.key
gh secret set SPARKLE_PUBLIC_KEY --body "<yazdırılan genel anahtar>"
gh secret set SPARKLE_PRIVATE_KEY < sparkle-private.key
rm sparkle-private.key
```

Özel anahtar Anahtar Zinciri'nde yedekli kalır. Kaybedersen mevcut kullanıcılara otomatik güncelleme gönderemezsin.

## 4. GitHub Pages'i aç

İlk sürüm yayınlandıktan sonra `gh-pages` dalı oluşur. Deponun **Settings › Pages** bölümünde kaynak olarak `gh-pages` dalını seç. Güncelleme listesi şu adreste yayınlanır: `https://utkumeydan.github.io/TidyDock/appcast.xml`

## 5. Her sürümde

```bash
git tag v0.1.0
git push origin v0.1.0
```

GitHub Actions sırasıyla şunları yapar:
1. Testleri çalıştırır.
2. Universal (Apple Silicon + Intel) derleme alır ve imzalar.
3. `TidyDock-0.1.0.zip` dosyasıyla bir GitHub Release oluşturur.
4. Sparkle güncelleme listesini (appcast) GitHub Pages'e yayınlar.

İş akışının özet sayfasında Homebrew için gereken `version` ve `sha256` değerleri yazar.

## 6. Homebrew tap

1. Bir kez `utkumeydan/homebrew-tap` adında herkese açık bir depo oluştur.
2. `packaging/homebrew/tidydock.rb` dosyasını bu depoya `Casks/tidydock.rb` olarak kopyala.
3. Her sürümde dosyadaki `version` ve `sha256` değerlerini güncelle.

Kullanıcılar şu komutla kurar:

```bash
brew install --cask utkumeydan/tap/tidydock
```

## İleride Developer hesabı alınırsa

`SIGNING_IDENTITY` değerini `Developer ID Application: …` sertifikasıyla değiştirmek yeterli. Derleme betiği bu durumda hardened runtime'ı kendiliğinden açar. Ardından iş akışına bir `xcrun notarytool submit … --wait` ve bir `xcrun stapler staple` adımı eklenir. Notarize edilen uygulamalar Homebrew'un resmi deposuna da gönderilebilir.
