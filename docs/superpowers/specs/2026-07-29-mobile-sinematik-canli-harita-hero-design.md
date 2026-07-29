# Mobil Sinematik Canli Harita Hero Tasarimi

## Amac

Ana sayfa, yolda olma duygusunu ilk ekranda vermeli ve canli konumu tek bakista anlatmali. Tasarim once telefon ekranina gore kurulacak; masaustu gorunumu ayni hiyerarsiyi daha genis bir kompozisyona tasiyacak.

## Kapsam

- Ana sayfanin hero alani yeniden tasarlanacak.
- Hero ile rota cizgisi, harita ve yolculuk ozeti arasindaki gecis iyilestirilecek.
- Mevcut API'ler, rota verisi, harcama verisi ve hava durumu akisi korunacak.
- Gun detay sayfalari, hesap sistemi ve iOS uygulamasi degismeyecek.

## Ana Kompozisyon

Hero iki katmani birlestirecek:

1. Sinematik yol goruntusu, hareket halindeki karavani ve ileri akan yolu gosterecek.
2. Canli mini harita, rotayi, guncel konumu ve siradaki duragi gosterecek.

Mobilde yol goruntusu ekranin ust bolumunu kaplayacak. Baslik ve canli durum, okunurlugu koruyan koyu bir alt bantta yer alacak. Mini harita bu banttan sonra gelecek ve hero'nun parcasi gibi gorunecek. Masaustunde metin solda, sinematik goruntu sagda ve mini harita goruntunun alt kenarinda konumlanacak.

Hero'da yalnizca su bilgiler bulunacak:

- `Leyla'nin Kuzey Yolculugu`
- Okunabilir canli durum: `Umraniye, Istanbul -> Sofya`
- Kalkis oncesinde kompakt geri sayim; yolculuk basladiginda `Rota aktif` durumu
- Baslangic, simdiki konum, siradaki durak ve Riga'dan olusan sade rota ozeti
- Canli mini harita

Kalan yol, gidilen mesafe, hava, yakit ve harcama bilgileri hero'nun altindaki yolculuk ozeti bandina tasinacak.

## Hareket Dili

- Sinematik gorsel, yavas ve kesintisiz bir yatay kayma ile hafif olcek degisimi kullanacak.
- Rota cizgisi, ilerleme yonunde sakin bir akis animasyonu gosterecek.
- Canli konum isareti, yeni veri geldiginde kisa bir nabiz animasyonu verecek.
- Kaydirma sirasinda gorsel ve metin farkli hizlarda en fazla birkac piksel hareket edecek.
- `prefers-reduced-motion` etkinse tum surekli hareketler duracak.

Hareket, metin okunurlugunu bozmayacak ve telefonda pil tuketimini artiran surekli JavaScript donguleri kullanmayacak. Animasyonlar CSS donusumleriyle calisacak.

## Gorsel Yon

- Yeni hero gorseli, capraz arkadan gorunen cekici arac ve Adria karavani acik bir Avrupa yolunda gosterecek.
- Yol cizgileri, ufuk ve aracin yonu ileri hareketi guclendirecek.
- Sahne, gunun ilk isiklarinda gercekci, canli ve dogal gorunecek.
- Goruntu, mobilde dikey kirpmaya ve masaustunde yatay kirpmaya uygun guvenli odak alanlari tasiyacak.
- Yapay pariltilar, neon efektler, yogun renk yikamalari ve sahte arayuz metinleri kullanilmayacak.

## Canli Konum Kurali

Arayuz hicbir durumda enlem ve boylam gostermeyecek. Konum metni su oncelikle belirlenecek:

1. API'nin sagladigi sehir ve bolge adi
2. Aktif rota duragi veya siradaki duraga gore `Sofya yonunde`
3. En yakin planli duraga gore `Istanbul cevresi`
4. Veri eksikse `Konum guncelleniyor`

Hero, konumun guncellenme zamanini ikincil metinde gosterecek. Eski veri, canliymis gibi sunulmayacak.

