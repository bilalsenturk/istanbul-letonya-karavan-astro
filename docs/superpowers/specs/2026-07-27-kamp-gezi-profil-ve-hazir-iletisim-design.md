# Kamp, Gezi, Profil ve Hazır İletişim Tasarımı

## Amaç

Kuzey, her geceleme durağı için yakın ve doğrulanmış kamp alternatifleri sunacak; kamp çevresindeki gezilecek yerleri kaynaklı görsellerle gösterecek; konaklama alanlarını rota ve hesap profilinden dolduracak; WhatsApp, Mesajlar ve E-posta uygulamalarını hazır alıcı ve metinle açacak.

Uygulama mesaj kutularına erişmeyecek. Gönderilen ve gelen mesajları Kuzey içinde göstermeyecek. Kullanıcı, iletişim durumunu elle yönetecek.

## Kapsam

İlk içerik paketi İstanbul–Riga yolculuğundaki altı geceleme durağını kapsar:

1. Sofya / Elin Pelin — Sunset Garden Camping
2. Novi Sad / Kovilj — Camping Campuccino
3. Budapeşte — Aréna Camping Budapest
4. Kraków — Camping Adam
5. Varşova — Camping Motel WOK
6. Riga — Camping & Yachts

Standart hesap rotaları da aynı veri modelini ve arayüzü kullanır. Küratörlü içerik bulunmayan standart rotalarda Apple Maps yakın araması çalışır.

## Mesafe Kuralları

Küratörlü kamp listesi şu sınırları uygular:

- Şehir gecelemelerinde kamp alternatifi hedef şehir merkezinin 25 km çevresinde kalır.
- Transit gecelemelerinde alternatif, planlanan güzergâhtan en fazla 10 km sapar.
- Mevcut altı geceleme şehir durağı sayılır. Sonradan eklenen ve yalnız yol üstü geceleme amacı taşıyan duraklar transit sayılır.
- Uygulama kuş uçuşu mesafeyi ön eleme için, Apple Maps sürüş mesafesini gösterim için kullanır.
- Sınırı aşan, çekme karavan kabulü doğrulanamayan veya güncel iletişim kaynağı bulunmayan yer öneri listesine girmez.

Gezilecek yerler kampın çevresinde seçilir. Günün sürüş yükü yüksekse uygulama kısa ve yakın ziyaretleri öne çıkarır; uzun sapmaları “başka güne bırak” notuyla gösterir veya listeden çıkarır.

## İçerik Yaklaşımı

Kuzey, küratörlü başlangıç verisini Apple Maps canlı aramasıyla birleştirir.

Her geceleme için ana kamp ve iki doğrulanmış alternatif hedeflenir. Alternatif sayısı kalite ölçütünü karşılayan yer sayısına göre azalabilir. Uygulama eksik sayıyı zayıf bir öneriyle tamamlamaz.

Her kamp kaydı şunları taşır:

- Ad, tür, koordinat, adres ve kaynak URL'si
- Ana kampa veya şehir merkezine mesafe; güzergâhtan sapma
- Telefon, WhatsApp için kullanılacak numara, e-posta ve web sitesi
- Çekme karavan uygunluğu, elektrik, su ve atık boşaltma bilgisi
- Açılış dönemi, giriş saatleri, rezervasyon yöntemi ve uzunluk sınırı
- Kısa “neden önerildi” ve “dikkat” notları
- Kaynak adı ve son doğrulama tarihi
- Lisanslı veya kullanıma izinli görsel, kredi ve lisans

Her gezi kaydı şunları taşır:

- Yer adı, koordinat, kategori ve kısa açıklama
- Kamptan yaklaşık sürüş mesafesi ve önerilen ziyaret süresi
- “Yorgunluk düşükse”, “dinlenme gününe uygun” veya “kısa mola” etiketi
- Harita ve resmî bilgi bağlantısı
- Görsel, kredi ve lisans

## İlk Küratörlü Liste

### Sofya / Elin Pelin

Kamp adayları:

- Mega Park Vrana — doğu yaklaşımında karavan ve camper parkı
- Caravan Park Sofia — yıl boyu açık, elektrik ve güvenlik bilgisi yayımlanmış camper stop
- Canlı yedek: Apple Maps ile Elin Pelin–Vrana koridorunda 25 km filtreli arama

Gezilecek yerler:

- Alexander Nevsky Katedrali
- Serdika antik kalıntıları ve merkez yürüyüşü
- Vrana Parkı

### Novi Sad / Kovilj

Kamp adayları:

- Auto Camp Farma 47 — elektrik bağlantılı camper alanı
- Eko Kamp Fruška Gora — araçlı kamp kabul eden, Sremski Karlovci yakınındaki doğa kampı
- Canlı yedek: Novi Sad çevresinde 25 km filtreli arama

