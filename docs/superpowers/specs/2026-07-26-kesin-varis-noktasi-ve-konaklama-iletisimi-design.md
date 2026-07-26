# Kesin Varış Noktası ve Konaklama İletişimi Tasarımı

## Amaç

Kuzey uygulamasında bir plan gününün şehir hedefi ile navigasyonun gerçek varış noktası ayrılacak. `Sofya` etap ve arama bölgesi olarak kalırken `Camping Campuccino`, bir otel, kamp alanı veya tam adres gerçek varış noktası olacak. Dinlenme günü dışındaki bir etap gerçek varış noktası seçilmeden başlatılamayacak; rota anonsları ve konum sapması denetimleri de yalnızca kullanıcı bu hedef için navigasyonu açıkça başlattığında etkinleşecek.

Seçilen işletmenin Apple Maps tarafından sağlanan adres, telefon ve internet sitesi bilgileri plana alınacak. Kullanıcı eksik iletişim bilgilerini tamamlayacak; uygulama WhatsApp ve e-posta için düzenlenebilir, yeniden kullanılabilir konaklama mesajları hazırlayacak.

## Temel Kavramlar

Plan iki ayrı kavram kullanır:

- `Etap şehri`: Günü, sıralamayı, ülkeyi, tarih hesabını ve yer aramasının coğrafi kapsamını belirler. Örnek: `Sofya`.
- `Kesin varış noktası`: Yol tarifinin, varış algılamasının ve konaklama iletişiminin bağlandığı gerçek işletme veya adres. Örnek: `Camping Campuccino`.

Şehir merkezi hiçbir zaman sessiz bir navigasyon varsayımı olmaz. Kesin hedef seçilmemişse gün kartı `Varış yeri gerekli` durumunu gösterir ve `Buraya Git` eylemi devre dışı kalır. Dinlenme günlerinde hedef zorunlu değildir.

## Ürün Akışı

Plan gününün başlığı etap bilgisini korur: `İstanbul → Sofya`. Başlığın altında ana eylem alanı kesin varış noktasını gösterir. Hedef yoksa kullanıcı `Varış Yerini Seç` eylemine dokunur.

Seçim ekranı Apple Maps yer aramasını hedef şehir çevresinde açar. Kullanıcı kamp, otel, apart, karavan parkı, otopark veya adres arayabilir. Arama sonucu seçilince uygulama işletmenin adını, kategorisini, tam adresini, koordinatını, telefonunu ve internet sitesini önizler. Kullanıcı seçimi onayladıktan sonra hedef gün planına kaydedilir ve rota üyeleriyle senkronize edilir.

Hedef seçildikten sonra gün kartı şu bilgileri ve eylemleri gösterir:

1. Gerçek varış noktası adı ve türü.
2. Tam adres ve hedef şehre uzaklığı.
3. Rezervasyon ve iletişim durumu.
4. `Buraya Git` ana eylemi.
5. Ara, WhatsApp, e-posta, mesajı kopyala, web sitesini aç ve Apple Maps'te göster eylemleri.

Hedef değiştirildiğinde eski hedefin koordinatı ve iletişim bilgileri navigasyonda kullanılmaz. Kullanıcıya mevcut rezervasyon notlarının yeni hedefte tutulacağı veya temizleneceği açıkça gösterilir.

## Veri Modeli

Plan gününe serbest metin kamp alanları yerine yapılandırılmış bir `ArrivalTarget` eklenir:

- `id`: Uygulama içinde kararlı hedef kimliği.
- `mapItemIdentifier`: Sistem sağladığında Apple Maps kimliği.
- `name`: İşletme veya adres adı.
- `kind`: Kamp, otel, apart, karavan parkı, otopark, adres veya diğer.
- `latitude` ve `longitude`: Navigasyonun kesin koordinatı.
- `formattedAddress`: Gösterim ve iletişim için tam adres.
- `phone`: Apple Maps'ten gelen veya kullanıcı tarafından girilen telefon.
- `whatsAppPhone`: E.164 biçiminde doğrulanmış WhatsApp numarası.
- `email`: Kullanıcı tarafından doğrulanan e-posta.
- `websiteURL`: İşletmenin internet sitesi.
- `source`: Apple Maps, kullanıcı girişi veya eski veriden geçiş.
- `updatedAt`: Çakışma ve güncellik kontrolü için zaman.

Konaklama ayrıntıları ayrı bir `StayDetails` içinde tutulur:

- Giriş ve çıkış tarihleri.
- Gece sayısı; plan tarihleri değiştiğinde yeniden hesaplanır.
- Rezervasyon durumu, referansı ve notu.
- Tahmini varış saati.
- Kişi sayısı, araç/karavan bilgisi, elektrik ve diğer ihtiyaçlar.
- Son iletişim zamanı ve kullanılan kanal.

