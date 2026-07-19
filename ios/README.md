# Karavan — iOS Uygulaması (SwiftUI)

İstanbul → Riga karavan yolculuğunun **native iOS dashboard'u**. iPhone ve iPad'de çalışır; App Store gerekmez, kendi cihazlarına Xcode ile kurulur.

## Özellikler

- **Canlı geri sayım** — gün : saat : dk : sn, saniyede bir günceller
- **Canlı konum** — sunucu yok, AirTag yok: cihazın kendi GPS'i. Haritada rota + konumun, Riga'ya kalan km, en yakın durak
- **Canlı hava durumu** — 8 durak, Open-Meteo (anahtar gerektirmez)
- **Gün gün plan** — timeline; her günün risk/fırsat/yedek planı ve kamp detayı
- **Kendini güncelleyen içerik** — veri, deploy edilen sitedeki `/trip-data.json`'dan tazelenir. Siteyi güncellediğinde app içeriği de güncellenir; yeniden kurulum gerekmez. İnternet yoksa gömülü kopya kullanılır.

## Kurulum (kendi cihazına)

1. `ios/Karavan.xcodeproj`'u Xcode ile aç
2. Sol panelde **Karavan** target → **Signing & Capabilities** → **Team** olarak kendi Apple ID'ni seç (Xcode → Settings → Accounts'tan ekleyebilirsin)
3. iPhone/iPad'ini kabloyla bağla, üstteki cihaz listesinden seç
4. **⌘R** — app cihazına kurulur
5. Cihazda ilk açılışta: Ayarlar → Genel → VPN ve Aygıt Yönetimi → geliştirici sertifikana güven

> **Not:** Ücretsiz Apple ID ile kurulan uygulamalar **7 gün** sonra yeniden imza ister (Xcode'dan tekrar ⌘R yeterli). Ücretli Developer hesabıyla (99$/yıl) 1 yıl geçerli olur. Yolculuk 8 gün sürdüğü için yola çıkmadan hemen önce kurmak pratik bir çözüm.

## Veri kaynağını değiştirme

`TripStore.swift` içindeki `remoteDataURL` deploy edilen sitenin adresini gösterir:

```swift
static let remoteDataURL = URL(string: "https://<site-adresin>/trip-data.json")
```

## Projeyi yeniden üretme

Proje [XcodeGen](https://github.com/yonas/xcodegen) ile tanımlı (`project.yml`). Dosya ekleyip çıkardıysan:

```sh
cd ios && xcodegen generate
```