Gezilecek yerler:

- Kovilj Manastırı ve Koviljsko-Petrovaradinski Rit
- Petrovaradin Kalesi
- Sremski Karlovci tarihî merkezi

### Budapeşte

Kamp adayları:

- Haller Camping — şehir içi ve toplu taşımaya yakın
- Ave Natura Camping — Buda tepelerinde, merkeze toplu taşıma bağlantılı
- Canlı yedek: Budapeşte çevresinde 25 km filtreli arama

Gezilecek yerler:

- Parlamento ve Tuna kıyısı
- Buda Kalesi ve Balıkçı Tabyası
- Kahramanlar Meydanı ve Széchenyi çevresi

### Kraków

Kamp adayları:

- Camping Smok — çekme karavan alanı, merkeze yaklaşık 4 km
- Camping Clepardia — tramvaya yakın; temmuz ve ağustosta kamp yerleri geliş sırasına göre
- Canlı yedek: Kraków çevresinde 25 km filtreli arama

Gezilecek yerler:

- Wawel Tepesi
- Ana Pazar Meydanı ve Kumaş Pazarı
- Kazimierz

### Varşova

Kamp adayları:

- Camping Majawa 123 — şehir içi karavan ve kamp alanı; iletişim ve güncel kabul koşulu gönderimden önce yeniden doğrulanır
- Camper Park Venessa — 24 saat erişim, elektrik, su ve atık servisi; çekme karavan kabulü mesajla teyit edilir
- Canlı yedek: Varşova çevresinde 25 km filtreli arama

Gezilecek yerler:

- Wilanów Sarayı
- Łazienki Kraliyet Parkı
- Eski Şehir ve Kraliyet Yolu

Ana kamp WOK için 8 metrelik araç sınırı belirgin uyarı olarak gösterilir.

### Riga

Kamp adayları:

- Riga City Camping — Ķīpsala'da sezonluk şehir kampı
- Camping Zanzibara — Via Baltica ve Riga çevre yoluna yakın aile kampı
- Canlı yedek: Riga çevresinde 25 km filtreli arama

Gezilecek yerler:

- Vecrīga / Eski Riga
- Art Nouveau bölgesi
- Riga Merkez Pazarı

Ana kamp Camping & Yachts için 7,5 metreden uzun kombinasyonlarda ön teyit uyarısı gösterilir.

## Kaynak ve Görsel Politikası

Kamp koşulları önce işletmenin resmî sitesinden, sonra resmî turizm kurumu veya ulusal kamp federasyonundan doğrulanır. Toplayıcı siteler yalnız aday bulmak için kullanılır; tek başına doğrulama kaynağı sayılmaz.

Gezi içeriği belediye, resmî turizm kurumu, UNESCO veya mekânın resmî sitesine dayanır. Her kayıtta kaynak URL'si ve `verifiedAt` tarihi bulunur.

Görseller mevcut uzaktan galeri sistemiyle yüklenir ve URLCache içinde tutulur. Uygulama yalnız açık lisanslı, resmî basın kullanımına açık veya projeye ait görselleri kullanır. Manifest; fotoğrafçı, kaynak ve lisans alanlarını zorunlu kılar. Ağ yoksa son önbellek veya temalı yer tutucu görünür.

## Gün Ayrıntısı Arayüzü

Gün ayrıntısı şu sırayı kullanır:

1. Gün özeti ve hesaplanan tahmini varış
2. Ana konaklama kartı
3. İletişim ve rezervasyon durumu
4. “Yakın kamp alternatifleri” yatay veya dikey liste
5. “Yakında gezilecek yerler” görsel şerit
6. Yol üstü duraklar ve mevcut alt planlar

Ana konaklama kartı kamp fotoğrafını, adresi, mesafeyi, karavan uygunluğunu ve kritik kısıtı gösterir. `Buraya Git` ana eylem olarak kalır. `İletişim`, `Haritada Aç` ve `Alternatifleri Gör` ikincil eylemlerdir.

Alternatif kamp kartı `Haritada Aç`, `İletişim` ve `Bu kampı seç` eylemlerini sunar. Kullanıcı bir alternatifi seçmeden önce hedef, iletişim bilgileri ve konaklama ayrıntılarının nasıl değişeceğini görür.

Gezi kartı görsel, kısa açıklama, kamptan mesafe, ziyaret süresi ve `Yol Tarifi` eylemi gösterir. Uygulama çekme karavanla şehir merkezine girilmemesi gereken yerlerde kampı kurup toplu taşıma veya taksi kullanma notunu öne çıkarır.

## Hesap Geneli Seyahat Profili

`StayContactProfile`, rota düzeyinden hesap düzeyine taşınır. Profil tüm yolculuklarda ortaktır ve özel hesap verisi olarak saklanır.

