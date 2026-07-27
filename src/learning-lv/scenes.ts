export interface ScenePlan {
  id: string;
  index: number;
  title: string;
  /** Üretim istemine giren, sahnenin ne kapsadığını anlatan tek cümle. */
  brief: string;
  /** Sahnede kesinlikle bulunması gereken kelimeler. */
  seedWords: string[];
}

export const SCENE_PLAN: readonly ScenePlan[] = [
  {
    id: 'lv-s01-tanisma',
    index: 1,
    title: 'Tanışma',
    brief: 'Selamlaşma, kendini tanıtma, evet/hayır, teşekkür ve rica.',
    seedWords: ['sveiki', 'labdien', 'paldies', 'lūdzu', 'jā', 'nē', 'es', 'mani sauc'],
  },
  {
    id: 'lv-s02-sayilar',
    index: 2,
    title: 'Sayılar ve fiyat',
    brief: '0-100 arası sayılar, fiyat sorma, pahalı/ucuz, para birimi.',
    seedWords: ['viens', 'divi', 'trīs', 'desmit', 'simts', 'cik maksā', 'eiro', 'dārgi', 'lēti'],
  },
  {
    id: 'lv-s03-markette',
    index: 3,
    title: 'Markette',
    brief: 'Temel gıda alışverişi, istemek ve ihtiyaç belirtmek.',
    seedWords: ['maize', 'ūdens', 'piens', 'kafija', 'gribu', 'man vajag', 'veikals'],
  },
  {
    id: 'lv-s04-benzinlik',
    index: 4,
    title: 'Benzinlik ve yol',
    brief: 'Yakıt almak, yön sormak ve yön tarifini anlamak.',
    seedWords: ['degviela', 'pilnu bāku', 'kur ir', 'pa kreisi', 'pa labi', 'taisni', 'ceļš'],
  },
  {
    id: 'lv-s05-kamp',
    index: 5,
    title: 'Kamp alanı',
    brief: 'Konaklama yeri bulmak, süre ve müsaitlik sormak.',
    seedWords: ['telts', 'vieta', 'nakts', 'cik ilgi', 'vai ir brīvs', 'kempings'],
  },
  {
    id: 'lv-s06-yemek',
    index: 6,
    title: 'Yemek',
    brief: 'Restoranda sipariş, beğeni belirtme, hesap isteme, kısıtlar.',
    seedWords: ['ēst', 'dzert', 'garšīgs', 'rēķinu lūdzu', 'bez gaļas', 'zupa'],
  },
  {
    id: 'lv-s07-zaman',
    index: 7,
    title: 'Zaman',
    brief: 'Gün, saat, zaman aralığı ve randevu ifadeleri.',
    seedWords: ['šodien', 'rīt', 'vakar', 'pulksten', 'cikos', 'no', 'līdz'],
  },
  {
    id: 'lv-s08-hava',
    index: 8,
    title: 'Hava ve yol durumu',
    brief: 'Hava olayları, sıcaklık ve yol koşulları.',
    seedWords: ['lietus', 'sniegs', 'auksts', 'silts', 'slidens', 'vējš'],
  },
  {
    id: 'lv-s09-sinir',
    index: 9,
    title: 'Sınır ve belgeler',
    brief: 'Sınır geçişi, kimlik ve araç belgeleri, nereden geldiğini söyleme.',
    seedWords: ['pase', 'dokumenti', 'mašīna', 'no Turcijas', 'robeža'],
  },
  {
    id: 'lv-s10-yardim',
    index: 10,
    title: 'Yardım ve acil',
    brief: 'Yardım istemek, sağlık sorunu anlatmak, acil kurumlar.',
    seedWords: ['palīdziet', 'ārsts', 'slimnīca', 'man sāp', 'policija', 'aptieka'],
  },
  {
    id: 'lv-s11-sohbet',
    index: 11,
    title: 'Sohbet',
    brief: 'Hâl hatır sormak, nereli olduğunu söylemek, beğeni belirtmek.',
    seedWords: ['kā tev iet', 'no kurienes', 'patīk', 'ļoti', 'labi'],
  },
  {
    id: 'lv-s12-veda',
    index: 12,
    title: 'Kibarlık ve veda',
    brief: 'Özür dileme, vedalaşma ve kibar kapanış ifadeleri.',
    seedWords: ['atvainojiet', 'uz redzēšanos', 'ar prieku', 'nekas', 'čau'],
  },
];
