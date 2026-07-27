# Çoklu Kaynaklı Güvenli Rota ve Çevrimdışı Navigasyon Tasarımı

- **Tarih:** 27 Temmuz 2026
- **Durum:** Onaylandı
- **Ürün:** Kuzey iOS uygulaması ve Astro/Vercel servis katmanı

## 1. Amaç

Kuzey, Apple Maps'e tek başına güvenmeden araç veya araç-karavan birleşimine uygun rota üretir. Sistem Apple, HERE, TomTom ve açık harita verilerini karşılaştırır; yasal ve fiziksel kısıtları uygular; güvenli yolu gereksiz yere uzatmaz; farkı kullanıcıya açıklar; onaylanan rotayı uygulama içi navigasyona ve çevrimdışı yolculuk paketine kaydeder.

Ürün, gelişmiş motoru Apple düzeyinde sakin bir arayüzle sunar. Ana ekranda yalnızca karar için gerekli bilgiler görünür. Ayrıntılı kaynaklar, puanlar ve seçenekler istek üzerine açılır.

## 2. Başarı ölçütleri

Sistem aşağıdaki sonuçları sağlamalıdır:

1. Araç yüksekliği, genişliği, uzunluğu, ağırlığı, dingil yükü, römork yasağı veya yol erişimiyle çelişen rota önerilmez.
2. Normal koşullarda önerilen rota, en hızlı uygun rotadan en fazla yüzde 15 uzun sürer.
3. Daha uzun tek güvenli rota bu sınırın dışındaysa sistem rotayı gizlemez; süre farkını ve güvenlik gerekçesini gösterir.
4. Kullanıcı `Dengeli`, `Otoyol`, `Rahat` veya `Ekonomik` sürüş karakterini seçebilir.
5. `Otoyol` modu, başlangıç ve varış için gereken en kısa güvenli bağlantılar dışında mümkün olan en yüksek otoyol oranını seçer.
6. Onay ekranı süre, mesafe, otoyol oranı, tüketim, ücret, güven durumu ve seçimin en önemli üç gerekçesini gösterir.
7. Kullanıcı onay vermeden planlanan rota aktif yolculuğa girmez.
8. Onaylanan rota ve gereken navigasyon verileri bağlantı olmadan kullanılabilir.
9. Normal trafik iyileştirmeleri aktif rotayı sessizce değiştirmez. Onaylanmış bir kapanma veya araca aykırı yasal kısıt güvenli yeniden rotayı tetikleyebilir.
10. Sağlayıcı kesintisi, düşük veri güveni veya eksik çevrimdışı paket kullanıcıdan saklanmaz.
11. Önbellekteki plan 500 milisaniye içinde açılır. Normal bağlantıda ilk uygun aday beş saniye, tam karşılaştırma on iki saniye içinde hedeflenir; yavaş sağlayıcı ana sonucu engellemez.
12. Mevcut aile/kişisel kullanım ölçeğinde dış rota ve navigasyon hizmetlerinin toplam yinelenen maliyet tavanı aylık 50 avrodur. Tavanı aşan HERE teklifi yedek mimariyi etkinleştirir.

## 3. Kapsam ve sınırlar

### 3.1 Kapsam

- iOS içinde harita, rota planlama, sesli yönlendirme, sapma algılama ve yeniden rota
- Birden fazla araç ve araç-römork profili
- Dizel, benzin, LPG/CNG, hibrit, plug-in hibrit ve elektrikli araç tüketimi
- Apple, HERE, TomTom ve açık harita kaynaklarından aday rota
- Yol sınıfı, yüzey, kısıt, trafik, çalışma, kapanma, hava ve enerji doğrulaması
- Kullanıcı onayı ve onaylanan rota sürümü
- Rota koridoru ve isteğe bağlı ülke/bölge çevrimdışı paketleri
- Maliyet kotası, önbellek, sağlayıcı devre kesici ve düşük güvenli çalışma kipleri
- Mevcut çoklu rota, rol ve senkron altyapısıyla uyum

### 3.2 Kapsam dışı

- Mutlak güvenlik garantisi
- Apple'ın yönettiği çevrimdışı Apple Maps paketlerini uygulama içinden indirme veya denetleme
- Topluluk bildirimini tek başına yasal kısıt ya da kapanma kanıtı sayma
- CarPlay entitlement alınmadan tam CarPlay navigasyon arayüzü
- İlk sürümde küresel kaza kara nokta verisi; yalnızca lisansı ve güncelliği doğrulanmış resmi veri eklenebilir
- Sağlayıcı sözleşmesinin izin vermediği geometriyi saklama, dışa aktarma veya başka sağlayıcıya gönderme

## 4. Ürün ilkeleri

1. **Güvenlik önce gelir.** Yasal ve fiziksel uygunluk maliyet veya süreyle takas edilmez.
2. **Tek kaynağa güvenilmez.** Her kaynak, izin verdiği ölçüde bağımsız kanıt sağlar.
3. **Belirsizlik görünürdür.** Eksik veri güvenli kabul edilmez; güven durumu düşürülür.
4. **Onaylanan yol korunur.** Navigasyon, daha kısa diye başka koridora sessizce geçmez.
5. **Arayüz sakin kalır.** Motor karmaşık, ana karar yüzeyi sadedir.
6. **Çevrimdışı çalışma gerçek olmalıdır.** Önbelleğe alınmış bir çizgi, çevrimdışı navigasyon sayılmaz.
7. **Maliyet ölçülür ve sınırlandırılır.** Aynı rota için gereksiz sağlayıcı çağrısı yapılmaz.

## 5. Sağlayıcı stratejisi

