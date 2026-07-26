# Apple Hesapları ve Çoklu Rotalar Tasarımı

## Amaç

Kuzey uygulaması Apple hesabıyla giriş yapan birden fazla kullanıcıyı ve rotayı destekleyecek. Kullanıcılar harita üzerinde rota oluşturacak, durakları ayrıntılandıracak ve rotalarına rol vererek başka kullanıcılar ekleyecek. Mevcut Leyla'nın Kuzey Yolculuğu korunacak; Letonca, müzik ve bu yolculuğa özgü araçlar yalnızca bu rotada görünecek.

## Ürün Akışı

Uygulama ilk açılışta Apple ile Giriş ekranını gösterir. Başarılı girişten sonra kullanıcı `Rotalarım` ekranına gelir. Bilal bütün rotaları görebilir. Leyla ve `szngk.13` mevcut Kuzey rotasını görür. Yeni kullanıcı boş durumda `Yeni rota` eylemini görür.

Kullanıcı bir rota seçince ana sekmeler açılır. `Rotalar` sekmesinin adı `Duraklar` olur. Bu sekme rotanın sıralı duraklarını, aktif etabı ve harita görünümünü gösterir. Rota sahibi durak ekler, düzenler, siler ve sıralar. Kuzey üyeleri durakları düzenleyebilir. Görüntüleyenler yalnızca okuyabilir.

Yeni rota akışı şu sırayı izler:

1. Kullanıcı rota adını ve isteğe bağlı tarihleri girer.
2. Başlangıç noktasını mevcut konumdan, yer aramasından veya haritadan seçer.
3. Yer araması ya da haritaya dokunma ile durak ekler.
4. Durakları sürükleyerek sıralar; MapKit güzergâhı ve yaklaşık mesafeyi yeniler.
5. Her durağa başlık, not, varış tarihi, konaklama bilgisi ve bağlantı ekler.
6. Rotayı oluşturur ve sahibi olur.

## Kimlik Doğrulama

iOS uygulaması `AuthenticationServices` ile native Apple ile Giriş kullanır. Uygulama her istek için rastgele nonce üretir ve özetini Apple isteğine ekler. `/api/auth/apple` Apple kimlik token'ının imzasını, issuer, audience, süre ve nonce değerini doğrular. API daha sonra kısa ömürlü erişim token'ı ve döndürülebilir yenileme token'ı üretir.

Uygulama token'ları Keychain'de saklar. API erişim token'ını her istekte doğrular. Çıkış, yenileme token'ını iptal eder ve kullanıcıya bağlı yerel önbelleği kapatır. Apple kimlik token'ı veya e-posta istemci tarafından rol kanıtı olarak kullanılamaz.

Apple gerçek e-postayı yalnızca ilk yetkilendirmede döndürür. Özel hesapların ilk girişte `E-postamı paylaş` seçmesi gerekir. API e-postayı bir kez doğrular ve Apple'ın sabit `sub` değerine bağlar. E-postasını gizleyen özel hesap normal kullanıcı olur; global admin daha sonra kullanıcı kimliğine rol veya rota üyeliği verebilir.

## Roller ve Yetkiler

Sistem iki yetki katmanı kullanır:

- `globalAdmin`: Bütün kullanıcıları ve rotaları görür, düzenler ve yönetir.
- `user`: Yalnızca üyesi veya sahibi olduğu rotalara erişir.

Rota rolleri:

- `owner`: Rotayı, üyeleri, durakları, günlüğü ve rota oturumunu yönetir.
- `member`: Durakları ve günlük kayıtlarını ekler ve düzenler.
- `viewer`: Rotayı ve günlüğü okur.

`senturk.bilal@icloud.com` ilk doğrulanmış girişte `globalAdmin` olur. `senturk.leyla@icloud.com` ve `szngk.13@icloud.com`, Kuzey rotasına `member` olarak bağlanır. Yeni rota oluşturan kullanıcı o rotanın `owner` rolünü alır. Bütün yazma uçları yetkiyi sunucuda denetler.

