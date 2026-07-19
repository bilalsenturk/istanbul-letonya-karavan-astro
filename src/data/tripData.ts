import rawData from './tripData.json';

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
  phone?: string | null;
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
  kind?: 'video' | 'web' | 'image';
  openUrl?: string;
  refreshSeconds?: number;
  note?: string;
};

type CountryGuide = {
  slug: string;
  country: string;
  population: string;
  language: string;
  currency: string;
  religion: string;
  traffic: string;
  profile: string;
  highlights: string[];
  highlightsAdvice: string;
  importantStops: string[];
  shopping: string;
  shoppingAdvice?: string;
  coffeeFood?: string;
  roadNote?: string;
};

type SegmentGuide = {
  segment: string;
  from: string;
  to: string;
  highlights: string[];
  netComment: string;
};

type CoffeeStrategy = {
  title: string;
  coffeeStops: string[];
  foodPattern: string[];
};

type MealStrategy = {
  title: string;
  items: string[];
};

type CampLogic = {
  title: string;
  items: Array<{
    city: string;
    primary: string;
    alternative: string;
    advantages: string;
    disadvantages: string;
  }>;
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
  countryGuides: CountryGuide[];
  segmentGuides: SegmentGuide[];
  coffeeStrategy: CoffeeStrategy;
  mealStrategy: MealStrategy;
  campLogic: CampLogic;
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

export const tripData: TripData = rawData as TripData;