### 5.1 HERE Navigate: birincil navigasyon

HERE Navigate, son rota geometrisini, uygulama içi haritayı, manevraları, araç kısıtı uyarılarını, sapma algılamayı ve çevrimdışı navigasyonu sağlar. Rota isteği, araç türüne göre `car`, `truck` veya elektrikli taşıt özelliklerini kullanır. Araç-römork birleşimi için yönlendirme zarfı; toplam ölçüleri, yüklü ağırlığı ve dingil değerlerini içerir.

HERE 4.26 ve sonrası sürümlerde çevrimdışı rota ve `truck` katmanları varsayılan olarak indirilmeyebilir. Uygulama, çevrimdışı paket yapılandırmasında `offlineRouting` ve `truck` verisini açıkça etkinleştirir. Uygulama bu katmanları doğrulamadan paketi `Hazır` saymaz.

### 5.2 TomTom: bağımsız rota, trafik ve enerji görüşü

TomTom; alternatif güzergâh, trafik, kapanma, çalışma, otoyol/tünel/feribot bölümleri, araç ölçüleri ve enerji tüketimi için ikinci görüş sağlar. TomTom anahtarı iOS uygulamasına gömülmez; Astro/Vercel servis katmanı çağrıyı sunucu tarafında yapar.

### 5.3 Apple MapKit: birinci sınıf karşılaştırma ve yedek

Apple Maps sistemden çıkarılmaz.

- `MKDirections`, bağımsız rota süresi ve koridor karşılaştırması sağlar.
- `MKLocalSearch` ve Look Around; kamp, yakıt, şarj, mola ve kesin varış noktalarını doğrular.
- Kullanıcı her zaman `Apple Maps'te aç` eylemini görebilir.
- HERE veya uzaktaki servisler kullanılamazsa MapKit çevrimiçi hızlı rota yedeği olur.

MapKit, karavan ölçülerini rota kısıtı olarak işlemediği için tek başına `araç için doğrulandı` sonucu üretemez. Apple adayı süre, yer ve genel koridor kanıtına katkı verir; sert araç uygunluğu kararını vermez.

### 5.4 Açık veri ve açık rota motoru

GraphHopper tabanlı bir sağlayıcı, OSM yol sınıfı ve kısıt verileriyle bağımsız aday üretir. Sağlayıcı arayüzü, ileride GraphHopper hizmetini kendi Valhalla/GraphHopper dağıtımımızla değiştirmeye izin verir.

Uzun koridorlar için genel Overpass örnekleri çalışma zamanı bağımlılığı olmaz. Üretim doğrulaması, sürümlenmiş bölgesel OSM çıkarımları veya sözleşmeli bir açık rota hizmeti kullanır. `surface`, `smoothness`, `lanes`, `lit`, `maxheight`, `maxwidth`, `maxlength`, `maxweight`, `access`, `motor_vehicle`, `trailer` ve `highway` gibi alanların kapsamı ölçülür.

### 5.5 Resmi ve canlı kaynaklar

Bir `SourceRegistry`, rota ülkelerine göre etkin kaynakları seçer:

- Ulusal veya bölgesel DATEX II kapanma, çalışma ve trafik akışları
- Resmi sınır kapısı ve feribot bilgileri
- Mevcut Open-Meteo temelli hava verisi
- Lisanslı yakıt fiyatı ve şarj durumu, erişim varsa

Her kayıt kaynak, kapsama alanı, alınma zamanı, geçerlilik aralığı ve kalite sınıfı taşır. Kapsanmayan ülke için veri varmış gibi davranılmaz.

## 6. Mimari

### 6.1 iOS bileşenleri

| Bileşen                    | Sorumluluk                                                                      |
| -------------------------- | ------------------------------------------------------------------------------- |
| `VehicleGarageStore`       | Araç profillerini, doğrulama durumunu ve öğrenilen tüketimi saklar.             |
| `RoutePlanningCoordinator` | Yerel ve uzak sağlayıcı çağrılarını eşgüdümler; iptal ve zaman aşımını yönetir. |
| `AppleRouteProvider`       | MapKit adayını ve yer doğrulamasını üretir.                                     |
| `HERERouteProvider`        | Birincil online/offline adayları ve son navigasyon rotasını üretir.             |
| `RemoteRouteProvider`      | TomTom, açık rota ve resmi kanıt uç noktasını çağırır.                          |
| `RouteCandidateNormalizer` | Sağlayıcı sonuçlarını ortak aday biçimine çevirir.                              |
| `RouteSafetyEngine`        | Sert kuralları, kanıt güvenini ve seçim sırasını uygular.                       |
| `ConsumptionEstimator`     | Yakıt, elektrik ve hibrit tüketim aralığını hesaplar.                           |
| `ApprovedRouteStore`       | Onaylanan sürümü, geometriyi, özeti ve kanıt parmak izini saklar.               |
| `OfflineTripPackManager`   | Harita bölgelerini, rota koridorunu, manevraları ve ek veriyi indirir.          |
| `NavigationCoordinator`    | HERE navigasyonunu, yeniden rota politikasını ve Apple'a geçişi yönetir.        |

Bu birimler protokoller üzerinden haberleşir. Puanlama motoru MapKit, HERE SDK veya ağ sınıflarını doğrudan bilmez. Böylece saf mantık testleri sağlayıcı SDK'sı olmadan çalışır.

### 6.2 Astro/Vercel bileşenleri

Yeni uç noktalar mevcut `src/pages/api/v2` düzenini izler ve `prerender = false` kullanır:

