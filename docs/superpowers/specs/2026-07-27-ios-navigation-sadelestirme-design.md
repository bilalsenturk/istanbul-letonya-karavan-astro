# iOS Navigasyon Sadelestirme Tasarimi

## Amac

KUZEY ekranlarinin ustunde duran ozel yolculuk cubugunu kaldirarak iPhone ve iPad'de tek, sistemle uyumlu bir navigasyon katmani kullanmak. Hesap, rota ve uye islemleri kaybolmadan ikincil bir yonetim alaninda toplanacak.

## Ana Navigasyon

- Uygulamanin ana yuzeyi yalnizca bes sistem sekmesinden olusur: Panel, Duraklar, Plan, Gunluk ve Araclar.
- `ContentView`, `TabView` ustune ek bir baslik veya menu cubugu koymaz.
- Her sekme kendi `NavigationStack` basligini ve ekrana ozel araclarini yonetir.
- iPad, sistemin uygun tab sunumunu kullanir; ozel bir ust katman sistem sekmelerini kapatmaz.

## Hesap Ve Yolculuk Yonetimi

- Panel'in sistem navigasyon cubugunda tek bir profil simgesi bulunur.
- Profil simgesi oturum acilmissa yolculuk yonetimini, acilmamissa Apple ile giris ekranini acar.
- Araclar ekraninda `Hesap ve yolculuk` bolumu kalici ve acik bir giris noktasi saglar.
- Yolculuk yonetimi; `Rotalarim`, secili yolculugun uyeleri ve hesap islemlerine erisim verir.
- Yolculuk degistirmek mevcut secimi kapatip `Rotalarim` ekranini acar. KUZEY'in ana sekmeleri kaybolmaz; kullanici geri dondugunde son secili sekme korunur.

## Durumlar

- Misafir: Sekmeler kullanilabilir; hesap eylemi Apple ile girisi acar.
- Oturum acmis KUZEY kullanicisi: Sekmeler kullanilabilir; hesap eylemi rota, uye ve hesap islemlerini acar.
- Standart rota secili: Mevcut `AccountStopsView` korunur ve kendi sistem navigasyonunu kullanir.
- Hesap geri yuklenirken ana arayuz engellenmez; hesap eyleminde kucuk bir yuklenme durumu gosterilir.

## Dogrulama

- iPhone'da bes alt sekme ve her ekranin basligi cakismadan gorunur.
- iPad'de bes sekme gorunur ve icerik ustten kesilmez.
- Misafir giris akisi, rota degistirme, uye yonetimi ve oturum kapatma erisilebilir kalir.
- Mevcut hesap alan testleri ve Simulator derlemesi gecer.
