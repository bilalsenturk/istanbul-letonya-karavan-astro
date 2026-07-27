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