| Uç nokta                                 | İşlev                                                                       |
| ---------------------------------------- | --------------------------------------------------------------------------- |
| `POST /api/v2/routes/compare`            | TomTom, açık rota ve canlı kanıtları getirir; ortak uzak yanıtı döndürür.   |
| `POST /api/v2/trips/[id]/approved-route` | Yetkili kullanıcının onayladığı rota sürümünü kaydeder.                     |
| `GET /api/v2/trips/[id]/approved-route`  | Üyelerin onaylanan rota özetini ve izin verilen geometriyi almasını sağlar. |
| `GET /api/v2/routes/sources`             | Kaynak sağlığı, kapsama ve güncellik özetini verir.                         |

Sunucu, sağlayıcı anahtarlarını ortam değişkenlerinden okur. Günlük veya aylık kullanım kotası sunucuda uygulanır. Sağlayıcı yanıtları sözleşmenin izin verdiği süre ve ayrıntı düzeyinde saklanır.

### 6.3 İstek akışı

1. Kullanıcı başlangıç, hedef, ara durak, araç ve sürüş karakterini seçer.
2. iOS, plan parmak izi üretir. Parmak izi rota noktalarını, araç yönlendirme zarfını, seçenekleri ve kalkış zamanı dilimini içerir.
3. `RoutePlanningCoordinator`, Apple ve HERE adaylarını cihazda; TomTom ve açık adayları sunucuda paralel hesaplar.
4. Uzak servis, canlı olayları ve yol kanıtını aday koridorlara bağlar.
5. `RouteCandidateNormalizer`, izin verilen sonuçları ortak bölümlere dönüştürür.
6. `RouteSafetyEngine`, sert uygunluk kurallarını uygular ve kalan adayları karşılaştırır.
7. HERE, seçilen koridoru son navigasyon rotası olarak hesaplar veya sözleşmenin izin verdiği destek noktalarıyla içe aktarır.
8. Motor son HERE rotasını bir kez daha sert kurallardan geçirir. Seçim ile son geometri farklılaşırsa onay ekranı güncellenir.
9. Kullanıcı onaylar. `ApprovedRouteStore` yerel sürümü yazar; yetkili kullanıcı sunucuya senkronlar.
10. `OfflineTripPackManager`, çevrimdışı paket planını ve boyutunu üretir.

Her sağlayıcı sekiz saniyelik bağımsız zaman aşımına sahiptir. İlk uygun sonuç geldiğinde kullanıcı önizlemeyi görür; daha sonra gelen kanıtlar öneriyi değiştirecekse ekran farkı açıkça günceller. Kullanıcı planlama ekranından ayrılırsa gereksiz çağrılar iptal edilir.

## 7. Ortak veri modeli

### 7.1 Araç profili

`VehicleProfile` şu alanları taşır:

- Kimlik, ad ve araç sınıfı
- Enerji türü: dizel, benzin, LPG/CNG, hibrit, plug-in hibrit veya elektrik
- Çekici ölçüleri ve isteğe bağlı römork/karavan ölçüleri
- Toplam yüklü uzunluk, genişlik, yükseklik, ağırlık, dingil yükü ve dingil sayısı
- Römork durumu, ticari kullanım, emisyon sınıfı ve güvenli azami hız
- Yakıt deposu, kullanılabilir batarya, başlangıç doluluğu ve minimum varış rezervi
- Şehir, karma ve otoyol tüketim eğrileri
- Kullanıcı ölçümü, üretici değeri veya öğrenilen değer kaynak bilgisi
- Son doğrulama tarihi ve kritik ölçülerin doğrulanma durumu

Profil, `declaredDimensions` ile `routingEnvelope` değerlerini ayırır. Yönlendirme zarfı ölçüm belirsizliği için kullanıcıya açık bir güvenlik payı ekleyebilir. Sistem yüklü birleşim ölçülerini kullanır; yalnız çekici ölçülerini kullanıp karavanı unutmaz.

İlk hazır profil `VW Passat B8 + Adria Altea 432 PX` olur. Modelden gelen başlangıç değerleri öneri sayılır; kullanıcı kritik ölçüleri ilk rota onayından önce doğrular.

### 7.2 Rota adayı

`RouteCandidate` aşağıdaki alanları sağlar:

- Sağlayıcı ve sağlayıcı rota kimliği
- Başlangıç, hedef, ara duraklar ve kalkış zamanı
- Geometri veya sözleşmenin izin verdiği koridor özeti
- Mesafe, süre, trafik gecikmesi ve varış zamanı
- Otoyol, bölünmüş yol, şehir içi, asfaltsız yol, tünel, köprü, feribot ve ücret bölümleri
- Manevra yoğunluğu, eğim, viraj ve yol yüzeyi özeti
- Araç kısıtı bulguları ve bilinmeyen alanlar
- Hava, kapanma, çalışma ve sınır bulguları
- Yakıt/enerji aralığı, ücretler ve mola/şarj durakları
- Kanıt kaynakları, zamanları ve saklama izinleri

### 7.3 Onaylanan rota

`ApprovedRoute` değişmez bir sürümdür:

- `routeId`, `tripId`, sürüm ve önceki sürüm
- Onaylayan kullanıcı, rol ve zaman
- Araç profilinin tam anlık görüntüsü
- Sürüş karakteri ve ince ayarlar
- Birincil HERE rota kimliği, izin verilen geometri ve manevralar
- Mesafe, süre, otoyol oranı, tüketim aralığı ve ücret özeti
- Güvenlik, güvenilirlik, konfor ve maliyet sonuçları
- Kaynak ve veri güncellik özeti
- Onay gerekçeleri
- Çevrimdışı paket sürümü ve hazır olma durumu
- Geometri ve kanıt parmak izleri

