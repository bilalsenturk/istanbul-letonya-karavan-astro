# İstanbul → Riga Karavan Yolculuğu

Astro ile oluşturulmuş karavan yolculuğu brifing ve takip panosu.

## Yolculuk

- **Güzergâh:** İstanbul → Sofya → Bükreş → Deva → Budapeşte → Katowice → Suwałki → Riga
- **Tarih:** 3–10 Ağustos 2026
- **Araç:** VW Passat 1.6 TDI + Adria karavan
- **Toplam:** ~3.150 km

## Proje Yapısı

```
src/
├── components/
│   ├── CameraPlayer.astro   # Şehir kamerası oynatıcı
│   └── RouteMap.astro       # Leaflet interaktif rota haritası
├── data/
│   ├── tripData.json        # Tüm yolculuk verileri
│   └── tripData.ts          # TypeScript tipleri
├── layouts/
│   └── MainLayout.astro     # Ana sayfa düzeni
├── pages/
│   ├── index.astro          # Kontrol paneli
│   └── day/[slug].astro     # Günlük detay sayfaları
└── scripts/
    └── routeMap.ts          # Leaflet harita başlatma
```

## Komutlar

| Komut | Açıklama |
|-------|----------|
| `npm run dev` | Geliştirme sunucusu (`localhost:4321`) |
| `npm run build` | Üretim build'i (`dist/`) |
| `npm run preview` | Build önizlemesi |
| `npm run lint` | ESLint ile kod kontrolü |
| `npm run format` | Prettier ile formatlama |
| `npm run check` | TypeScript tip kontrolü |

## Hesap ve rota altyapısı

iOS uygulaması Apple ile giriş yapar. Astro `/api/v2` uçları oturumu doğrular; hesaplar, rotalar, duraklar ve üyelikler Vercel Private Blob'da saklanır.

| Ortam değişkeni | Amaç |
|---|---|
| `AUTH_SESSION_SECRET` | Kuzey erişim ve yenileme tokenlarını imzalar; en az 32 bayt rastgele değer olmalı |
| `BLOB_READ_WRITE_TOKEN` | Özel `kuzey-accounts` Blob deposu; Vercel bağlantısı otomatik ekler |
| `LIVE_BLOB_READ_WRITE_TOKEN` | Mevcut herkese açık konum, plan, günlük ve harcama deposu |
| `LIVE_POST_SECRET` | iOS uygulamasından gelen canlı konum yazma isteğini doğrular |

Üretimde özel Blob tokenı yoksa hesap API'si veri yazmaz. Yerel geliştirmede hesap deposu yalnızca süreç belleğine düşer ve sunucu yeniden başlayınca temizlenir.

## Yapılan İyileştirmeler

- Veri (JSON) ve tipler (TS) ayrıştırıldı
- Leaflet npm paketi ile CDN bağımlılığı kaldırıldı
- Sitemap, robots.txt ve PWA eklendi
- ESLint + Prettier yapılandırması
- Tarih tekilleştirme, setInterval cleanup, responsive iyileştirmeler