`destination` alanı etap şehri olarak korunur. Mevcut `campName`, `campPlace` ve `campLink` alanları geçiş sırasında `ArrivalTarget` ve `StayDetails` içine taşınır; koordinatı bulunamayan eski kayıt kesin hedef sayılmaz ve yeniden seçim ister.

## Apple Maps Entegrasyonu

Arama `MKLocalSearchCompleter` ve `MKLocalSearch` ile yapılır. Arama bölgesi etap şehrinin koordinatı çevresinde başlar; kullanıcı haritayı taşıdığında `Bu bölgede ara` ile kapsamı değiştirebilir. Kategori kısayolları arama sorgusunu daraltır ancak sonuçları yapay bir sabit listeyle sınırlamaz.

Seçilen `MKMapItem` içinden ad, koordinat, posta adresi, telefon, internet sitesi, kategori ve mümkünse sistem kimliği alınır. MapKit e-posta veya WhatsApp hesabı sağlamaz. Bu alanlar tahmin edilmez; kullanıcı tarafından girilir veya doğrulanmış telefon numarasından WhatsApp numarası oluşturulur. Apple Maps sonucu değişse bile plana kaydedilmiş hedef çevrimdışı görüntülenebilir.

Konum izni yoksa hedef şehir çevresinde arama çalışır. Ağ veya MapKit hatası mevcut seçimi silmez. Sonuç seçimi sırasında harita ve liste aynı seçili öğeyi gösterir; kullanıcı onaylamadan plan güncellenmez.

## İletişim Profili ve Mesajlar

Kullanıcının her tesis için aynı bilgileri yeniden yazmaması için rota düzeyinde bir `StayContactProfile` tutulur:

- İletişim kurulacak kişinin adı.
- Yetişkin ve çocuk sayısı.
- Otomobil ve karavan modeli veya toplam uzunluğu.
- Elektrik, evcil hayvan ve diğer temel ihtiyaçlar.
- Tercih edilen mesaj dili.

Varsayılan iletişim dili İngilizcedir ve gönderimden önce değiştirilebilir. Hazır WhatsApp mesajı ve e-posta gövdesi hedef adı, giriş/çıkış tarihleri, gece sayısı, kişi/araç bilgileri, tahmini varış saati ve uygunluk/fiyat talebinden üretilir. E-posta ayrıca kısa bir konu satırı üretir.

Mesajlar hiçbir zaman kullanıcı onayı olmadan gönderilmez. `WhatsApp'tan Yaz` geçerli E.164 numarası ve URL-encoded mesaj ile WhatsApp bağlantısını açar. `E-posta Gönder` sistem e-posta oluşturucusunu konu ve gövdeyle açar. İlgili uygulama kurulu değilse mesajı kopyalama seçeneği sunulur. Telefon, e-posta veya internet sitesi yoksa karşılık gelen eylem gizlenir veya eksik bilgiyi tamamlama akışını açar.

## Navigasyon ve Rota Yaşam Döngüsü

`Buraya Git` aşağıdaki koşullar sağlanmadan çalışmaz:

- Gün dinlenme günü değildir.
- Gün, tamamlanmamış sıradaki etaptır.
- Kesin varış noktasının geçerli koordinatı vardır.
- Kullanıcı rota başlatma yetkisine sahiptir.

Navigasyon başlangıcı cihazın güncel GPS konumudur; planın eski başlangıç koordinatı veya şehir merkezi kullanılmaz. Hedef `ArrivalTarget` koordinatıdır. Aktif rota oturumu etap kimliğiyle birlikte hedef kimliğini ve hedef koordinatını saklar.

Rota anonsları, sapma denetimi, fırtına değerlendirmesi ve ilerleme hesabı yalnızca bu oturum aktifken çalışır. Hedef düzenlenmek istenirse aktif navigasyon önce durdurulur veya kullanıcı yeni hedef için rotayı açıkça yeniden başlatır. Uygulamanın yeniden açılmasında etkin oturum, etap ve hedef kimlikleri birlikte doğrulanır; uyuşmayan eski oturum otomatik olarak anons üretmez.

Varış algılama şehir merkezine değil kesin hedefe göre yapılır. Düşük GPS doğruluğunda otomatik tamamlanma yapılmaz; kullanıcıya varışı onaylama seçeneği gösterilir. Etap tamamlanınca şehir durağı tamamlanmış sayılır ve sıradaki etap açılır.

## Tarih ve Plan Değişiklikleri

Bir durakta fazladan gün eklendiğinde sonraki etapların başlangıç ve varış tarihleri tek plan hesaplayıcısından yeniden üretilir. `StayDetails` giriş/çıkış tarihleri de aynı sonuçtan güncellenir. Önceden hazırlanmış iletişim metni saklanmış sabit metin değil, gönderim anında güncel plan verisinden üretilir; böylece eski tarih gönderilmez.

Hedefin rezervasyon tarihleri planla çelişirse gün kartında uyarı gösterilir. Kullanıcı plan tarihini değiştirebilir veya konaklama tarihini planla eşitleyebilir. Senkronizasyon sırasında eski bir cihaz daha yeni hedefi veya tarihleri sessizce ezemez; sürüm çakışması çözülmeden yazma uygulanmaz.