Araç ölçüsü, ana durak veya sert kısıt değişirse eski onay geçersizleşir. Sıradan trafik değişikliği onayı silmez; yeni rota önerisi oluşturur.

Gezi sahibi veya durak düzenleme yetkisi olan üye rota taslağı hazırlayabilir. Aktif sürüşü başlatacak sürücü, seçilen araç profilini ve kesin rotayı kendi cihazında onaylar. Uzaktan verilen planlama onayı sürücünün yerel güvenlik onayının yerine geçmez.

## 8. Rota motoru

### 8.1 Sert uygunluk kuralları

Motor önce şu rotaları eler:

- Yönlendirme zarfından alçak, dar, kısa veya düşük taşıma kapasiteli geçiş
- Aktif kapanma veya doğrulanmış yol yasağı
- Römork, araç sınıfı, ticari kullanım veya özel erişim yasağı
- Uygun olmayan düşük emisyon bölgesi
- İzin verilmeyen özel yol, yaya yolu veya araç geçişsiz bölüm
- Elektrikli araç için rezervin altına düşmeden erişilemeyen koridor
- Kullanıcının sert `kaçın` seçeneğiyle çelişen feribot, araç treni veya asfaltsız yol

Kaynaklar çelişirse daha kısıtlayıcı ve daha güncel resmi kayıt uygulanır. Yalnız topluluk kaydı sert eleme yapmaz; ikinci kanıt veya kullanıcı uyarısı üretir.

### 8.2 Bölümleme ve kanıt birleştirme

Adaylar yol kimliği değişimlerinde ve en geç 250–500 metrede bir bölünür. Her bölümde yol sınıfı, fiziksel özellik, kısıt, canlı olay, hava ve kaynak güveni tutulur. Bölüm, yalnızca mevcut alanlarla değerlendirilir; bilinmeyen alanlar güvenilirlik sonucunu düşürür.

Kaynak uyumu yalnız çizgi yakınlığıyla ölçülmez. Yol numarası, yön, giriş-çıkış sırası, ülke ve yol sınıfı da eşleşmeye katılır. Böylece paralel servis yolu ana otoyolla aynı sayılmaz.

### 8.3 Ayrı sonuçlar

Motor tek ve açıklanamaz bir puan göstermez:

- **Güvenlik:** Araç uygunluğu, yol niteliği, olay, hava ve sürüş yükü
- **Güvenilirlik:** Kaynak uyumu, özellik kapsamı, güncellik ve sağlayıcı sağlığı
- **Konfor:** Otoyol/bölünmüş yol oranı, yüzey, eğim, viraj, şehir içi ve manevra yükü
- **Maliyet:** Süre, yakıt/elektrik, geçiş, vinyet ve planlanan molalar

Sıralama sözlüksel ilerler: sert uygunluk, asgari güvenilirlik, süre penceresi, sürüş karakteri hedefi. Bu düzen güvenliği maliyetle takas eden tek ağırlıklı toplamı engeller.

### 8.4 Yüzde 15 kuralı

Referans, bütün sert kuralları geçen en hızlı rotadır. Motor, referans süresinin yüzde 115'i içindeki adaylar arasından sürüş karakterine en uygun rotayı seçer.

Pencerenin dışındaki bir rota, anlamlı bir güvenlik veya doğrulama üstünlüğü taşıyorsa `Daha güvenli alternatif` olarak görünür. Sistem farkı dakika, kilometre ve somut gerekçeyle açıklar.

### 8.5 Sürüş karakterleri

#### Dengeli

Sert uygunluktan sonra güvenlik ve güvenilirliği en üstte tutar. Süre ve maliyet, yakın sonuçlarda belirleyici olur.

#### Otoyol

Yüzde 15 penceresinde mümkün olan en yüksek otoyol ve bölünmüş yol oranını seçer. Başlangıç, varış, mola, yakıt ve şarj bağlantıları için gereken en kısa güvenli yerel yola izin verir. Sonuç `yüzde otoyol` ve `bağlantı yolu kilometresi` verir.

#### Rahat

Dar yol, bozuk yüzey, sık keskin dönüş, dik eğim, yoğun şehir merkezi, karmaşık kavşak ve kuvvetli yan rüzgâra açık bölüm cezalarını artırır. Karavan çekişinde varsayılan öneri bu olabilir; kullanıcı tercihi korunur.

#### Ekonomik

Yakıt/elektrik, ücretli yol, vinyet ve süreyi birlikte azaltır. Sert uygunluk ile asgari güvenilirlik değişmez.

### 8.6 İnce ayarlar

Arayüz yalnız seçili araç ve rota için anlamlı seçenekleri gösterir:

- Ücretli yol ve vinyet
- Feribot ve araç treni
- Tünel
- Düşük emisyon bölgesi
- Bozuk veya asfaltsız yol
- Dar yol, dik eğim ve keskin dönüş hassasiyeti
- Yan rüzgâra açık köprü ve yol hassasiyeti
- Gece ana/aydınlatılmış yol önceliği
- Kesintisiz sürüş süresi ve güvenli mola aralığı
- Minimum yakıt veya şarj rezervi
- EV/PHEV soket, güç ve istasyon güvenilirliği
- Karavanla güvenli azami hız
- Sınır kapısı bekleme süresi

## 9. Tüketim ve menzil

`ConsumptionEstimator` tek nokta yerine aralık üretir. Başlangıçta kullanıcı ortalamasını veya doğrulanmış üretici değerini kullanır. Şu girdiler tahmini düzeltir:

- Yol sınıfı ve hedef hız
- Canlı ve tarihsel trafik
- Yükselme ve iniş
- Hava sıcaklığı, yağış ve karşı/yan rüzgâr
- Römork/karavan ve yüklü ağırlık
- Klima ve yardımcı enerji
- Kullanıcının gerçekleşen yolculukları

Dizel, benzin ve LPG/CNG sonuçları litre ve maliyet aralığı verir. Hibrit, yakıt tüketimi üzerinden çalışır. Plug-in hibrit, batarya ve yakıt bölümlerini ayrı hesaplar. Elektrikli araç, kullanılabilir batarya ile minimum varış rezervini uygular; uygun şarj duraklarını rota içine ekler.

Kullanıcı yakıt veya şarj sonrası gerçek miktarı kaydederse uygulama araç, römork durumu, hız ve hava sınıfına göre hareketli bir tüketim modeli öğrenir. En az üç uygun kayıt oluşmadan öğrenilen değer varsayılanı değiştirmez. Kullanıcı öğrenmeyi kapatabilir ve değeri sıfırlayabilir.

## 10. Arayüz

### 10.1 Planlama

Ana yüzey başlangıç, hedef, ara duraklar, seçili araç ve dört sürüş karakterini gösterir. `İnce ayar` kapalı başlar. Araç profilindeki kritik ölçüler doğrulanmamışsa rota hesaplanabilir; onay düğmesi doğrulama tamamlanana kadar `Ölçüleri doğrula` olur.

Hesaplama ilerlemesi sağlayıcı adlarını sıralayan teknik bir ekran göstermez. Arayüz `Rotalar karşılaştırılıyor`, `Araç uygunluğu kontrol ediliyor` ve `Çevrimdışı paket hazırlanıyor` gibi üç anlamlı durumu gösterir.

### 10.2 Onay

Onay yüzeyi tek öneriyle açılır:

```text
En iyi rota
8 sa 42 dk · 734 km
En hızlı uygun rotadan +12 dk
%91 otoyol · 58–64 L · €24 geçiş

Dar şehir yollarını ve iki düşük güvenli bölümü atlıyor.
```

Ana eylem `Onayla ve indir`, ikincil eylem `Alternatifleri gör` olur. Ayrıntı; kaynak uyumunu, veri zamanlarını, riskli bölümleri, bağlantı yolu kilometresini ve paket boyutunu gösterir. Sağlayıcı pazarlama adları ana kararı gölgelemez.

### 10.3 Sürüş

Sürüş yüzeyi yalnız sonraki manevra, şerit, kalan süre/mesafe, hız, hız sınırı ve tek etkin güvenlik uyarısını öne çıkarır. Kaynak puanları sürüş sırasında gizlenir. Kritik olmayan kontroller büyük ve az sayıdadır.

Normal trafik önerisi, süre farkını ve gerekçeyi gösterir; sürücü dokunarak veya güvenli sesli onayla kabul eder. Doğrulanmış kapanma ya da mevcut araçla yasal olmayan bölüm otomatik güvenli yeniden rota başlatabilir. Uygulama değişikliği sesli açıklar ve olay kaydına yazar.

### 10.4 Apple Maps

`Apple Maps'te aç` plan ayrıntısında ve navigasyon menüsünde kalır. Bu eylem, onaylanan Kuzey rotasının Apple tarafından birebir korunacağını iddia etmez; Apple hedefi kendi kurallarıyla yeniden hesaplayabilir. Arayüz bu farkı kısa bir notla belirtir.

## 11. Çevrimdışı yolculuk paketi

### 11.1 İçerik

`Onayla ve indir` şu verileri tek paket olarak yönetir:

- Onaylanan rota, alternatif güvenli dönüş noktaları ve manevralar
- HERE harita, çizim, çevrimdışı rota ve araç kısıtı katmanları
- Rota çevresinde 30 kilometrelik ön getirme koridoru
- Koridoru güvenilir çevrimdışı rota için örten en küçük HERE bölge birleşimi
- Durak şehirleri, kamp, yakıt, şarj, güvenli mola ve acil durak özeti
- Hız sınırı, tünel, köprü, ücret, vinyet ve sınır özeti
- Son hava ve kapanma anlık görüntüsü; zamanı açıkça işaretlenir
- Türkçe manevra ve kritik uyarı metinleri

HERE, keyfi 30 kilometrelik alanı kalıcı bölge olarak kurmaya izin vermediğinde paket yöneticisi iki katman kullanır: rota ön getirmesi geçici kopmaları karşılar; indirilen resmi HERE bölgeleri çevrimdışı rota garantisini sağlar. Arayüz gerçek indirme boyutunu onaydan önce gösterir.

### 11.2 İndirme davranışı

- Varsayılan indirme Wi-Fi üzerinden yapılır.
- Kullanıcı hücresel indirmeye açıkça izin verebilir.
- Güncelleme yalnız değişen paket ve uygulama verisini indirir; HERE bölge farkları SDK davranışına göre uygulanır.
- Paket imza, sürüm, boyut, son güncelleme ve bütünlük özeti taşır.
- İndirme kesilirse kaldığı yerden sürer.
- Depolama yetersizse gereken alan ve temizlenebilir eski paketler gösterilir.
- Kullanıcı rota ülkelerini veya bölgelerini elle indirebilir.

### 11.3 Çevrimdışı yeniden rota

Çevrimdışı HERE motoru, kurulu bölgelerde araç zarfını kullanarak yeniden rota üretir. Gerekli bölge eksikse uygulama bilinmeyen yola kestirme yapmaz. Onaylanan rotayı korur, kullanıcıyı son doğrulanmış koridora geri yönlendirir ve kısıtlı çalışma durumunu gösterir.