## Üyelik ve Davetler

Rota sahibi `Üyeler` ekranında e-posta girer ve `Üye` veya `Görüntüleyen` rolünü seçer. Kayıtlı kullanıcı hemen üyeliğe eklenir. Kayıtsız e-posta bekleyen davet olarak saklanır; kişi Apple ile giriş yapıp aynı doğrulanmış e-postayı paylaşınca davet otomatik kabul edilir. Sahip üyelerin rolünü değiştirir veya erişimini kaldırır. Son sahip silinemez.

## Veri Modeli

Sunucu şu temel kayıtları kullanır:

- `User`: Apple kullanıcı kimliğinin tek yönlü özeti, doğrulanmış e-posta, ad ve global rol.
- `Trip`: Kimlik, ad, tür, sahibi, tarihler, oluşturulma ve güncellenme zamanı.
- `TripMember`: Rota kimliği, kullanıcı veya bekleyen e-posta özeti ve rota rolü.
- `RouteStop`: Rota kimliği, sıra, koordinat, ad, not, tarih, konaklama ve bağlantı.
- `TripEvent`: Yetkili değişikliğin kimliği, sürümü, zamanı, aktörü ve yükü.

Kuzey rotasının türü `kuzey2026`, yeni rotaların türü `standard` olur. `kuzey2026` türü Letonca, yolculuk müziği ve Kuzey'e özel araçları açar. `standard` rotalar bu özellikleri göstermez.

## Vercel Saklama Katmanı

Mevcut Astro API korunur. Kimlik ve kişisel rota verileri ayrı bir Vercel Private Blob store içinde tutulur. API dışındaki istemciler Blob URL'lerine erişemez.

Değişiklikler tek bir ortak JSON dosyasını ezmez. API her yazmayı benzersiz kimlikli, sıralanabilir bir `TripEvent` olarak ekler. Okuma tarafı olayları katlayarak güncel rotayı üretir. İstemci son gördüğü sürümü gönderir; API eski sürümle gelen çakışan düzenlemeye `409` döndürür ve güncel kaydı yollar. Böylece uygulama kullanıcıya yenileme veya kendi değişikliğini yeniden uygulama seçeneği sunar.

Private Blob okumaları API içinde ETag ve kısa süreli önbellek kullanır. Uygulama yalnızca açılışta, öne geldiğinde ve kullanıcı yenilediğinde senkron olur; sürekli sorgulama yapmaz. Bu yaklaşım Vercel Hobby kotasını korur.

## API Sınırı

Yeni API uçları `/api/v2` altında yaşar:

- `POST /api/v2/auth/apple`: Apple token'ını doğrular ve uygulama oturumu açar.
- `POST /api/v2/auth/refresh`: Erişim token'ını yeniler.
- `POST /api/v2/auth/logout`: Yenileme token'ını iptal eder.
- `GET /api/v2/me`: Kullanıcıyı ve erişebildiği rotaları döndürür.
- `POST /api/v2/trips`: Yeni standart rota oluşturur.
- `GET/PATCH /api/v2/trips/:id`: Rotayı okur veya düzenler.
- `POST/PATCH/DELETE /api/v2/trips/:id/stops`: Durakları yönetir.
- `GET/POST/PATCH/DELETE /api/v2/trips/:id/members`: Üyeleri ve davetleri yönetir.
- `GET/POST/PATCH/DELETE /api/v2/trips/:id/journal`: Günlüğü yönetir.

Mevcut herkese açık takip uçları Kuzey rotasını göstermeyi sürdürür. Kişisel rotalar hiçbir herkese açık uçta yayımlanmaz.

## iOS Yapısı

