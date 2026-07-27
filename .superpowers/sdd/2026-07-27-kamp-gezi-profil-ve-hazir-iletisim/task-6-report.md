# Task 6 — Sistem Mesaj Oluşturucuları ve Otomatik Kopyalama

## RED

- `ios/Tests/arrival-target-check.swift` içinde `PreparedContactAction` beklentileri eklendi.
- `./ios/Tests/run-arrival-target-check.sh`, beklenildiği gibi `StayContactAction` ve `StayContactFollowUp` bulunamadığı için derleme hatasıyla kırmızı oldu.
- İletişim sonucunda durumu yalnız açık kullanıcı onayıyla değiştirme beklentisi de önce eksik API nedeniyle kırmızı doğrulandı.

## GREEN

- Saf hazırlayıcı, e-posta ve telefon alıcılarını doğrular; WhatsApp için E.164 sayıları üretir; konu ve gövdeyi değiştirmez.
- Mesajlar ve Mail gerçek `MessageUI` bestecileriyle açılır; Mail'de gönderen hesap programatik olarak seçilmez.
- Her kanal önce aynı gövdeyi panoya alır ve iptal edilebilir iki saniyelik `Mesaj kopyalandı` bildirimini gösterir.
- Uygulama/hazır hesap yoksa kopyalama korunur ve kullanıcıya tam kullanılabilirlik bildirimi gösterilir.
- WhatsApp `wa.me` URL'siyle açılır; yalnız gerçek uygulama dönüşünden sonra, bir kez, `Yanıt bekleniyor` için kullanıcı onayı istenir. Sistem bestecilerinde aynı soru yalnız `.sent` sonucundan sonra sorulur.

## Doğrulama

- `./ios/Tests/run-arrival-target-check.sh` geçti.
- `cd ios && xcodegen generate` tamamlandı.
- `xcodebuild -quiet -project ios/Kuzey.xcodeproj -scheme Kuzey -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' build CODE_SIGNING_ALLOWED=NO` geçti.

## Kapsam ve Notlar

- Değişiklikler yalnız `ArrivalTarget`, varış editörü, yeni besteci sarmalayıcısı ve varış doğrulama testleriyle sınırlıdır.
- Uygulama konuşma geçmişi, teslimat/okundu işareti veya gelen mesaj iddiası göstermez. `Yanıt bekleniyor` yalnız kullanıcının seçtiği konaklama durumudur.
- `xcodegen`, paylaşılan kirli çalışma alanındaki başka yeni kaynakları da proje dosyasına ekledi. Task 6 için proje dosyasında yalnız `StayContactComposer.swift` satırları stage edilmelidir; diğer üretilmiş hunks başka görevlerin kapsamındadır.

## Fix Round 1 — WhatsApp Handoff

- WhatsApp artık Safari/web fall-back yerine yalnız `whatsapp://send` uygulama şemasını, E.164 telefon sorgusunu ve URLComponents ile kodlanmış özgün gövdeyi kullanır.
- `LSApplicationQueriesSchemes` altında `whatsapp` tanımlandı; `canOpenURL` bu doğrudan şemayı doğrular. Uygulama yoksa metin kopyalı kalır ve standart kullanılamaz uyarısı gösterilir.
- Saf `WhatsAppHandoffState`, başarılı açılış ile gerçek inactive→active dönüşün ikisini de bekler; ters callback sırası, geç başarısızlık, tekrar eden aktif olayları ve eski action ID'leri tek seferlik/doğru davranışla kapsar.
- E.164 normalleştirme yalnız ASCII biçim ayraçlarını kabul eder; `+`/`00` ön ekini kaldırdıktan sonra `[1-9][0-9]{7,14}` uygular. Unicode rakamlar, harfler, sıfır önekleri ve uzunluk sınır dışı değerler reddedilir.
- Doğrulama: arrival harness, `xcodegen generate` ve mevcut paylaşılan çalışma alanındaki simulator build geçti. Temiz arşiv sonucu, paylaşılan alandaki bağımsız `SubplanCompactRow` kaynağı nedeniyle bu görev tarafından iddia edilmez.

## Fix Round 2 — Runtime Scheme and Prefix Grammar

- PBX tarafından kullanılan `ios/Support/Info.plist` içine `LSApplicationQueriesSchemes`/`whatsapp` dizisi eklendi; `ios/project.yml` eşdeğer beyanı korunur.
- `ios/Tests/run-whatsapp-plist-check.sh`, çalışma dizini veya index yerine `HEAD` içeriğini okuyarak iki kaynağın da WhatsApp sorgu şemasını taşıdığını doğrular.
- Telefon ayrıştırıcısı çevre boşluğunu kırpar; yalnız ilk karakterlerde tek `+`, baştaki `00` veya yalın sayı biçimini kabul eder. Kalan bölüm ASCII sayı/boşluk/tire/parantezle sınırlıdır; iç/çift `+`, `00+`, `(00)`, Unicode sayı ve harfler reddedilir.

## Fix Round 3 — Executable Plist Check

- `ios/Tests/run-whatsapp-plist-check.sh` dosya modu `100755` olarak kaydedildi; doğrulama artık doğrudan `./ios/Tests/run-whatsapp-plist-check.sh` ile çalışır.
- Doğrudan plist kontrolü ve arrival harness yeniden geçti.