Canlı trafik, kapanma, hava ve şarj durumu bağlantısızken eskir. Arayüz bu verilerin zamanını gösterir; eski veriyi canlı gibi sunmaz.

## 12. Yeniden rota politikası

Yeniden değerlendirme şu olaylarda başlar:

- Kullanıcının rota yenilemesi
- Kalkış öncesi tazeleme
- Rotadan anlamlı ve kalıcı sapma
- Birincil sağlayıcının kapanma veya araç kısıtı uyarısı
- Yol boyunca kritik resmi olay
- Menzil veya minimum rezervin tehlikeye girmesi

Küçük GPS sıçraması yeniden rota üretmez. Mevcut 700 metre/45 saniye koruması başlangıç davranışı olarak korunur; gerçek sürüş simülasyonu eşikleri kalibre eder. Tam sağlayıcı karşılaştırması için en az beş dakikalık bekleme uygulanır. Trafik özeti, sağlayıcının ucuz yenileme yöntemiyle daha sık güncellenebilir.

Şu değişiklikler otomatik uygulanabilir:

- Doğrulanmış kapanmış yolu terk etme
- Araç zarfıyla uyumsuz kısıttan kaçınma
- Ulaşılamaz menzil durumunda güvenli yakıt/şarj durağı ekleme

Diğer değişiklikler sürücü onayı ister. Otomatik değişiklik de sesli gerekçe, eski-yeni fark ve denetlenebilir olay kaydı üretir.

## 13. Maliyet denetimi

1. Plan parmak izi aynı sonuçları yeniden kullanır.
2. Geometri, trafik, hava ve kapanma için ayrı yaşam süreleri uygulanır.
3. Sağlayıcı çağrıları iptal edilebilir ve zaman aşımına sahiptir.
4. Bir planlama eylemi sağlayıcı başına sınırlı aday ister; sonsuz alternatif aramaz.
5. Aylık ve günlük sert kullanım tavanları sunucuda tutulur.
6. Kullanım yüzde 70, 90 ve 100'e ulaştığında yönetici uyarısı üretir.
7. Kota bitince ücretli çağrı sessizce devam etmez; uygun önbellek, Apple/HERE cihaz sonucu veya açık motor kullanılır.
8. Sağlayıcı devre kesici, art arda hatalarda çağrıları geçici durdurur.
9. Telemetri, konum geçmişini saklamadan çağrı sayısını, önbellek isabetini, gecikmeyi ve hata türünü ölçer.
10. Sunucu, dış rota ve navigasyon hizmetleri için aylık 50 avroluk toplam sert tavan uygular. Yönetici bu değeri düşürebilir; istemci yükseltemez.

TomTom'un güncel ücretsiz kotası düşük hacimli ilk kullanım için yeterli görünür. Kota ve fiyatlar sözleşme sırasında yeniden doğrulanır; kodda sabit ticari varsayım bulunmaz. HERE Navigate teklifi ürün bütçe tavanını aşarsa `NavigationProvider` arayüzü açık kaynak harita/navigasyon yedeğine geçişi mümkün kılar. Bu geçişin kalite farkı kullanıcıdan saklanmaz.

## 14. Güven, gizlilik ve lisans

- TomTom ve açık sağlayıcı anahtarları yalnız sunucuda bulunur.
- HERE kimlik bilgileri imzalı uygulama yapılandırmasından gelir; depoya yazılmaz.
- Her uç nokta mevcut hesap, gezi üyeliği ve rol denetimini uygular.
- Konum ve rota verisi yalnız planlama, navigasyon ve kullanıcının mevcut paylaşım seçeneği için kullanılır.
- Ham konum geçmişi rota puanlama telemetrisine girmez.
- Sağlayıcı lisansları, geometri saklama, türetilmiş veri, kaynak gösterimi, çevrimdışı süre ve sağlayıcılar arası kullanım açısından uygulama öncesi incelenir.
- `ProviderCapabilities` modeli `allowsPersistence`, `allowsServerTransfer`, `requiresAttribution` ve `maxCacheAge` kurallarını kod seviyesinde uygular.
- Kullanıcıya `Bu rota yardımcı bir güvenlik aracıdır; işaretler ve yerel kurallar önceliklidir` uyarısı ilk kullanımda ve kritik belirsizlikte gösterilir.

## 15. Hata davranışı

### 15.1 Güven düzeyleri

- **Yüksek güven:** Birincil araç kısıtı kaynağı ve en az bir bağımsız koridor kaynağı uyumlu; canlı veriler güncel.
- **Doğrulandı:** Birincil kısıt verisi geçerli; bağımsız kaynağın kapsamı kısmi veya canlı veri eskimeye yakın.
- **Sınırlı doğrulama:** Tek rota kaynağı, eksik yol özelliği veya eski canlı veri var.
- **Çevrimdışı kayıt:** Son onaylanan paket kullanılıyor; canlı durum bilinmiyor.

Sınırlı doğrulama, kullanıcının açık onayını ister. Kritik ölçüsü doğrulanmamış araç hiçbir düzeyde `araç için doğrulandı` sayılmaz.

### 15.2 Sağlayıcı hataları

