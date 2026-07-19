export type RouteStop = {
  id: string;
  name: string;
  country: string;
  lat: number;
  lng: number;
};

type ChecklistTask = {
  id: string;
  due: string;
  task: string;
};

type CampPlan = {
  name: string;
  place: string;
  contact: string;
  email: string;
  phone?: string;
  link: string;
  reservationTemplate: string;
  note: string;
};

type DayStop = {
  type: 'Petrol' | 'Kahve' | 'Görülecek' | 'Tedarik';
  name: string;
  note: string;
  mapUrl: string;
  estimatedMinutes: number;
};

type CameraResource = {
  title: string;
  url: string;
  source: string;
  kind?: 'video' | 'web';
};

export type DayPlan = {
  id: string;
  slug: string;
  date: string;
  origin: string;
  destination: string;
  distanceKm: string;
  duration: string;
  fuel: string;
  risks: string[];
  opportunities: string[];
  contingencies: string[];
  camp: CampPlan;
  stops: DayStop[];
  route: string;
  routeEmbed: string;
  trafficEmbed: string;
  trafficLabel: string;
  cityCameras: CameraResource[];
};

export type TripData = {
  departureAt: string;
  vehicle: {
    plate: string;
    model: string;
    description: string;
    towing: string;
  };
  totalKm: number;
  totalBudget: {
    min: number;
    max: number;
    fuel: string;
    total: string;
  };
  checklist: ChecklistTask[];
  postArrival: Array<{ when: string; title: string; text: string }>;
  stops: RouteStop[];
  days: DayPlan[];
  routeGuide: {
    city: string;
    from: string;
    to: string;
    distance: string;
    reason: string;
  }[];
};

