# Günlük ve Bildirimler — Tasarım

**Tarih:** 20 Temmuz 2026
**Durum:** Onaylandı, uygulamaya hazır
**Kapsam:** Kişisel günlük (CloudKit) + bildirim genişletmesi

---

## Bağlam ve kapsam kararı

Kullanıcı dört şey istedi: bildirim genişletmesi, kişisel günlük, çok rotalı mimari,
ve rotaya kişi ekleme. Son ikisi uygulamanın temelini değiştiriyor — `trip-data.json`
tek yolculuk varsayımı, anonsların Riga duraklarına bağlı olması, `TripEdits`'in tek
takvimi düzenlemesi.

**Rota modeli yolculuktan sonraya ertelendi.** Kalkışa iki hafta kaldı (3 Ağustos
2026); çalışan bir uygulamayı yolculuktan hemen önce temelinden değiştirmek gereksiz
risk. Günlük ve bildirimler mevcut yapıya dokunmadan eklenebiliyor ve yolda işe
yarıyor. Rota mimarisi Ağustos sonunda ayrı bir spec olarak ele alınacak.

Bu spec yalnızca günlük ve bildirimleri kapsar.

---

## Karar verilen mimari (rota modeli dahil, ileriye dönük)

Üç katman, her birinin tek işi:

| Katman | İçerik | Neden |
|---|---|---|
| CloudKit özel DB | Günlük kayıtları, kişisel ayarlar | Herkesin kendi iCloud'u; bedava, sunucu yok, kimlik Apple'da |
| CloudKit paylaşılan DB (CKShare) | Rotalar ve üyelik — **bu spec'te YOK**, Ağustos'ta | Davet/kabul/çakışma Apple tarafında |
| Vercel Blob aynası | Canlı konum, plan, harcama toplamı, paylaşılan günlük kayıtları | Web sitesi canlı kalsın |

**Kural: CloudKit kaynak, Vercel ayna.** İki yönlü senkron kurulmaz — çakışma
yönetimi maliyeti faydasını aşar.

---

## 1. Günlük

### Veri modeli

CloudKit `JournalEntry` kaydı, kullanıcının **özel** veritabanında:

| Alan | Tip | Not |
|---|---|---|
| `id` | String | UUID |
| `text` | String | Kayıt metni |
| `createdAt` | Date | Oluşturma anı |
| `latitude` / `longitude` | Double? | O anki konum (varsa) |
| `stopId` | String? | O güne denk gelen durak |
| `mood` | String? | Ruh hali etiketi |
| `photoAssets` | [CKAsset] | Fotoğraflar |
| `isShared` | Bool | Rotaya paylaşıldı mı (varsayılan `false`) |

### Çevrimdışı öncelikli yazma

Her kayıt **önce cihaza** (`Documents/journal/*.json` + fotoğraflar), **sonra**
CloudKit'e gider. Sınırda sinyal gittiğinde kayıt kaybolmaz; bağlantı gelince
kuyruk boşalır.

Bu bir tercih değil zorunluluk: yolculuğun büyük kısmı sinyalin zayıf olduğu
sınır bölgelerinden ve ülkeler arası geçişlerden oluşuyor.

### Sesli yazdırma

`SFSpeechRecognizer(locale: "tr-TR")` — halihazırda `VoiceExpenseView`'da çalışıyor,
aynı motor yeniden kullanılır. Bas-konuş, metin alana düşer, kullanıcı düzeltir.

Sürerken tek elle kullanılabilir olmalı: büyük dokunma hedefi, tek dokunuşla
başlat/bitir, otomatik kaydetme.

### Fotoğraf

İki kaynak:
- **Kamera** — anlık çekim
- **Kütüphane** — seçicide o günün *konumlu* fotoğrafları önde

İkinci madde mevcut `PhotoJournalView` mantığını yeniden kullanır (tarih + konum
filtresi ile `PHAsset` taraması). O ekran bugün hiçbir şey saklamıyor, yalnızca
görüntüleyici; günlüğe besleyici olarak bağlanır, kaldırılmaz.

### Apple öneri seçicisi

`JournalingSuggestions` (iOS 17.2+) ile "bugün Sofya'daydın, 3 fotoğraf çektin,
240 km sürdün" önerileri içeri alınır. Ayrı ayrı izin istemeden çalışır — seçici
ayrı süreçte koşar, yalnızca kullanıcının seçtiği içerik app'e geçer.