- Bir sağlayıcı başarısızsa kalan sonuçlar tamamlanır; ekran sonsuza kadar beklemez.
- HERE son rota üretemezse sistem TomTom geometrisini HERE navigasyonuymuş gibi göstermez.
- Apple sonucu yoksa yer araması ve rota kıyaslaması ayrı ayrı çalışmaya devam eder.
- Uzak servis kullanılamazsa cihaz sonuçları ve çevrimdışı paket açık durum etiketiyle kullanılabilir.
- Hiç güvenli rota yoksa `rota bulunamadı` yerine hangi kuralın engellediği ve hangi profil bilgisinin kontrol edilmesi gerektiği açıklanır.

## 16. Yolculuk kalitesini artıran öneriler

İlk sürüm rota çekirdeğini kurar. Aynı veri modeli şu önerileri güvenli biçimde ekler:

1. **En iyi kalkış saati:** Trafik, sınır, hava ve gün ışığına göre birkaç saatlik kalkış seçeneklerini kıyaslar.
2. **Karavan rüzgâr koruması:** Açık köprü ve yüksek viyadüklerde yan rüzgâr riskini öne çıkarır; gerekirse bekleme veya güvenli durak önerir.
3. **Eğim ve fren planı:** Uzun inişleri önceden bildirir; daha yumuşak koridoru karşılaştırır.
4. **Güvenli mola zinciri:** İki saatlik sürüş aralığı, karavan park alanı, aydınlatma, tuvalet ve yakıt/şarj uygunluğunu birlikte değerlendirir.
5. **Sınır ve vinyet asistanı:** Rota seçimine göre gereken vinyetleri, geçerlilik tarihlerini, ödeme türlerini ve sınır beklemesini açıklar.
6. **Gece sürüş koruması:** Ana, bölünmüş ve aydınlatılmış yolu tercih eder; varışın karanlığa kalmasını gösterir.
7. **Menzil güven payı:** Rüzgâr veya trafik kötüleşirse bir sonraki güvenli yakıt/şarj durağını önceden değiştirir.
8. **Yoldan öğrenme:** Gerçekleşen tüketim ve kullanıcının açık yol kalitesi bildirimi gelecekteki tahmini iyileştirir; topluluk verisi tek başına sert kural olmaz.
9. **Aile rota kilidi:** Onaylanan rota ve güncelleme nedeni gezi üyeleriyle senkronize olur; bütün cihazlar aynı sürümü görür.
10. **Tek dokunuş acil durak:** Kritik hava, yorgunluk veya araç sorunu için rota üzerindeki en yakın güvenli geniş alanı seçer.

## 17. Test stratejisi

### 17.1 Saf mantık testleri

Geliştirme test güdümlü ilerler. Her davranış önce başarısız testle tanımlanır:

- Alçak köprü, dar yol, ağırlık, römork ve erişim sert elemeleri
- Bilinmeyen kısıtın güvenilirliği düşürmesi
- En hızlı uygun rota ve yüzde 15 penceresi
- Pencere dışındaki anlamlı güvenli alternatif
- Otoyol oranı ve zorunlu bağlantı yolu hesabı
- Kaynak çelişkisinde resmî/güncel verinin önceliği
- Araç profili değişince onayın geçersizleşmesi
- Yakıt, EV, hibrit ve PHEV tüketim aralığı
- Maliyet kotası, önbellek ve devre kesici

Testler saat, hava ve sağlayıcı yanıtını sabit fikstürlerle deterministik yapar.

### 17.2 Sağlayıcı sözleşme testleri

Her bağdaştırıcı kaydedilmiş ve kimliksizleştirilmiş sağlayıcı yanıtlarıyla sınanır. Şema değişikliği, eksik alan, oran sınırlaması, zaman aşımı ve lisans saklama süresi ayrı test edilir. Canlı testler yalnız açık bir entegrasyon komutuyla çalışır; normal test paketi ücretli API çağırmaz.

### 17.3 Altın rota senaryoları

İstanbul–Riga koridoru için en az şu senaryolar korunur:

- Passat + Adria profiliyle otoyol önceliği
- 2,8 metrelik geçiş kısıtı
- Kapalı otoyol ve güvenli sapma
- Kaynakların farklı rota vermesi
- Sınır ve feribot tercihi
- Kuvvetli yan rüzgâr
- EV şarj boşluğu
- Tam çevrimdışı sapma
- Eksik çevrimdışı bölge
- Sağlayıcı kotası dolu çalışma

### 17.4 iOS ve sürüş doğrulaması

- SwiftUI durum, erişilebilirlik, Dynamic Type ve VoiceOver testleri
- Konum simülasyonuyla manevra, tünel, sapma ve yeniden rota
- Uçak modunda harita, ses, manevra ve çevrimdışı rota
- İndirme kesme, devam, bozuk paket ve yetersiz depolama
- Arka plan/ön plan, düşük güç ve termal durum
- Onay ekranında doğru `+dakika`, `+km`, tüketim ve otoyol oranı
- Güvenli sesli onay ve sürüş sırasında dokunma yükü

Gerçek cihaz ve kontrollü yol testi tamamlanmadan güvenlik iddiası yayımlanmaz.

### 17.5 Sunucu doğrulaması

- Kimlik doğrulama, gezi üyeliği ve rol
- İstek doğrulama ve koordinat sınırları
- Sağlayıcı anahtarlarının istemciye sızmaması
- Önbellek parmak izi ve kullanıcılar arası veri ayrımı
- Kota aşımları ve sağlayıcı kesintileri
- Astro build, type check ve lint

## 18. Uygulama aşamaları

Kapsam beş bağımsız teslimata ayrılır. Her teslimat, çalışan ürünü korur ve özellik bayrağı arkasında açılır.

### Aşama 0 — Lisans ve teknik ispat