`AccountSessionStore` oturum durumunu ve kullanıcı profilini yönetir. `TripWorkspaceStore` erişilebilir rotaları, seçili rotayı ve rota özelliklerini taşır. Bu iki depo uygulama kökünde oluşturulur ve ihtiyaç duyan ekranlara enjekte edilir.

Ekranlar:

- `SignInView`: Apple ile giriş ve yüklenme/hata durumları.
- `TripsHomeView`: Kullanıcının rotaları, Kuzey rozeti, yeni rota eylemi ve hesap menüsü.
- `RouteBuilderView`: Harita, arama, konum, sıralı durak taslağı ve rota özeti.
- `StopEditorView`: Durak ayrıntıları.
- `MembersView`: Üye listesi, bekleyen davetler ve rol yönetimi.
- `ContentView`: Seçili rota varsa rota sekmelerini, yoksa `TripsHomeView` ekranını gösterir.

Harita araması `MKLocalSearchCompleter`, rota çizimi `MKDirections` kullanır. Kullanıcı konum izni vermezse arama ve haritadan seçim çalışmaya devam eder. Ağ veya MapKit hatası taslağı silmez.

## Geçiş

İlk global admin girişi Kuzey rotasını mevcut `trip.json` verisinden sunucuya tohumlar. Mevcut yerel plan düzenlemeleri, rota durumu ve günlük kayıtları kimlikleri korunarak bir kez yüklenir. Her cihaz yalnızca kendi yerel günlük kayıtlarını taşır; API aynı kayıt kimliğini ikinci kez kabul etmez.

Cihaz bazlı `RoleStore` yetki kaynağı olmaktan çıkar. Navigasyon başlatma ve düzenleme düğmeleri hesap ve rota rolünden türetilir. Geçiş tamamlanana kadar mevcut veri dosyaları salt okunur yedek olarak kalır.

## Hata Durumları

- Apple giriş iptali kullanıcıyı giriş ekranında bırakır.
- Token yenileme başarısızsa uygulama güvenli biçimde çıkış yapar.
- Çevrimdışıyken rota taslağı cihazda kalır; sunucuya kaydedilene kadar `Taslak` görünür.
- Yetkisiz yazma `403`, sürüm çakışması `409`, doğrulama hatası `422` döndürür.
- Hesap değişince önceki hesabın seçili rotası ve önbelleği kullanılamaz.
- Sahipsiz rota, son sahibin silinmesi veya `kuzey2026` türünün istemciden atanması engellenir.

## Testler

Sunucu testleri Apple token doğrulamasını, oturum yenilemeyi, e-posta rol eşlemesini, bütün rol izinlerini, davet kabulünü, sürüm çakışmasını ve özel rota türü korumasını kapsar. Testler gerçek yetki fonksiyonlarını çağırır; yalnızca Apple ağ anahtarları sabit test anahtarıyla değiştirilir.

iOS testleri oturum durum makinesini, Keychain sınırını, hesap değişiminde önbellek ayrımını, rota taslağını, durak sıralamasını ve özellik görünürlüğünü kapsar. Derleme sonrası simülatörde giriş, boş rota listesi, rota oluşturma, durak ayrıntısı ve üyeler ekranları görsel olarak doğrulanır.

## Başarı Ölçütleri

- Kullanıcı Apple hesabıyla giriş yapar ve rolü sunucudan gelir.
- Üç özel hesap doğru yetkiyi ilk girişte alır.
- Yeni kullanıcı haritadan en az iki nokta seçip standart rota oluşturur.
- Rota sahibi e-posta ile üye veya görüntüleyen ekler.
- `Duraklar` sekmesi sıralı durakları gösterir ve yetkili kullanıcı ayrıntıları düzenler.
- Standart rotada Letonca, Kuzey müziği ve Kuzey'e özel araçlar görünmez.
- Başka kullanıcı kişisel rotayı okuyamaz veya değiştiremez.
- Mevcut Kuzey yolculuğu ve herkese açık takip sitesi çalışmayı sürdürür.