## Yetkiler ve Senkronizasyon

Rota sahibi ve üyeler kesin hedefi, konaklama ayrıntılarını ve iletişim bilgilerini düzenleyebilir. Görüntüleyenler hedefi ve iletişim durumunu görür ancak mesaj taslağındaki kişisel profil bilgilerine erişmez. Global admin bütün rota verisini yönetebilir.

Sunucu hedefi yapılandırılmış veri olarak saklar ve sürümlendirir. Telefon, e-posta, rezervasyon referansı ve iletişim profili herkese açık takip API'sinde yayımlanmaz. Web takip sitesi yalnızca güvenli hedef özeti yayımlanacak şekilde rota sahibinin açık tercihine uyar; varsayılan olarak kesin tesis adı ve iletişim bilgileri özeldir.

## Arayüz İlkeleri

Plan düzenleme ekranındaki serbest metin `Nereye`, `Kamp adı` ve `Yer` alanları ana akıştan kaldırılır. Etap şehri yalnızca sıralı rota düzenleme akışından değiştirilir. Kesin hedef seçimi ayrı, harita odaklı bir akıştır.

Gün kartı tek bir görsel hiyerarşi kullanır:

- Küçük başlık: etap şehri ve tarih.
- Ana içerik: kesin varış noktası veya `Varış yeri gerekli`.
- Birincil eylem: `Buraya Git`.
- İkincil eylemler: iletişim ve ayrıntı.

Seçilemeyen veya sırası gelmemiş etaplarda başlatma düğmesi gösterilmez. Kullanıcıya aynı anda birden fazla eşdeğer ana eylem sunulmaz. Eksik hedef, nötr/uyarı rengiyle; aktif rota, sistem vurgu rengiyle; tamamlanan etap ise yeşille gösterilir.

## Hata Durumları

- Apple Maps sonucu telefon veya web sitesi içermiyorsa seçim yine kaydedilir; eksik alanlar açıkça belirtilir.
- Girilen WhatsApp numarası uluslararası biçime çevrilemiyorsa bağlantı oluşturulmaz.
- E-posta biçimi geçersizse sistem e-posta oluşturucusu açılmaz.
- Hedef çevrimdışıyken düzenlenirse değişiklik taslak olarak kalır ve çevrimiçi olunca sürüm kontrolüyle gönderilir.
- Hedef silinirse rota başlatılamaz ve eski rota oturumu kullanılamaz.
- MapKit aynı isimli birden fazla yer döndürürse adres ve harita konumu gösterilmeden hızlı seçim yapılmaz.
- İşletme taşınmış veya kapanmış görünüyorsa kullanıcı hedefi yeniden doğrulamadan navigasyon başlatabilir ancak belirgin bir güncellik uyarısı görür.

## Testler

Model testleri şehir ve kesin hedef ayrımını, eski kamp alanlarının geçişini, tarih kaydırmasını, iletişim metni üretimini, telefon normalizasyonunu ve özel alanların herkese açık yanıttan çıkarılmasını kapsar.

Navigasyon testleri hedef olmadan başlatmanın reddedilmesini, mevcut GPS konumunun başlangıç alınmasını, kesin koordinatın hedef olmasını, sırası gelmeyen etabın engellenmesini, aktif oturum-hedef uyuşmazlığında anonsların kapanmasını ve hedef değişiminde yeniden başlatma zorunluluğunu kapsar.

Arayüz testleri Apple Maps araması, kategori filtreleri, sonuç önizlemesi, eksik iletişim alanları, WhatsApp/e-posta derin bağlantıları, çevrimdışı taslak ve küçük ekran düzenini doğrular. Simülatörde hedef seçme, mesaj hazırlama ve `Buraya Git` akışı baştan sona görsel olarak kontrol edilir.

## Başarı Ölçütleri

- `Sofya` etap şehri olarak kalırken gerçek kamp veya otel ayrı seçilir.
- Dinlenme günü dışındaki etap kesin hedef olmadan başlatılamaz.
- Yol tarifi güncel cihaz konumundan kesin hedef koordinatına hesaplanır.
- Rota anonsları yalnızca açıkça başlatılmış ve hedefle eşleşen rota oturumunda çalışır.
- Apple Maps'in sağladığı adres, telefon ve internet sitesi seçim önizlemesinde görünür ve plana kaydedilir.
- WhatsApp ve e-posta metinleri güncel tarih ve seyahat profilinden üretilir, gönderimden önce düzenlenebilir.
- Fazladan gün eklenince sonraki tarihler ve iletişim taslakları güncel planı kullanır.
- Üyeler hedefi düzenleyebilir; görüntüleyenler özel iletişim ve rezervasyon bilgilerini alamaz.
- Eski şehir merkezi hedefi veya eski kamp metni sessizce navigasyon hedefi olarak kullanılmaz.