- HERE Navigate ticari teklif ve sözleşme sınırları
- TomTom, Apple ve açık veri kullanım koşulları
- HERE offline `truck` katmanı, ülke/bölge boyutu ve iOS paket ispatı
- Sağlayıcı arayüzleri ve tek kısa deneme rotası

Çıkış ölçütü: Son geometri, çevrimdışı rota ve saklama kuralları kanıtlanır; toplam yinelenen dış hizmet maliyeti aylık 50 avroluk tavanı geçmez.

### Aşama 1 — Araç garajı ve saf rota motoru

- `VehicleProfile`, yönlendirme zarfı ve Passat + Adria başlangıç profili
- Ortak aday/kanıt modelleri
- Sert kurallar, yüzde 15 seçimi ve dört sürüş karakteri
- Tüketim aralığı
- Tam saf mantık test paketi

Çıkış ölçütü: Fikstür adayları doğru ve açıklanabilir sonucu verir.

### Aşama 2 — Çoklu kaynaklı planlama ve onay

- Apple, HERE, TomTom ve açık rota bağdaştırıcıları
- Astro karşılaştırma API'si, önbellek ve kota
- Minimal planlama, alternatif ve onay yüzeyleri
- Onaylanan rota sürümü ve gezi senkronu

Çıkış ölçütü: Gerçek İstanbul–Riga adayları kıyaslanır; kullanıcı farkı görüp rotayı onaylar.

### Aşama 3 — HERE uygulama içi navigasyon ve çevrimdışı paket

- HERE harita ve `NavigationCoordinator`
- Sesli manevra, sapma ve güvenli yeniden rota
- Çevrimdışı bölge/koridor indirme, bütünlük ve depolama yönetimi
- Apple Maps'e geçiş

Çıkış ölçütü: Uçak modunda indirilen koridorda navigasyon ve araç uyumlu yeniden rota çalışır.

### Aşama 4 — Canlı güvenlik ve enerji

- Resmi kapanma/çalışma kayıtları
- Yan rüzgâr, yağış ve görüş etkisi
- EV/PHEV şarj ve minimum rezerv
- Güvenli mola, sınır ve vinyet

Çıkış ölçütü: Canlı olay öneriyi açıklanabilir biçimde değiştirir; maliyet kotası aşılmaz.

### Aşama 5 — Kalibrasyon ve yol testi

- Gerçek tüketim öğrenmesi
- Rota sonuç ve API maliyet telemetrisi
- Kontrollü karavan yol testleri
- Eşik, metin ve sürüş etkileşimi ayarı

Çıkış ölçütü: Yol testi raporu açık kritik sorun bırakmaz.

## 19. Kabul ölçütleri

- Kullanıcı en az iki araç profili oluşturabilir ve rota başına profil seçebilir.
- Passat + Adria profilinin kritik ölçüleri onaydan önce doğrulanır.
- Dört sürüş karakteri farklı ve açıklanabilir sonuç üretir.
- Apple, HERE ve TomTom katkısı kaynak özetinde görünür; Apple Maps'e geçiş çalışır.
- Sert kısıta aykırı aday seçilmez.
- Varsayılan öneri yüzde 15 kuralını uygular.
- Otoyol modu otoyol oranını ve bağlantı yolunu gösterir.
- Onay ekranı süre/mesafe farkı, tüketim, ücret ve üç gerekçe verir.
- Onay olmadan rota aktifleşmez veya geziye yazılmaz.
- Onaylanan rota sürümlenir ve üyelerle yetkiye uygun senkronlanır.
- Çevrimdışı paket gerekli araç kısıtı ve rota katmanlarını doğrular.
- Uçak modunda rota, manevra, ses ve desteklenen bölgede yeniden rota çalışır.
- Normal yeniden rota kullanıcı onayı ister; kritik sert kural ihlali güvenli otomatik rota üretebilir.
- Kota bittiğinde maliyet artmaz; uygulama açık bir düşük güven durumuna geçer.
- Önbellekteki plan 500 milisaniye içinde açılır; normal bağlantıda ilk uygun aday beş saniye, tam karşılaştırma on iki saniye içinde hedeflenir.
- Dış rota ve navigasyon hizmetleri mevcut kullanım ölçeğinde aylık 50 avroluk sert tavanı aşmaz.
- Build, type check, lint, saf mantık, sağlayıcı sözleşme ve iOS simülasyon testleri geçer.

## 20. Kaynaklar

- [HERE iOS çevrimdışı rota](https://docs.here.com/here-sdk/docs/ios-offline-maps-routing)
- [HERE iOS kamyon navigasyonu ve araç kısıtları](https://docs.here.com/here-sdk/docs/ios-navigation-truck)
- [HERE iOS rota seçenekleri](https://docs.here.com/here-sdk/docs/ios-routing-options)
- [HERE SDK iOS başlangıç ve Navigate lisansı](https://docs.here.com/here-sdk/docs/ios-get-started)
- [HERE SDK iOS Navigate değişiklik günlüğü](https://docs.here.com/here-sdk/changelog/here-sdk-ios-navigate-prod)
- [TomTom rota hesaplama](https://developer.tomtom.com/routing-api/documentation/tomtom-maps/v1/calculate-route)
- [TomTom ortak rota ve araç parametreleri](https://developer.tomtom.com/routing-api/documentation/tomtom-maps/v1/common-routing-parameters)
- [TomTom güncel fiyatlandırma](https://docs.tomtom.com/pricing)
- [GraphHopper özel model yol sınıfları ve ölçü alanları](https://docs.graphhopper.com/openapi/custom-model/conditional-multiplication)
- [Astro dosya tabanlı ve isteğe bağlı rota düzeni](https://docs.astro.build/en/guides/routing/)