**Önemli sınır:** Apple'ın Günlük uygulamasına **yazılamaz**. `JournalingSuggestions`
tek yönlüdür (öneri → üçüncü taraf app). Üçüncü taraf hiçbir uygulama Journal'a
giriş ekleyemez veya düzenleyemez. Bu yüzden günlük app içinde kurulur.

### Paylaşım

Her kayıt varsayılan **gizli**. Kayıt başına "paylaş" düğmesi. Rota modeli henüz
olmadığı için "paylaşmak" bu spec'te tek anlama gelir: **mevcut İstanbul→Riga
yolculuğu**. Paylaşılan kayıt mevcut Vercel Blob hattından (`x-live-secret`) geçip:
- app'teki ortak zaman çizgisinde
- web sitesinde

görünür. CloudKit paylaşımı (CKShare) bu spec'te **kurulmaz** — rota modeliyle
birlikte Ağustos'ta gelir.

Gerekçe: sonradan gizliye almak zor, baştan gizli olmak kolay. Herkesin okuduğunu
bilmek yazılanı değiştirir; Leyla'nın kendine saklayabildiği bir şey yazabilmesi
tasarımın amacı.

### Hata durumları

| Durum | Davranış |
|---|---|
| iCloud kapalı / oturum yok | Kayıt yalnızca cihazda; ayarlarda uyarı gösterilir |
| iCloud depolama dolu | Kayıt cihazda kalır, kuyrukta bekler, kullanıcıya bildirilir |
| İnternet yok | Kuyruk; bağlantı gelince otomatik gönderim |
| Fotoğraf izni reddedildi | Metin + ses çalışır, fotoğraf bölümü gizlenir |

---

## 2. Bildirimler

Hepsi **yerel bildirim** (`UNUserNotificationCenter`). Sunucu, push sertifikası
veya APNs yok — çevrimdışı çalışır.

### Zaten var (dokunulmaz)

Yağmur başladı/durdu, sert hava uyarısı (`WeatherService`), kalkış hatırlatmaları,
varış geofence'i, vinyet bitişi.

### Eklenecekler

**Yol**
- Sınır yaklaşımı: 30 km kala belge hatırlatması
- Uzun sürüş molası: 2 saat kesintisiz sürüşte
- Varışa 50 km kala: "kamp yerini ara" tetiği

**Para**
- Kur sıçraması: %3+ değişimde
- Ülke değişiminde dizel farkı: "Polonya'da dizel Litvanya'dan %12 ucuz, burada doldur"

**Pratik**
- Akşam: "bugünü günlüğe yaz" hatırlatması
- Ertesi gün özeti: mesafe, hava, sıradaki durak
- Şarj %20 altında ve navigasyon açıkken uyarı

### Bildirim disiplini

Anons motorundaki (`AnnouncementEngine`) kurallara benzer bir kısıtlama gerekir:
aynı kategoriden art arda bildirim gönderilmez, kritik olmayanlar sürüş sırasında
birikip mola anında toplu verilir. Yolculuk sekiz gün sürüyor; bildirim yorgunluğu
gerçek bir risk.

---

## Test yaklaşımı

| Alan | Nasıl doğrulanır |
|---|---|
| Çevrimdışı kuyruk | Uçak modunda kayıt → moddan çık → CloudKit'te göründüğü teyit edilir |
| Sesli yazdırma | Gerçek cihazda Türkçe dikte (simülatörde mikrofon davranışı farklı) |
| CloudKit yazma | Gerçek cihaz + gerçek iCloud hesabı; simülatörde iCloud oturumu gerekir |
| Bildirim tetikleri | Sahte konum/tarih enjeksiyonu ile tetik koşulları zorlanır |
| Paylaşım | Kayıt paylaş → web sitesinde göründüğü teyit edilir |

**Simülatör yetmez.** Bu projede iki hata yalnızca gerçek cihazda ortaya çıktı:
barometre izni eksikliği (simülatörde barometre yok, kod hiç çalışmıyordu) ve
kuş uçuşu mesafe hatası (simülatör konumu San Francisco olduğu için sayı zaten
anlamsızdı). CloudKit ve mikrofon aynı sınıfta — gerçek cihazda test edilmeli.

---

## Kapsam dışı (bilinçli)

- Çok rotalı mimari — Ağustos, ayrı spec
- CKShare ile rota paylaşımı — Ağustos, ayrı spec
- Apple Journal'a yazma — teknik olarak imkânsız, API yok
- Günlük kayıtlarının web'den düzenlenmesi — ayna tek yönlü kalır
- Push bildirimleri — yerel bildirim yeterli, sunucu maliyeti gereksiz