export const tripData: TripData = {
  departureAt: '2026-08-03T05:00:00+03:00',
  vehicle: {
    plate: '34 SC 2441 TR',
    model: 'VW Passat 2016 1.6 TDI Highline (Camlı Tavan)',
    description: 'Nette çalışan çekici setup: beyaz Passat + çekili karavan',
    towing: 'Çekme: Düzgün ve stabilize edilmiş; stop-start testleri sonrası onay.',
  },
  totalKm: 3150,
  totalBudget: {
    min: 1345,
    max: 1795,
    fuel: '€520–590',
    total: '€1.500 – €1.600 (pratik hedef)',
  },
  checklist: [
    { id: 'pmlp', due: '19–21 Temmuz', task: 'PMLP randevusu, okul yazışmaları, buz pateni kulübü başvuruları' },
    { id: 'insurance', due: '19–21 Temmuz', task: 'Yeşil Kart teyidi, yol yardım kapsamı ve karavan sigorta yazısı' },
    { id: 'service', due: '20–24 Temmuz', task: 'Araç mekanik onayı: fren, soğutma, çekme sistemi, akü ve 13-pin elektrik' },
    { id: 'tires', due: '20–24 Temmuz', task: 'Araç ve karavan lastikleri, stepne, balans, derinlik kontrolü' },
    { id: 'clean', due: '25–26 Temmuz', task: 'Araç içi, tavan ve karavanın detaylı temizlik planı' },
    { id: 'test-drive', due: '27 Temmuz', task: '100–150 km deneme sürüşü + fren, gürültü, ısınma takibi' },
    { id: 'fixes', due: '28–29 Temmuz', task: 'Sürüşte görülen titreşim, çekim, elektrik ve fren sorunlarının giderilmesi' },
    { id: 'documents', due: '30 Temmuz', task: 'Ruhsatlar, sigorta, sağlık, kamp ve oturum dosyaları klasörü' },
    { id: 'load', due: '31 Temmuz', task: 'Eşya yerleşimi + aks ve dingil yük ölçümü' },
    { id: 'final', due: '2 Ağustos', task: 'Buzdolabı girişi, lastik basıncı, erken uyku ve son yükleme' },
  ],
  postArrival: [
    { when: '10 Ağustos', title: 'Varış ve kurulum', text: 'Elektrik, su, internet ve kısa günlük kullanım akışı kurulur. Ağır eşyalar sabitlenmiş kalır.' },
    { when: '11 Ağustos', title: 'Rutin güvenlik günü', text: 'Sim kart, adres bilgisi ve PMLP / sağlık ön hazırlıkları tamamlanır.' },
    { when: '12–20 Ağustos', title: 'PMLP ve sağlık belgeleri', text: 'Aktif tüberküloz yokluğu, sağlık sigortası ve ikamet kanıtı kontrol edilir.' },
    { when: '13–21 Ağustos', title: 'Leyla’nın rutin geçişi', text: 'Skate seviye tespiti, antrenör eşleşmesi ve okul temposu ile saat uyumu yapılır.' },
    { when: '17–28 Ağustos', title: 'Şirket ve adres süreci', text: 'Şirket kurulum + yönetim kurulu kaydı ve PMLP takvimi eşleştirilir.' },
    { when: '24–28 Ağustos', title: 'Okul ve yaşam geçişi', text: 'Malzeme listesi, ulaşım denemesi, öğle menüsü ve kampüs öncesi günlük düzen netleşir.' },
  ],
  stops: [
    { id: 'istanbul', name: 'İstanbul', country: 'Türkiye', lat: 41.0082, lng: 28.9784 },
    { id: 'sofia', name: 'Sofya', country: 'Bulgaristan', lat: 42.6977, lng: 23.3219 },
    { id: 'bucharest', name: 'Bükreş', country: 'Romanya', lat: 44.4268, lng: 26.1025 },
    { id: 'deva', name: 'Deva', country: 'Romanya', lat: 45.8833, lng: 22.9 },
    { id: 'budapest', name: 'Budapeşte', country: 'Macaristan', lat: 47.4979, lng: 19.0402 },
    { id: 'katowice', name: 'Katowice', country: 'Polonya', lat: 50.2649, lng: 19.0238 },
    { id: 'suwalki', name: 'Suwałki', country: 'Polonya', lat: 54.111, lng: 22.93 },
    { id: 'riga', name: 'Riga', country: 'Letonya', lat: 56.9496, lng: 24.1052 },
  ],
  routeGuide: [
    { city: 'İstanbul', from: 'İstanbul', to: 'Sofya', distance: '540–560 km', reason: 'Tek günde sınır geçişine uygun, dinlenme dengeli.' },
    { city: 'Sofya', from: 'Sofya', to: 'Bükreş', distance: '440–470 km', reason: 'Gecikme riskini düşürmek için kısa mola planı.' },
    { city: 'Bükreş Güney', from: 'Bükreş', to: 'Deva', distance: '430–450 km', reason: 'Olt Vadisi ve dağ geçişleri nedeniyle dikkatli hız.' },
    { city: 'Deva', from: 'Deva', to: 'Budapeşte', distance: '280–320 km', reason: 'Daha kısa bir gün ile yorgunluğu kır.' },
    { city: 'Budapeşte', from: 'Budapeşte', to: 'Budapeşte', distance: 'Sürüş yok', reason: 'Sahada dinlenme ve sistem kontrolü için ayrılmış tampon gün.' },
    { city: 'Budapeşte', from: 'Budapeşte', to: 'Katowice', distance: '570–600 km', reason: 'Uzun gün; iki güvenli mola ve iki kez yakıt kontrolü şart.' },
    { city: 'Katowice', from: 'Katowice', to: 'Suwałki', distance: '550–580 km', reason: 'Doğu Avrupa aksında akışa göre hız planı.' },
    { city: 'Suwałki', from: 'Suwałki', to: 'Riga', distance: '360–390 km', reason: 'Son 2 günde düşük stresle varış.' },
  ],
  days: [
    {
      id: '01',
      slug: 'istanbul-sofya',
      date: '3 Ağustos · Pazartesi',
      origin: 'İstanbul',
      destination: 'Sofya',
      distanceKm: '540–560 km',
      duration: '8–10 saat + sınır',
      fuel: '65–75 L · €95–115',
      risks: [
        'Kapıkule yoğunluğu ve uzun bekleme olasılığı',
        'Yağmurda otoban hızını düşürmek ve tek parça güvenli sürüş',
        'Sürücü değişimi olmadan 10 saat üstü sürüşten kaçınılmalı',
      ],
      opportunities: [
        'Gün doğumu saatinde çıkış ile sıcaklıktan avantaj',
        'Rahat bir geçiş için 6:30 sonrası şehir içi yoldan uzak durma',
      ],
      contingencies: [
        'Sınırda en az 1 saat bekleme olursa, Sofya yerine Dragalevtsi dışında 30 dk’lık bekleme molası',
        'Yakıtı %70’in altına düşmeden önce temin et',
      ],
      camp: {
        name: 'Camperisimo Caravan & Camper Park',
        place: 'Dragalevtsi, Sofya',
        contact: 'Kapasiteyi telefon ve mail ile teyit et',
        phone: '+359 888 677 676',
        email: 'info@camperisimo.com',
        link: 'https://www.google.com/maps/search/?api=1&query=Camperisimo+Caravan+Camper+Park+Sofia',
        reservationTemplate: 'Bugün 1 gece, elektrikli kamp yeri, duş ve temizlik mümkün mü? 18:00–20:00 varış var.',
        note: 'Şehir kenarında kalmak, bir sonraki günü yüksek tempo olmadan geçirmeye yardım eder.',
      },
      stops: [
        { type: 'Petrol', name: 'Shell Kapıkule çevresi', note: 'Sınır öncesi tam depo, tuvalet, su/atıştırmalık.' , mapUrl: 'https://www.google.com/maps/search/?api=1&query=Shell+Kapikule', estimatedMinutes: 25 },
        { type: 'Kahve', name: 'Haskovo istasyonu', note: 'Ruhsal molada 20 dakika. Kısa mola, yüz ifadesi kontrolü.' , mapUrl: 'https://www.google.com/maps/search/?api=1&query=coffee+station+Haskovo', estimatedMinutes: 20 },
        { type: 'Görülecek', name: 'Vitosha manzarası', note: 'İç mekanda kısa nefeslenme için kısa bir anlık tur.' , mapUrl: 'https://www.google.com/maps/search/?api=1&query=Vitosha+Sofia', estimatedMinutes: 15 },
      ],
      route: 'https://www.google.com/maps/dir/?api=1&origin=Istanbul%2CTurkey&destination=Sofia%2CBulgaria',
      routeEmbed: 'https://www.google.com/maps/?output=embed&f=d&daddr=Sofia,+Bulgaria&saddr=Istanbul,+Turkey',
      trafficEmbed: 'https://www.google.com/maps?output=embed&mode=driving&ttype=dep&f=d&daddr=Sofia,+Bulgaria&saddr=Istanbul,+Turkey',
      trafficLabel: 'Sınır trafiği + otoyol akışı',
      cityCameras: [
        { title: 'İstanbul canlı yol durumu', url: 'https://www.ibb.gov.tr/tr/icerik/360-canli-tesisat', source: 'İBB', kind: 'web' },
        { title: 'Sofya şehir merkezi kamera', url: 'https://www.youtube-nocookie.com/embed/JbDs24AgrJs', source: 'YouTube', kind: 'video' },
      ],
    },
    {
      id: '02',
      slug: 'sofya-bukres',
      date: '4 Ağustos · Salı',
      origin: 'Sofya',
      destination: 'Bükreş Güney',
      distanceKm: '440–470 km',
      duration: '7–8 saat',
      fuel: '55–65 L · €80–100',
      risks: [
        'Ruse–Varna aksında tır trafiği nedeniyle dalgalı hız',
        'Gece görüş açısında yorgunluk artışı',
      ],
      opportunities: [
        'Pleven ve Ruse arasında dinlenme noktaları düzenli',
        'Trafik akışı 17:00 sonrası kötüleşirse varış penceresi esnetilebilir',
      ],
      contingencies: [
        'Bükreş çevresinde kamp teyidi gecikirse alternatif olarak Giurgiu bandını kullan',
        'Öğleden sonra yağmurda sürüş yavaşıtılabilir',
      ],
      camp: {
        name: 'Bükreş güney kamp hedefi',
        place: 'Bükreş Güney çevresi',
        contact: 'Kapasite ve elektrik bağlantısı teyidi tek gün önceden yapılmalı',
        phone: 'N/A',
        email: 'kamp@bucamp.ro',
        link: 'https://www.google.com/maps/search/?api=1&query=camping+south+Bucharest',
        reservationTemplate: 'Bugün geceleme ve araç park alanı (karavan için) var mı? Kapalı depo ve duş imkanı var mı?',
        note: 'Kente girişin gürültüsünü aşmak için kampı ana arterden uzak seç.',
      },
      stops: [
        { type: 'Petrol', name: 'OMV Sofya çıkışı', note: 'Romanya geçişinden önce güvenli tank.' , mapUrl: 'https://www.google.com/maps/search/?api=1&query=OMV+Sofia', estimatedMinutes: 20 },
        { type: 'Kahve', name: 'Pleven dinlenme alanı', note: 'Sürücü odaklanma dönüşü için molaya 20 dk.' , mapUrl: 'https://www.google.com/maps/search/?api=1&query=coffee+Pleven+rest+area', estimatedMinutes: 20 },
        { type: 'Görülecek', name: 'Ruse Tuna kıyısı', note: 'Fotoğraf molası (hızlı geçiş).' , mapUrl: 'https://www.google.com/maps/search/?api=1&query=Danube+Ruse', estimatedMinutes: 15 },
      ],
      route: 'https://www.google.com/maps/dir/?api=1&origin=Sofia%2CBulgaria&destination=Bucharest%2CRomania',
      routeEmbed: 'https://www.google.com/maps/?output=embed&f=d&daddr=South+Bucharest,+Romania&saddr=Sofia,+Bulgaria',
      trafficEmbed: 'https://www.google.com/maps?output=embed&mode=driving&f=d&daddr=South+Bucharest,+Romania&saddr=Sofia,+Bulgaria',
      trafficLabel: 'Sofya–Bükreş aksında anlık trafik',
      cityCameras: [
        { title: 'Şehir ana yol kamera seti', url: 'https://www.webcambg.com/sofia2.html', source: 'Sofya', kind: 'web' },
        { title: 'Ruşey / Ruse geçiş görüntüsü', url: 'https://www.youtube.com/embed/aqkZ9v8Y5Q8', source: 'YouTube', kind: 'video' },
      ],
    },
    {
      id: '03',
      slug: 'bukres-deva',
      date: '5 Ağustos · Çarşamba',
      origin: 'Bükreş Güney',
      destination: 'Deva',
      distanceKm: '430–450 km',
      duration: '7–8 saat',
      fuel: '55–65 L · €80–100',
      risks: [
        'Olt Vadisi virajlarında ağır yük etkisi artar',
        'Yağmurda yol işaretleri daha hızlı kaybolur',
      ],
      opportunities: [
        'Deva öncesi küçük mola alanları düzenli',
        'Motosiklet trafiği dalgalı; takip mesafesi artırılmalı',
      ],
      contingencies: [
        'Kamp kapasitesi dolu ise Deva merkez dışı alternatif kamp alanları aktif.',
        'Yol kenarı arıza ihtimaline karşı karavan elektrik bağlantısı kontrol listesi tekrar.',
      ],
      camp: {
        name: 'Deva kamp alanı',
        place: 'Deva çevresi',
        contact: 'Aynı gün rezerve edilmesi önerilir',
        phone: 'N/A',
        email: 'rezervare@deva-camp.ro',
        link: 'https://www.google.com/maps/search/?api=1&query=camping+Deva+Romania',
        reservationTemplate: 'Deva’da 1 gece karavan dolabı ve elektrikli park uygun mu? Rezervasyon teyidi rica edilir.',
        note: 'Erken varış: geceyi düzenli geçirir, araç kontrolüne 1 saat ek süre bırakır.',
      },
      stops: [
        { type: 'Petrol', name: 'Pitești geçişi', note: 'Yolun kritik eğimini geçmeden önce yakıt kontrolü.' , mapUrl: 'https://www.google.com/maps/search/?api=1&query=petrol+station+Pitesti', estimatedMinutes: 20 },
        { type: 'Kahve', name: 'Călimănești', note: 'Düşük ritimden sonra kısa mola.' , mapUrl: 'https://www.google.com/maps/search/?api=1&query=C%C4%83lim%C4%83ne%C8%99ti+coffee', estimatedMinutes: 20 },
        { type: 'Görülecek', name: 'Corvin Kalesi', note: 'Zaman varsa kısa fotoğraf molası.' , mapUrl: 'https://www.google.com/maps/search/?api=1&query=Corvin+Castle', estimatedMinutes: 15 },
      ],
      route: 'https://www.google.com/maps/dir/?api=1&origin=Bucharest%2CRomania&destination=Deva%2CRomania',
      routeEmbed: 'https://www.google.com/maps/?output=embed&f=d&daddr=Deva,+Romania&saddr=South+Bucharest,+Romania',
      trafficEmbed: 'https://www.google.com/maps?output=embed&mode=driving&f=d&daddr=Deva,+Romania&saddr=South+Bucharest,+Romania',
      trafficLabel: 'Olt Vadisi arazi ve trafik durumu',
      cityCameras: [
        { title: 'Deva şehir merkezi', url: 'https://www.livecamromania.ro/live-webcam-deva-camera-live-din-deva-romania/', source: 'Romanya', kind: 'web' },
      ],
    },
    {
      id: '04',
      slug: 'deva-budapest',
      date: '6 Ağustos · Perşembe',
      origin: 'Deva',
      destination: 'Budapeşte',
      distanceKm: '280–320 km',
      duration: '5–6 saat',
      fuel: '38–48 L · €60–75',
      risks: [
        'Ara geçişlerde yük dengesi değişimine bağlı rüzgâr etkisi',
        'Sınır dışı kısa şehir girişi sırasında yavaşlama',
      ],
      opportunities: [
        'Daha kısa gün, kamp giriş belgeleri ve elektrik kontrolünü rahatça yapmak için ideal',
        'Tuna hattında 20 dakikalık bir mola, yorgunluğu keser',
      ],
      contingencies: [
        'Kamp teklifi geçikirse Budapeşte içinde geceleme planı yedeklenir.',
        'Zorunlu ikincil plan: Arad çevresinde erken konaklama.',
      ],
      camp: {
        name: 'Camping Budapest Arena',
        place: 'Budapeşte',
        contact: 'Önceden teyit edilmeden geceleme planını kilitleme.',
        phone: '+36 30 296 9129',
        email: 'info@budapestcamping.hu',
        link: 'https://www.google.com/maps/search/?api=1&query=Camping+Budapest+Arena',
        reservationTemplate: 'Günümüz, elektrik, duş, atık su yönetimi ve giriş saati teyidi rica edilir.',
        note: 'Kısa gün nedeniyle dinlenme ve vites ayarı için en temiz seçenek.',
      },
      stops: [
        { type: 'Petrol', name: 'Arad çevresi', note: 'Macaristan geçişinden önce tam depoya yaklaş.' , mapUrl: 'https://www.google.com/maps/search/?api=1&query=petrol+station+Arad', estimatedMinutes: 20 },
        { type: 'Kahve', name: 'Szeged', note: '10–15 dakikalık mola.' , mapUrl: 'https://www.google.com/maps/search/?api=1&query=coffee+Szeged', estimatedMinutes: 15 },
        { type: 'Görülecek', name: 'Tisza kıyısı', note: 'Geceye geçmeden kısa manzara molası.' , mapUrl: 'https://www.google.com/maps/search/?api=1&query=Tisza+Szeged', estimatedMinutes: 15 },
      ],
      route: 'https://www.google.com/maps/dir/?api=1&origin=Deva%2CRomania&destination=Budapest%2CHungary',
      routeEmbed: 'https://www.google.com/maps/?output=embed&f=d&daddr=Budapest,+Hungary&saddr=Deva,+Romania',
      trafficEmbed: 'https://www.google.com/maps?output=embed&mode=driving&f=d&daddr=Budapest,+Hungary&saddr=Deva,+Romania',
      trafficLabel: 'Deva–Budapeşte girişi ve otoyol akışı',
      cityCameras: [
        { title: 'Budapeşte şehir kamera noktası', url: 'https://www.victoria.hu/webcam', source: 'Victória Hotel kameraları', kind: 'web' },
      ],
    },
    {
      id: '05',
      slug: 'budapest-dinlenme',
      date: '7 Ağustos · Cuma',
      origin: 'Budapeşte',
      destination: 'Budapeşte',
      distanceKm: 'Sürüş yok',
      duration: 'Dinlenme ve sistem güncelleme',
      fuel: 'Yakıt alma gerekmiyor',
      risks: ['Yüksek hızdayken kısa mesafe planlama yapılmaması', 'Şehir içinde parklama zorluğu'],
      opportunities: ['Sistem kontrolleri için zaman avantajı', 'Ertesi uzun gün için sürücü ritmini optimize etme'],
      contingencies: ['Sadece acil ihtiyaç olursa kısa yerel tur; uzun yolculuk değil'],
      camp: {
        name: 'Camping Budapest Arena',
        place: 'Budapeşte',
        contact: 'Dönüş planı için konukhane teyidi yapılabilir',
        phone: '+36 30 296 9129',
        email: 'info@budapestcamping.hu',
        link: 'https://www.google.com/maps/search/?api=1&query=Camping+Budapest+Arena',
        reservationTemplate: 'Bugün sadece konaklama onayı ve kamp elektrik şalterleri kontrol edilmeli.',
        note: 'Aynı kampın korunması yükü ve yorgunluğu düşürür.',
      },
      stops: [
        { type: 'Tedarik', name: 'Büyük market', note: 'Su, filtreli içecek, çocuk atıştırmalıkları.' , mapUrl: 'https://www.google.com/maps/search/?api=1&query=hypermarket+Budapest', estimatedMinutes: 25 },
        { type: 'Kahve', name: 'Budapeşte şehir merkezi', note: 'Kısa yürüyüş + dinlenme.' , mapUrl: 'https://www.google.com/maps/search/?api=1&query=coffee+Budapest', estimatedMinutes: 20 },
        { type: 'Görülecek', name: 'Parlamento çevresi', note: 'Tuna kıyısı gezisi ve stres yönetimi.' , mapUrl: 'https://www.google.com/maps/search/?api=1&query=Hungarian+Parliament+Building', estimatedMinutes: 30 },
      ],
      route: 'https://www.google.com/maps/search/?api=1&query=Budapest',
      routeEmbed: 'https://www.google.com/maps/?output=embed&q=Budapest',
      trafficEmbed: 'https://www.google.com/maps/embed?pb=!1m0!3m2!1str!2s!4v1710000000000!6m8!1m7!1s0x0%3A0x0!2m2!1d47.4979!2d19.0402',
      trafficLabel: 'Şehir içi trafik',
      cityCameras: [
        { title: 'Budapeşte şehir trafiği', url: 'https://www.norbi.hu/cities/cameras/hungary/budapest', source: 'Buda trafiği', kind: 'web' },
      ],
    },
    {
      id: '06',
      slug: 'budapest-katowice',
      date: '8 Ağustos · Cumartesi',
      origin: 'Budapeşte',
      destination: 'Katowice',
      distanceKm: '570–600 km',
      duration: '9–10 saat',
      fuel: '72–84 L · €110–130',
      risks: [
        'Uzun ve yoğun bir gün, dikkat dağıtıcı hava koşullarına dikkat',
        'Pencere sislenmesi/klima yönetimi yorgunluk yaratabilir',
      ],
      opportunities: [
        'Günün ana avantajı: Polonya girişindeki ilk kamp hedefini erken alabilirsin',
        'Olomouc, Brno ve Zlín çevresi dinlenmeye uygun geçiş noktaları sağlar',
      ],
      contingencies: [
        'Seyrüseferde alternatif rota: Varşova doğusuna kaydırarak trafikten kaçınma',
        'Aşırı hava dalgalanmasında Katowice gününü en geç 2 saat geciktirme planı',
      ],
      camp: {
        name: 'Camping 215 MOSiR',
        place: 'Trzech Stawów 23, Katowice',
        contact: 'Rezervasyon ve elektrik + temizlik durumu teyit edilmeli',
        phone: '+48 32 256 59 39',
        email: 'camping@mosir.katowice.pl',
        link: 'https://www.google.com/maps/search/?api=1&query=Camping+215+Katowice',
        reservationTemplate: 'Bugün geçiş sonrası 1 gece, göl kenarı kamp yeri ve duş durumu teyidi rica edilir.',
        note: 'Şehrin içinde olsa da erişimi güçlü; planlı inmek iyi olur.',
      },
      stops: [
        { type: 'Petrol', name: 'Brno çevresi', note: 'Yarım depo kontrolü, hızlı mola.' , mapUrl: 'https://www.google.com/maps/search/?api=1&query=petrol+station+Brno', estimatedMinutes: 20 },
        { type: 'Kahve', name: 'Olomouc dinlenme alanı', note: 'Ara mola ile sürücü odaklanmayı koru.' , mapUrl: 'https://www.google.com/maps/search/?api=1&query=rest+area+Olomouc', estimatedMinutes: 20 },
        { type: 'Görülecek', name: 'Katowice göl hattı', note: 'Akşam öncesi kısa yürüyüş' , mapUrl: 'https://www.google.com/maps/search/?api=1&query=Dolina+Trzech+Stawow', estimatedMinutes: 25 },
      ],
      route: 'https://www.google.com/maps/dir/?api=1&origin=Budapest%2CHungary&destination=Katowice%2CPoland',
      routeEmbed: 'https://www.google.com/maps/?output=embed&f=d&daddr=Katowice,+Poland&saddr=Budapest,+Hungary',
      trafficEmbed: 'https://www.google.com/maps?output=embed&mode=driving&f=d&daddr=Katowice,+Poland&saddr=Budapest,+Hungary',
      trafficLabel: 'Uzun yol segmenti anlık akış',
      cityCameras: [
        { title: 'Katowice şehir kameraları', url: 'https://katowice.webcamera.pl/', source: 'Katowice Belediyesi', kind: 'web' },
      ],
    },
    {
      id: '07',
      slug: 'katowice-suwalki',
      date: '9 Ağustos · Pazar',
      origin: 'Katowice',
      destination: 'Suwałki',
      distanceKm: '550–580 km',
      duration: '8–9 saat',
      fuel: '70–82 L · €105–125',
      risks: ['Varşova aksında yoğunluk; trafik saatinde rüzgar etkili park', 'Hava açıldığında uzun doğrusal sürüş dikkatini düşürebilir'],
      opportunities: ['Polonya–Litvanya hattında dinlenme alanları makul', 'Gece geçişi gerektirmeyecek şekilde rota planlanabilir'],
      contingencies: ['Gece sürüşü kaçınılmalı; gerekiyorsa ikinci güvenli durak eklenir'],
      camp: {
        name: 'Suwałki kamp hedefi',
        place: 'Suwałki çevresi',
        contact: 'Günün içinde teyit edilmesi kritik',
        phone: 'N/A',
        email: 'reservations@suwalki-camp.pl',
        link: 'https://www.google.com/maps/search/?api=1&query=camping+Suwalki+Poland',
        reservationTemplate: 'Riga’dan önceki stratejik güvenlik molası için 1 gece mümkün mü? Elektrik ve temizlik durumu isterim.',
        note: 'Baltık hattına girmeden önce ritmi düşürmek için ideal gece.',
      },
      stops: [
        { type: 'Petrol', name: 'Łódź çevresi', note: 'Varşova öncesi güvenli yakıt aralığı.' , mapUrl: 'https://www.google.com/maps/search/?api=1&query=petrol+station+Lodz', estimatedMinutes: 20 },
        { type: 'Kahve', name: 'Varşova kuzeyi', note: 'Trafik kararından önce kısa dinlenme.' , mapUrl: 'https://www.google.com/maps/search/?api=1&query=coffee+Warsaw+north', estimatedMinutes: 20 },
        { type: 'Görülecek', name: 'Masurya Gölleri', note: 'Kısa fotoğraf molası için düşük zaman kaybı.' , mapUrl: 'https://www.google.com/maps/search/?api=1&query=Masurian+Lakes', estimatedMinutes: 15 },
      ],
      route: 'https://www.google.com/maps/dir/?api=1&origin=Katowice%2CPoland&destination=Suwalki%2CPoland',
      routeEmbed: 'https://www.google.com/maps/?output=embed&f=d&daddr=Suwalki,+Poland&saddr=Katowice,+Poland',
      trafficEmbed: 'https://www.google.com/maps?output=embed&mode=driving&f=d&daddr=Suwalki,+Poland&saddr=Katowice,+Poland',
      trafficLabel: 'Varşova çevresi ve kuzey hattı trafiği',
      cityCameras: [
        { title: 'Suwalki belediye kameraları', url: 'https://live.um.suwalki.pl/live/', source: 'Suwałki Belediyesi', kind: 'web' },
      ],
    },
    {
      id: '08',
      slug: 'suwalki-riga',
      date: '10 Ağustos · Pazartesi',
      origin: 'Suwałki',
      destination: 'Riga',
      distanceKm: '360–390 km',
      duration: '5–6 saat',
      fuel: '45–55 L · €70–85',
      risks: ['Baltık rotasında son bölümde hızlı ritim baskısı', 'Son 90 km içinde yorgunluk nedeniyle “bitmişiz” hissi'],
      opportunities: ['Riga’ya varışta doğrudan planların uygulanabilirliği yüksek', 'Matrožu civarı doğrudan kamp erişimi'],
      contingencies: ['Geceye yakınsa Kaunas/eyalet parkı alternatiflerinde kısa gecikmeye izin ver'],
      camp: {
        name: 'Camping Yachts',
        place: 'Matrožu iela 7a, Riga',
        contact: '+371 29205543 · info@campingyachts.lv',
        phone: '+371 29205543',
        email: 'info@campingyachts.lv',
        link: 'https://www.google.com/maps/search/?api=1&query=Camping+Yachts+Riga',
        reservationTemplate: 'Riga varışı için 1 gece, elektrikli kamp ve atık su bağlantısı teyidi rica edilir.',
        note: 'Varış sonrası kurulum basit, su ve elektrik hızlıca devreye alınır.',
      },
      stops: [
        { type: 'Petrol', name: 'Kaunas çevresi', note: 'Letonya’dan önce acil yakıt tamponu.' , mapUrl: 'https://www.google.com/maps/search/?api=1&query=petrol+station+Kaunas', estimatedMinutes: 20 },
        { type: 'Kahve', name: 'Panevėžys', note: 'Son sakin mola.' , mapUrl: 'https://www.google.com/maps/search/?api=1&query=coffee+Panevezys', estimatedMinutes: 20 },
        { type: 'Görülecek', name: 'Riga A7 yaklaşımı', note: 'Rutin geçiş ve varış ritmini test et.' , mapUrl: 'https://www.google.com/maps/search/?api=1&query=Riga+A7', estimatedMinutes: 20 },
      ],
      route: 'https://www.google.com/maps/dir/?api=1&origin=Suwalki%2CPoland&destination=Riga%2CLatvia',
      routeEmbed: 'https://www.google.com/maps/?output=embed&f=d&daddr=Riga,+Latvia&saddr=Suwalki,+Poland',
      trafficEmbed: 'https://www.google.com/maps?output=embed&mode=driving&f=d&daddr=Riga,+Latvia&saddr=Suwalki,+Poland',
      trafficLabel: 'Riga yaklaşımı ve Baltık koridoru',
      cityCameras: [
        { title: 'Riga şehir görüntüsü', url: 'https://rus.lsm.lv/webcam-riga/lnb-eka/', source: 'Riga belediye', kind: 'web' },
      ],
    },
  ],
};
