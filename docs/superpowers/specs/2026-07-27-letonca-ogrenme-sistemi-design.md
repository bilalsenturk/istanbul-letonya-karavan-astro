# Letonca Öğrenme Sistemi — Tasarım

Tarih: 2026-07-27
Durum: onaylandı, uygulama planı bekliyor

## Amaç

Uygulamadaki Letonca modülünü, harf çalıştıran 12 elemanlı sabit bir listeden, kelime ve cümle
öğreten, unutmayı ölçen ve gerçekten öğrenene kadar bırakmayan bir sisteme dönüştürmek.
Duolingo'nun oyun hissi ve efekt kalitesi hedefleniyor; kopyası değil.

## Mevcut durumun sorunları

Ses bazı sorularda hiç çalmıyor. Üç ayrı sebep:

1. `LatvianLearningModels.swift:216` — `audioText = targetText ?? target`. `fill_blank`,
   `produce_sentence`, `match_pairs`, `short_answer`, `guided_write` payload'larında `target`
   alanı yok, dolayısıyla `nil` dönüyor ve `LatvianLearningAudioPlayer.play` guard'da sessizce
   çıkıyor. Buton görünür, basılır, hiçbir şey olmaz, hata da gösterilmez.
2. `src/learning-os/content-engine/latvian-pipeline.ts:189` — `audioTextForItem` yalnızca dört
   tür için metin döndürüyor; kalan türlere `audioUrl` hiç eklenmiyor.
3. Canlı TTS yolu kırılgan. `openai/gpt-audio-mini` chat-completions üzerinden "şunu seslendir"
   diye prompt'lanıyor; model bazen konuşmak yerine metin döndürüyor, ses parçası gelmiyor,
   endpoint 502 JSON dönüyor, `AVPlayer` o JSON'u çalamayıp sessizce ölüyor. Cache yok, her
   dinleme yeniden üretim. Ayrıca `.env` ve `.env.local` dosyalarında `OPENROUTER_API_KEY`
   tanımlı değil, yani lokal sunucuda endpoint her zaman 503 dönüyor.

İçerik tarafında paket toplam 12 elemanlı ve elle yazılmış — her soru türü için tek örnek.
Havuz bitince `pickLearningItem` aynı 12 şeyi döndürüyor. Hakimiyet ölçümü yok, tekrar planı
yok, unutma takibi yok. `phoneme_choose` türü harf odaklı; istenen kelime odaklı öğrenim.

## Araştırma bulguları

Açık kaynak Duolingo klonlarının hiçbirinde gerçek alıştırma taksonomisi veya aralıklı tekrar
yok; hepsi doğrusal ders + can modeli, çoğu aynı tutorial'ın lisanssız fork'u. Kullanılabilir
olanlar:

- [bryanjenningz/react-duolingo](https://github.com/bryanjenningz/react-duolingo) (465★, MIT) —
  XP/seri/can/gem state modeli için referans. Kod değil, model kopyalanacak.
- [sanidhyy/duolingo-clone](https://github.com/sanidhyy/duolingo-clone) (607★, MIT) — içerik
  şeması şekli için referans.
- [open-spaced-repetition/swift-fsrs](https://github.com/open-spaced-repetition/swift-fsrs)
  (MIT, SPM) — cihaz üstü tekrar planlaması. Doğrudan kullanılacak.
- [hermitdave/FrequencyWords](https://github.com/hermitdave/FrequencyWords) (MIT) — Letonca
  frekans listesi, müfredat denetimi için.
- [LUMII-AILab/Tezaurs](https://github.com/LUMII-AILab/Tezaurs) — Letonca çekim verisi. Lisansı
  belirsiz; üretim betiğinde kullanılacaksa önce doğrulanmalı, aksi halde çekimler üretim
  sırasında denetim modeline doğrulatılır.
- [simibac/ConfettiSwiftUI](https://github.com/simibac/ConfettiSwiftUI) (MIT),
  [airbnb/lottie-ios](https://github.com/airbnb/lottie-ios) (Apache-2.0) — kutlama efektleri.
- Kenney.nl CC0 arayüz ses paketleri — efekt sesleri. Duolingo'nun kendi sesleri telifli,
  kullanılmayacak.

TTS: OpenRouter'ın `/api/v1/audio/speech` listesinde OpenAI yok, ama `openai/gpt-audio-mini`
chat-completions üzerinden ses çıkışı veriyor (giriş $0.60/1M, ses çıkışı $2.40/1M token).
Bu model kullanılacak. Letonca kalitesi ilk üretim partisinde dinlenerek doğrulanacak; kabul
edilemezse üretim betiğinde sağlayıcı değiştirilebilir (paket formatı sağlayıcıdan bağımsız).

## Mimari

Üç katman, aralarındaki sınırlar net.

**Uygulama çalışırken hiçbir sunucuya bağlanmaz.** Ders içeriği, soru üretimi, notlama, FSRS,
XP/can/seri, maskot — hepsi cihazda. Tek istisna ilk açılıştaki ses indirmesi.

**İçerik üretim betiği (`tools/`, tek seferlik, elle çalıştırılır).** OpenRouter'a giden tek
şey bu. Sahne planından yola çıkıp kelime, cümle ve meta veriyi üretir; frekans süzgecinden
geçirir; ikinci bir modele denetletir; `openai/gpt-audio-mini` ile her Letonca metnin sesini
bir kez üretir. Çıktısı bir içerik paketi JSON'u ve bir ses dosyası klasörü. Astro ile ilgisi
yok, uygulama derlemesine dahil değil.

**Ses dağıtımı (Vercel Blob).** Ses dosyaları Blob'a yüklenir. Uygulama ilk açılışta bir kez
indirir, cihaza yazar, sonra internete ihtiyaç duymaz. İndirme kesintiye uğrarsa kaldığı
yerden devam eder.

`src/learning-os/` ve `src/pages/api/learning-os/` uygulamanın yolundan çıkar; seçim ve notlama
mantığı Swift'e taşınır, üretim mantığı `tools/` altına gider. `LatvianLearningAudioPlayer`'ın
canlı TTS çağrısı tamamen kalkar — ses her zaman yerelden çalar. Başarısız olabilecek bir ağ
çağrısı kalmadığı için "bazen çalışmıyor" sorunu kökten biter.

## İçerik planı

12 sahne, sırayla açılır, her biri yaklaşık 25 kelime ve 20 kalıp cümle. Toplam ~300 kelime,
~240 cümle.

| # | Sahne | Kapsam |
|---|---|---|
| 1 | Tanışma | sveiki, labdien, mani sauc, es esmu, paldies, lūdzu, jā/nē |
| 2 | Sayılar ve fiyat | 0-100, cik maksā, eiro, dārgi/lēti |
| 3 | Markette | maize, ūdens, piens, kafija, gribu, man vajag |
| 4 | Benzinlik ve yol | degviela, pilnu bāku, kur ir, pa kreisi/pa labi, taisni |
| 5 | Kamp alanı | telts, vieta, nakts, cik ilgi, vai ir brīvs |
| 6 | Yemek | ēst, dzert, garšīgs, rēķinu lūdzu, bez gaļas |
| 7 | Zaman | šodien, rīt, pulksten, no...līdz, cikos |
| 8 | Hava ve yol durumu | lietus, sniegs, auksts, ceļš, slidens |
| 9 | Sınır ve belgeler | pase, dokumenti, mašīna, no Turcijas |
| 10 | Yardım ve acil | palīdziet, ārsts, slimnīca, man sāp, policija |
| 11 | Sohbet | kā tev iet, no kurienes, cik ilgi, patīk |
| 12 | Kibarlık ve veda | atvainojiet, uz redzēšanos, ar prieku, nekas |

Sıra yolculuğun kendi sırasıyla örtüşüyor: 1-3 hemen kullanılır, 4-6 günlük ihtiyaç, 7-9
pratik, 10 güvenlik, 11-12 sosyal.

**Frekans denetimi.** Her kelime FrequencyWords Letonca listesine karşı kontrol edilir. İlk
5000'de olmayan kelime pakete girmez; üretim betiği onu eler ve daha sık kullanılan eşdeğerini
ister. Bu, üretim modelinin kitabi veya uydurma kelime sokmasını engeller.

**İşlev kelimeleri.** `ir, nav, un, bet, ar, uz, man, tev, šis, tas` gibi omurga kelimeler ayrı
ders olarak verilmez; cümlelerin içinde tekrar tekrar geçer ve kendi FSRS kaydını tutar.

**Haller.** Hal tablosu asla gösterilmez. Aynı kelime farklı sahnelerde farklı halde geçer
(`kafija` yalın → `ar kafiju` araçlı → `bez kafijas` ilgi). Kalıp oturduktan sonra hal
tatbikatı sorusu devreye girer. Kural öğretilmez, örüntü oturtulur.

**Üretim ve doğrulama.** Betik her sahne için kelime, Türkçe karşılık, örnek cümleler ve her
cümlenin hangi soru tiplerine uygun olduğunu ister. Ardından ayrı bir model ilk çıktıyı
denetler: Letonca doğruluğu, Türkçe karşılık doğruluğu, hal çekimi, sahne kapsamı dışına
taşma. Denetimi geçemeyen madde pakete girmez, yeniden üretilir.

## Soru tipleri

11 tip. Her biri kelimenin farklı bir yönünü sınar; bu ayrım FSRS için gerekli, çünkü tanıma
ve üretim ayrı becerilerdir.

| Tip | Ne sorar | Modalite |
|---|---|---|
| Dinle-seç | ses çalar, üç Letonca kelimeden doğrusu | dinleme |
| Görselden seç | ikon gösterir, Letoncasını sorar | tanıma |
| LV→TR | Letonca cümle, Türkçesini kelime bankasından kur | okuma |
| TR→LV | Türkçe cümle, Letoncasını kelime bankasından kur | üretim |
| Eşleştirme | dört LV + dört TR, dokunarak eşle | tanıma |
| Boşluk doldurma | cümlede eksik kelime, üç seçenek | okuma |
| Hal tatbikatı | `ar kafij__` → `-u / -a / -as` | dilbilgisi |
| Dikte | ses çalar, klavyeyle yaz | dinleme + yazım |
| Sıralama | karışık kelimeleri cümleye diz | üretim |
| Telaffuz | dinle, tekrar et (cihaz konuşma tanıma) | konuşma |
| Hızlı tekrar | 60 saniye, sadece bilinen kelimeler | pekiştirme |

`phoneme_choose` kaldırılır. `concept` soru olmaktan çıkar, ders başı tanıtım kartına dönüşür.

## Ders kompozisyonu

Her ders 16 soru. Karışım her seferinde hesaplanır:

- **%50 yeni malzeme** — dersin öğrettiği kelimeler, kolaydan zora: önce dinle-seç ve
  eşleştirme, sonra boşluk doldurma, en sonda TR→LV ve dikte. Bir kelime ilk kez üretim
  sorusunda çıkmaz.
- **%30 FSRS kuyruğu** — unutulmak üzere olan eski kelimeler, ders içine gömülü.
- **%20 hata tekrarı** — son üç derste yanlış yapılan kelimeler, farklı bir soru tipiyle. Aynı
  soruyu tekrarlamak ezber yaratır; farklı tip gerçek öğrenmeyi ölçer.

Ardışık iki soru asla aynı tipte veya aynı kelime üzerine olmaz. Mevcut `selector.ts`'deki bu
kural Swift'e taşınır.

## Hakimiyet motoru

Zorlama iki noktada:

1. **Ders içinde** — yanlış cevaplanan soru dersin sonuna geri eklenir; ders o soru doğru
   cevaplanmadan bitmez.
2. **Sahne kilidi** — sonraki sahne, ders sayısı dolduğu için değil, sahnedeki kelimelerin en
   az %80'inin FSRS hatırlama olasılığı 0.9'un üstüne çıktığı için açılır. Eşik tutmuyorsa
   sistem yeni ders yerine o sahnenin tekrar dersini verir. İlerleme zamanla değil hafızayla
   ölçülür.

**Derecelendirme.** İlk denemede doğru ve hızlı → `easy`; ilk denemede doğru → `good`; ipucu
alındı veya yavaş → `hard`; yanlış → `again`. `swift-fsrs` bir sonraki tekrar tarihini
hesaplar.

**Çift kayıt.** Her kelimenin iki ayrı FSRS kaydı vardır: tanıma ve üretim. `paldies`'i duyunca
anlamak ile konuşurken çıkarabilmek aynı şey değildir. Sahne kilidi ikisine birden bakar.

**Canlar.** 5 can; yanlışta bir can gider, ders içinde dolmaz. Canlar biterse ders yarıda kalır
ve baştan başlanır, ama o derste toplanan FSRS verisi kaydedilir. Canlar 4 saatte bir dolar ya
da bir tekrar dersi oynanarak anında kazanılır — cezalandırmak yerine tekrara yönlendirir.

## Efektler ve gamification

**Cevap anı.** Doğruda: kart yeşile döner, hafifçe büyüyüp yerine oturur (spring, response 0.3,
damping 0.6), `.success` haptic, kısa ding, alttan yeşil panel, XP sayacı yukarı sayar.
Yanlışta: kart kırmızıya döner ve yatay iki kez sarsılır, `.error` haptic, boğuk buzz, bir kalp
kırılıp düşer, alttan kırmızı panel doğru cevapla birlikte girer. Panel butonuna basılmadan
sonraki soruya geçilmez.

**Kombo.** 3 doğruda kart kenarında parıltı; 5'te +5 bonus XP ve ses tonu bir perde yükselir;
10'da ekran kenarlarından ışık dalgası. Kombo kırılınca sessizce sıfırlanır, ceza yok.

**Maskot.** SwiftUI şekillerinden çizilmiş özgün karakter (harici asset veya paralı editör
gerektirmez). Beş durum, aralarında yaylı geçiş: `beklemede` (nefes alma, ara sıra göz kırpma),
`düşünüyor` (kullanıcı cevaplarken öne eğilme), `doğru` (zıplama, gülümseme), `yanlış` (kafa
sallama), `kutlama` (ders sonu). Karavan temasına oturan bir karakter; ilk çalışan halinde
kullanıcıya gösterilip onaylanacak.

**Ders sonu.** İlerleme çubuğu dolar, konfeti patlar, maskot kutlamaya geçer, üç sayaç sırayla
dolar: XP, doğruluk yüzdesi, seri günü. Seri uzadıysa Lottie alev animasyonu büyüyerek gelir.

**Kalıcı göstergeler.** Üst çubuk: seri, can, XP, günlük hedef halkası. Sahne haritası
İstanbul'dan Riga'ya uzanan bir rota üzerinde 12 durak; açılanlar renkli, kilitliler soluk,
maskot o anki durakta. Sahne bitince yol bir sonraki durağa uzar.

**Sesler.** Kenney.nl CC0 paketlerinden 8 efekt: doğru, yanlış, ders bitti, XP tık, can gitti,
seri uzadı, dokunuş, kombo. Ayarlarda "ses efektleri" ve "telaffuz sesi" ayrı ayrı kapatılır.

**Günlük hedef.** Günde 1 ders. Tamamlanınca üst çubuktaki halka dolar.

## Bildirimler

Günde en fazla 2, hepsi zamanlı ve yerel. Metinler maskotun ağzından, kısa.

- **Günlük hatırlatma** — son 7 günün en sık ders saatine göre kendini ayarlar. İlk hafta
  20:00, sonra alışkanlığa kayar.
- **Seri kurtarma** — gün bitmesine 3 saat kala o gün ders yapılmamışsa. Yalnızca aktif seri
  varken gönderilir.
- **Seri dönüm noktası** — 7, 30, 100 gün.
- **FSRS uyarısı** — sahne kelimelerinin hatırlama olasılığı eşiğin altına düşünce, haftada en
  fazla bir kez.

Ortak sessiz saat penceresine (23:00-08:00) uyar. Mevcut `NotificationBudget` sistemine kendi
kategorisiyle kaydolur, böylece sınır geçişi gibi kritik yolculuk bildirimleriyle çakışmaz.
Ayarlarda tek anahtarla tamamen kapatılır.

## Veri modeli

**İçerik paketi (JSON, uygulama paketine gömülü).** Metin içeriği küçüktür ve uygulamayla
birlikte gelir; yalnızca ses dosyaları ilk açılışta indirilir. `scenes[]` → her sahnede `words[]` (letonca, türkçe, hal bilgisi,
sesId) ve `sentences[]` (letonca, türkçe, sesId, uygun soru tipleri). Sorular pakette hazır
durmaz, cihazda üretilir — 300 kelime × 11 tip binlerce olası soru demek; paket küçük kalır.

**İlerleme dosyası (cihazda).** Her kelime için iki FSRS kaydı, sahne durumları, XP, seri, can,
hata geçmişi. Tek JSON dosyası, her ders sonunda yazılır. `UserDefaults` kullanılmaz.

## Dosya değişiklikleri

- `src/learning-os/` ve `src/pages/api/learning-os/` uygulamanın yolundan çıkar; üretim mantığı
  `tools/` altına taşınır.
- `ios/Karavan/Learning/` baştan yazılır: içerik paketi çözümleme, soru üretici, notlayıcı,
  FSRS köprüsü, ilerleme deposu, ses deposu — her biri ayrı dosya.
- `ios/Karavan/Views/Tools/LatvianLearningView.swift` (674 satır) parçalanır: her soru tipi
  kendi görünüm dosyasında, tek dev `switch` kalmaz. Ayrıca sahne haritası, ders akışı, ders
  sonu ekranı ve maskot ayrı dosyalar.
- SPM bağımlılıkları eklenir: `swift-fsrs`, `ConfettiSwiftUI`, `lottie-ios`.

## Hata yönetimi

- Ses inmemişse: o kelime için dinleme sorusu üretilmez, ders başka tip seçer.
- Paket bozuksa: son çalışan paket kullanılmaya devam eder.
- İlerleme dosyası bozulursa: yedekten döner; yedek de yoksa sıfırdan başlar ve kullanıcıya
  açıkça söylenir.
- Konuşma tanıma izni yoksa: telaffuz soruları üretilmez, ders eksilmez.
- Ses indirme kesilirse: kaldığı yerden devam eder, bu sırada ders oynanabilir.

## Test

`ios/Tests/` altındaki düz Swift betik yaklaşımı sürdürülür.

- FSRS derece eşlemesi (hız/ipucu/yanlış → easy/good/hard/again).
- Ders kompozisyon oranlarının gerçekten %50/%30/%20 tutması.
- Sahne kilidi eşiği: %80 kelime, 0.9 hatırlama olasılığı.
- Ardışık tekrar kuralı: iki soru üst üste aynı tip veya aynı kelime olmamalı.
- Notlama normalizasyonu: `ā` yerine `a` yazan kullanıcı yanlış sayılmamalı; Türkçe tarafta
  büyük/küçük harf ve `ı/i` farkı tolere edilmeli.
- Üretim betiği tarafında: frekans süzgeci ve denetim geçişi.

## Kapsam dışı

- Rive maskot (paralı editör ve harici tasarım gerektirir; maskot SwiftUI ile çizilir).
- Liderlik tablosu, arkadaş, sosyal özellikler.
- A1 üstü seviyeler; bu tasarım temel Letonca ile sınırlı.
- FSRS parametre optimizasyonu (yeterli tekrar geçmişi biriktikten sonra değerlendirilir).