Profil alanları:

- İletişim adı ve e-posta
- Yetişkin ve çocuk sayısı
- Araç ve karavan açıklaması
- Toplam araç kombinasyonu uzunluğu
- Elektrik ihtiyacı
- Evcil hayvan bilgisi
- Ek ihtiyaçlar
- Tercih edilen mesaj dili

İlk doldurmada iletişim adı ve e-posta Apple hesabından alınır. İstanbul–Riga yolculuğunda araç açıklaması mevcut `vehicle` kaydından üretilir. Kullanıcı bütün alanları hesap ekranındaki `Seyahat profili` sayfasında düzenler.

Oturum açıkken profil özel hesap API'siyle cihazlar arasında senkronize edilir. Oturum yoksa yerel profil çalışır; kullanıcı giriş yaptığında yerel ve sunucu profili tarih damgasıyla uzlaştırılır. Profil herkese açık takip API'sine, galeri manifestine veya günlük paylaşımına girmez.

## Ulaşım Türüne Göre Mesaj

Mesaj üretici rota `transportMode` değerini alır.

- `automobile`: kişi, araç, karavan, toplam uzunluk, elektrik, evcil hayvan ve ek ihtiyaçlar kullanılır.
- `flight`: araç, karavan, toplam uzunluk ve elektrik cümleleri çıkarılır.
- `walking`: araç, karavan, toplam uzunluk ve elektrik cümleleri çıkarılır.

Boş profil alanları mesajda boş yer veya köşeli parantez üretmez. Kampın uzunluk sınırı varsa mesaj, kayıtlı toplam uzunluğu açıkça yazar ve kabul teyidi ister.

## Konaklama Otomatik Doldurma

Konaklama formu şu değerleri otomatik üretir:

- Giriş: plan gününün varış tarihi
- Çıkış: sonraki plan günü veya konaklama gün sayısına göre hesaplanan tarih
- Kişi ve ihtiyaçlar: hesap profilinden
- Tahmini varış: ETA hesaplayıcıdan
- Durum: `İletişim kurulmadı`
- Kamp iletişim alanları: doğrulanmış kamp kaydından

Kullanıcı her değeri değiştirebilir. Plan tarihi veya rota değişince uygulama otomatik üretilmiş değerleri günceller; kullanıcı tarafından değiştirilmiş alanları sessizce ezmez.

## Tahmini Varış

Planlama ETA'sı şu bileşenleri toplar:

`planlanan kalkış + Apple sürüş süresi + planlı mola dakikaları + sınır payı`

Sınır payı yalnız ülke geçişi olan etaplarda kullanılır ve gün verisinde açık bir dakika değeri olarak saklanır. Uygulama sonucu yarım saatlik bir aralığa yuvarlar. Örnek: merkez değer 19:05 ise mesaj `18:30–19:30` aralığını kullanır.

Aktif navigasyon başladığında Apple rota ETA'sı planlama değerinin yerini alır. Uygulama mesajı gönderim ekranı açılırken yeniden üretir. Kullanıcının elle girdiği ETA kilitlenir ve otomatik hesap onu değiştirmez.

## Harici İletişim Akışı

Kuzey üç kanalda hazır mesaj oluşturur:

- WhatsApp: `wa.me` bağlantısı doğrulanmış uluslararası numara ve URL kodlu metinle açılır.
- Mesajlar: `MFMessageComposeViewController` alıcı ve gövdeyle açılır.
- E-posta: `MFMailComposeViewController` alıcı, konu ve gövdeyle açılır. Kullanıcı sistem arayüzündeki `Kimden` alanından hesabı seçer.

Kullanıcı kanal düğmesine bastığında Kuzey mesaj metnini panoya kopyalar ve `Mesaj kopyalandı` bildirimi gösterir. İlgili uygulama veya hesap yoksa Kuzey hazır metni ekranda tutar ve yalnız kopyalama eylemini sunar.

Uygulama gönderim sonucunu yalnız sistem bileşeninin `sent`, `cancelled` veya `failed` sonucu kadar bilir. Bu sonuç teslimat veya karşı taraf yanıtı sayılmaz. Kuzey mesaj geçmişi, gelen kutusu veya ticket görünümü göstermez.

Kullanıcı gönderim bileşeni `sent` sonucu döndürdüğünde konaklama durumunu `Yanıt bekleniyor` olarak işaretlemeyi onaylayabilir. WhatsApp derin bağlantısı sonuç döndürmediği için uygulama kullanıcıdan aynı onayı ister.

## Veri Modeli

Yeni veya genişletilmiş yapılar:

- `TravelProfileRecord`: hesap düzeyindeki özel profil
- `CuratedCamp`: doğrulanmış kamp ayrıntıları, koordinat, kısıt, kaynak ve görsel
- `NearbyAttraction`: gezi ayrıntıları, koordinat, süre, kaynak ve görsel
- `TravelContentBundle`: hedef şehir anahtarı, kamp ve gezi listeleri, sürüm ve doğrulama tarihi
- `StayDetails.estimatedArrivalMode`: `automatic` veya `manual`
- `StayDetails.estimatedArrivalWindow`: başlangıç ve bitiş zamanı
- `DayPlan.borderBufferMinutes`: sınır payı

Mevcut `CampAlternative` yeni yapıya geçiş sırasında okunmaya devam eder. Eski kayıtlar kaynak ve koordinat içermiyorsa “doğrulanmamış” kabul edilir; seçimden önce Apple Maps ile yeniden çözülür.

## Hata Durumları

- Apple Maps mesafe hesaplayamazsa kuş uçuşu mesafe `yaklaşık` etiketiyle gösterilir.
- Küratörlü içerik indirilemezse uygulama son geçerli paketi veya gömülü başlangıç paketini kullanır.
- Görsel yüklenemezse kart boyutu değişmez; yer tutucu görünür.
- Kamp kaynağının doğrulama tarihi 90 günü aşarsa `Gitmeden önce teyit et` uyarısı çıkar.
- Telefon uluslararası biçime çevrilemezse WhatsApp gizlenir; Mesajlar alanı kullanıcı düzenlemesine açılır.
- E-posta geçersizse e-posta eylemi gizlenir ve iletişim düzenleme ekranı açılır.
- Sistem Mail hesabı yapılandırılmamışsa metin panoda kalır.
- Profil senkronu başarısız olursa yerel değişiklik korunur ve yeniden deneme durumu gösterilir.
- Uçak veya yürüyüş rotasında eski araç cümlesi taslakta saklanmaz; mesaj her açılışta yeniden üretilir.

## Testler

Model testleri mesafe filtresini, içerik paketi çözümlemeyi, 90 günlük güncellik uyarısını, ulaşım türüne göre mesaj cümlelerini, boş alan temizliğini, tarih türetmeyi ve ETA aralığını kapsar.

API testleri profilin hesaplar arasında ayrılmasını, özel alanda saklanmasını, yetkisiz yanıttan çıkarılmasını, güncelleme doğrulamasını ve tarih damgalı uzlaştırmayı kapsar.

Arayüz testleri profil düzenleme, otomatik konaklama doldurma, alternatif kamp seçme, gezi kartını haritada açma, WhatsApp URL'si, Mesajlar bileşeni, Mail bileşeni, otomatik kopyalama ve uygulama bulunmaması durumlarını doğrular.

Simülatör kontrolü Sofya, Novi Sad, Budapeşte, Kraków, Varşova ve Riga günlerini; karanlık tema, küçük ekran, Dynamic Type ve çevrimdışı görsel durumunda inceler.

## Başarı Ölçütleri

- Altı geceleme durağının her birinde kalite ölçütünü karşılayan yakın kamp alternatifleri görünür.
- Kamp kartı kritik uzunluk, sezon veya rezervasyon kısıtını saklamaz.
- Her durakta kaynaklı görsellerle yakın gezi önerileri bulunur.
- Alternatif kamp şehirde 25 km, transit hatta 10 km sapma sınırını aşmaz.
- Hesap profili bütün yolculuklarda kullanılır ve uçak/yürüyüş rotalarında araç bilgisi mesajdan çıkar.
- Giriş, çıkış, kişi bilgisi ve tahmini varış otomatik dolar; kullanıcı değişiklikleri korunur.
- WhatsApp, Mesajlar ve E-posta doğru alıcı ve metinle açılır; metin panoya kopyalanır.
- Kullanıcı Mail arayüzünde gönderen hesabı seçebilir.
- Uygulama desteklemediği mesaj geçmişi veya yanıt takibi izlenimi vermez.

## Araştırma Kaynakları

Başlangıç içeriği şu birincil veya kurumsal kaynaklarla doğrulanır:

- Apple MessageUI: `developer.apple.com/documentation/messageui`
- Sofia camper parkları: `megaparkvrana.bg`, `camperparking.bg`, `camping.bg`
- Novi Sad kamp ve gezi: `novisad.travel`, `kampfruskagora.com`
- Budapeşte kampları: `campingavenatura.hu`, `campingbudapest.eu`
- Kraków kampları ve gezi: `smok.krakow.pl`, `clepardia.com.pl`, `krakow.travel`
- Varşova kamp ve gezi: `campingwok.warszawa.pl`, `camperparkvenessa.pl`, `pfcc.eu`, `go2warsaw.pl`
- Riga kamp ve gezi: `campingyachts.lv`, `rigacamping.lv`, `zanzibara.lv`, `liveriga.com`