## Mini Harita

- Harita, mevcut rota geometrisini ve canli konum olayini kullanacak.
- Mobilde 180 piksel yuksekliginde, dokunmayla tam haritaya gecen sakin bir rota penceresi olacak.
- Harita varsayilan durumda suruklemeyi ve yakinlastirmayi devre disi birakacak; bu sayede sayfa kaydirmasini engellemeyecek.
- Canli isaret, rota cizgisi ve siradaki durak belirgin olacak. Tum ara durak etiketleri ayni anda gosterilmeyecek.
- Tam boy harita sayfanin alt bolumunde kalacak.

## Mobil Yerlesim

- Hero yuksekligi ilk ekrani gereksiz yere asmadan sonraki bolumun baslangicini gosterecek.
- Sinematik gorselin yuksekligi `clamp(320px, 44svh, 430px)` olacak.
- Baslik en fazla iki satir olacak.
- Dokunma hedefleri en az 44 piksel olacak.
- Hero icinde iki sutunlu istatistik kartlari bulunmayacak.
- 360, 390 ve 430 piksel genisliklerde yatay tasma olmayacak.
- Harita, geri sayim ve canli durum ayni anda okunabilir kalacak.

## Sayfa Ritmi

Hero'dan sonra mobilde yatay kaydirilabilir, masaustunde tek satirlik bir yolculuk ozeti gelecek. Ardindan rota cizgisi ve tam harita yer alacak. Harcama ve yol ayrintilari daha asagida acik listeler halinde kalacak. Galeri, daha buyuk ve daha az sayida goruntuyla yol hikayesini tamamlayacak.

Bu sira kullanilacak:

1. Sinematik hero ve mini harita
2. Yolculuk ozeti
3. Rota cizgisi
4. Tam harita
5. Yol ve harcama ayrintilari
6. Yoldan kareler

## Durumlar

- Kalkis oncesi: Canli durum, mevcut yeri ve kalkis geri sayimini gosterir.
- Yolda: Canli durum, mevcut yeri ve siradaki duragi gosterir; rota cizgisi akar.
- Konum gecikmis: Son bilinen yer ve guncelleme zamani gosterilir.
- Konum yok: `Konum guncelleniyor` yazilir; koordinat gosterilmez.
- Harita yuklenemez: Metin durumu ve rota ozeti calismaya devam eder.

## Erisilebilirlik Ve Performans

- Baslik, durum ve harita icin anlamli HTML ve Turkce erisilebilir adlar kullanilacak.
- Metin kontrasti WCAG AA duzeyini karsilayacak.
- Hero gorseli mobil ve masaustu icin uygun boyutlarda WebP olarak sunulacak.
- Ilk gorsel yuksek oncelikle, alt bolum gorselleri tembel yuklenecek.
- Harita ve animasyonlar sayfa kaydirma performansini dusurmeyecek.
- `prefers-reduced-motion` tercihi desteklenecek.

## Dogrulama

- 390 x 844 mobil gorunumde baslik, canli durum, hareketli gorsel ve mini harita ilk akis icinde gorunur.
- 360, 390 ve 430 piksel mobil genisliklerde yatay tasma yoktur.
- 1440 x 1000 masaustu gorunumunde gorsel, metin ve harita tek odakli bir kompozisyon kurar.
- API sehir adi saglamadiginda koordinat metni gorunmez.
- Kalkis oncesi, yolda, gecikmis veri ve veri yok durumlari dogru metni gosterir.
- `prefers-reduced-motion` etkinlestiginde surekli hareket durur.
- Ana sayfa Astro kontrolu, ESLint ve uretim derlemesinden gecer.
- Kabul edilen gorsel konsept ile masaustu ve mobil tarayici ekran goruntuleri yan yana karsilastirilir.

## Yayin

Degisiklikler yerelde dogrulandiktan sonra bagli Vercel projesine uretim yayini yapilacak. Yayinlanan URL hem mobil hem masaustu gorunumunde son kez kontrol edilecek.
