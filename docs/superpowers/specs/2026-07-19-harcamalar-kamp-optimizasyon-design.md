# Harcamalar · Kamp önerileri & görseller · App optimizasyonu

Tarih: 2026-07-19
Durum: Onaylandı (kullanıcı), implementasyona geçildi.

## Amaç

Kuzey (İstanbul → Riga karavan) projesine üç özellik ekle; native iOS app tam
işlevli olsun, **web'de yalnızca çıktı** görünsün. App hafif ve hızlı kalmalı.

## Genel ilke

Tek veri kaynağı `src/data/tripData.json` → `/trip-data.json` deseni korunur.
App→web akışı için mevcut **konum deseni** kullanılır: Vercel Blob + paylaşılan
`x-live-secret`. Yeni ağır backend (Supabase vb.) yok — yalnızca var olan altyapı.

## 1 + 2 — Harcamalar (EUR)

Para birimi: **sadece EUR**. Kategoriler: `yakit · kamp · yemek · gecis · diger`.

### App (tam işlev)
- `Expense` modeli: `id, amountEur, category, note?, date`.
- `ExpenseStore` (`@MainActor ObservableObject`): kalemler cihazda Documents
  altında JSON dosyasında saklanır (hafif, çevrimdışı, kalıcı). Toplam ve
  kategori kırılımını hesaplar; değişince `/api/expenses`'e toplamı POST eder.
- Panel'de **"Harcama" kartı**: büyük toplam `€X`, bütçe çubuğu + `%Z harcandı`,
  "tahmini bütçe" etiketi. Karta dokununca `ExpensesView` açılır.
- `ExpensesView`: kategori kırılımı + kalem listesi (`List`, kaydır-sil) +
  sağ üstte `+` ile hızlı ekleme sheet'i (tutar · kategori · not · tarih).

### Web (yalnızca çıktı)
- `src/pages/api/expenses.ts`: `POST` (secret ile) toplamı Blob'a yazar
  (`kuzey/expenses.json`), `GET` okur. Konum API'siyle birebir desen.
- `index.astro`: küçük **"Harcanan €X · %Z"** kartı. Kalem/kategori YOK.
- Bütçe tavanı = `totalBudget.max` (€1.795); pratik hedef metni yanında gösterilir.

## 3 — Kamp önerileri + görseller

- `camp` verisine iki alan: `image` (barındırılan yol) + `alternatives[]`
  (şehir başına 2-3 **gerçek** kamp: `name, place, link, note?`).
- Görseller `public/assets/camps/` altında **optimize** edilir (≈800px genişlik,
  WebP/JPEG, hedef < 90KB). App bunları **ağdan** yükler → app boyutu büyümez.
- App: `DayDetailView` üstünde hero görsel (`CampImage`) + "Diğer kamp
  seçenekleri" bölümü. Liste ekranı metin kalır (hafif).
- Web: `day/[slug].astro` kamp bloğuna görsel + alternatif kartları.
- Kaynak: 7 benzersiz şehir (Sofya, Bükreş, Deva, Budapeşte, Katowice, Suwałki,
  Riga). Temsili, serbest lisanslı (Wikimedia/Unsplash) görseller.

## 4 — Optimizasyon

- Görseller app'e gömülmez → IPA küçük kalır (en büyük kazanç).
- `CampImage`: `URLCache` tabanlı önbellekli async görsel; yükleme/başarısızlıkta
  temalı gradyan + çadır ikonu fallback (eksik görsel UI'ı bozmaz).
- Listelerde `LazyVStack`/`List`.
- Yeni görseller sıkıştırılmış; bonus: web'deki 2.25MB `passat-adria-karavan.png`
  optimize edilir.

## Dosyalar

Yeni: `ios/Karavan/Expense.swift`, `ios/Karavan/ExpenseStore.swift`,
`ios/Karavan/Views/ExpensesView.swift`, `ios/Karavan/Views/CampImage.swift`,
`src/pages/api/expenses.ts`, `public/assets/camps/*`.

Düzenleme: `ios/Karavan/Models.swift` (Budget min/max, Camp image+alternatives),
`ios/Karavan/Config.swift` (expensesPostURL + imageBaseURL),
`ios/Karavan/KaravanApp.swift` (ExpenseStore inject),
`ios/Karavan/Views/DashboardView.swift` (Harcama kartı),
`ios/Karavan/Views/DayDetailView.swift` (görsel + alternatifler),
`ios/Karavan/Resources/trip.json` (gömülü kopya güncelle),
`src/data/tripData.json` + `src/data/tripData.ts` (camp alanları),
`src/pages/index.astro` (Harcanan kartı), `src/pages/day/[slug].astro`.

## Doğrulama

- `cd ios && xcodegen generate` → `xcodebuild ... -destination 'iOS Simulator'`
  temiz derlenmeli.
- Simülatöre kur + çalıştır; Panel'de Harcama kartı, ekleme akışı, kamp görselleri
  görünmeli.
- `astro build` web tarafında hatasız olmalı.
