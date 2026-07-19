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

## Yapılan İyileştirmeler

- Veri (JSON) ve tipler (TS) ayrıştırıldı
- Leaflet npm paketi ile CDN bağımlılığı kaldırıldı
- Sitemap, robots.txt ve PWA eklendi
- ESLint + Prettier yapılandırması
- Tarih tekilleştirme, setInterval cleanup, responsive iyileştirmeler
