import '../models/destination.dart';
import '../models/tour.dart';
import '../models/tour_category.dart';

// Photos come from the Unsplash and Pexels CDNs (free licenses). The app shows
// a local gradient fallback whenever one of them fails to load.
String _unsplash(String photoId) =>
    'https://images.unsplash.com/photo-$photoId?fm=jpg&fit=crop&w=1200&q=75';

String _pexels(int photoId) =>
    'https://images.pexels.com/photos/$photoId/pexels-photo-$photoId.jpeg'
    '?auto=compress&cs=tinysrgb&w=1200';

const _mon = DateTime.monday;
const _tue = DateTime.tuesday;
const _wed = DateTime.wednesday;
const _thu = DateTime.thursday;
const _fri = DateTime.friday;
const _sat = DateTime.saturday;
const _sun = DateTime.sunday;
const _daily = [_mon, _tue, _wed, _thu, _fri, _sat, _sun];

final List<Tour> mockTours = List.unmodifiable([
  // Turkey
  Tour(
    id: 'tr-cappadocia-balloons',
    title: 'Cappadocia Hot Air Balloons & Cave Hotel Escape',
    destination: Destination.turkey,
    location: 'Göreme, Cappadocia',
    category: TourCategory.adventure,
    price: 890,
    durationDays: 4,
    rating: 4.9,
    reviewCount: 1284,
    imageUrl: _unsplash('1641128324972-af3212f0f6bd'),
    description:
        'Float over fairy chimneys at sunrise, sleep in a restored cave hotel '
        'and explore the rock-cut churches of the Göreme Open Air Museum. '
        'Evenings are free for pottery workshops in Avanos or a sunset ride '
        'through Love Valley.',
    highlights: [
      'Sunrise hot air balloon flight with champagne toast',
      'Göreme Open Air Museum and Uçhisar Castle',
      'Derinkuyu underground city',
      'Sunset horseback ride through Love Valley',
    ],
    included: [
      '3 nights in a cave hotel with breakfast',
      'Balloon flight and flight certificate',
      'Airport transfers from Kayseri or Nevşehir',
      'Licensed English-speaking guide',
    ],
    maxGroupSize: 12,
    languages: ['English', 'Turkish', 'Russian'],
    departureWeekdays: [_mon, _thu, _sat],
  ),
  Tour(
    id: 'tr-istanbul-bosphorus',
    title: 'Istanbul: Bazaars, Bosphorus & Byzantine Wonders',
    destination: Destination.turkey,
    location: 'Istanbul',
    category: TourCategory.city,
    price: 640,
    durationDays: 5,
    rating: 4.8,
    reviewCount: 2140,
    imageUrl: _unsplash('1524231757912-21f4fe3a7200'),
    description:
        'Five days across two continents: the Hagia Sophia and Blue Mosque, '
        'the spice-scented lanes of the Grand Bazaar, a sunset cruise on the '
        'Bosphorus and a food walk through Kadıköy on the Asian side.',
    highlights: [
      'Hagia Sophia, Blue Mosque and Topkapı Palace',
      'Grand Bazaar and Spice Bazaar with a local guide',
      'Sunset Bosphorus cruise',
      'Kadıköy street food tasting',
    ],
    included: [
      '4 nights in a boutique hotel in Sultanahmet',
      'Museum entry tickets',
      'Bosphorus cruise',
      'Istanbulkart transit card',
    ],
    maxGroupSize: 16,
    languages: ['English', 'Turkish'],
    departureWeekdays: [_tue, _fri, _sun],
  ),
  Tour(
    id: 'tr-pamukkale-ephesus',
    title: 'Pamukkale Travertines & Ancient Ephesus',
    destination: Destination.turkey,
    location: 'Denizli & Selçuk',
    category: TourCategory.culture,
    price: 520,
    durationDays: 3,
    rating: 4.6,
    reviewCount: 864,
    imageUrl: _pexels(29800608),
    description:
        'Walk barefoot across the white calcium terraces of Pamukkale, swim '
        'in Cleopatra\'s antique pool and stand before the Library of Celsus '
        'in Ephesus, one of the best-preserved Roman cities in the world.',
    highlights: [
      'Pamukkale terraces and Hierapolis ruins',
      'Swim in Cleopatra\'s antique pool',
      'Library of Celsus and the Great Theatre of Ephesus',
      'House of the Virgin Mary',
    ],
    included: [
      '2 nights in thermal spa hotels',
      'Breakfast and dinner daily',
      'All entrance fees',
      'Air-conditioned coach transport',
    ],
    maxGroupSize: 20,
    languages: ['English', 'German'],
    departureWeekdays: [_wed, _sat],
  ),
  Tour(
    id: 'tr-kas-turquoise-coast',
    title: 'Turquoise Coast: Kaş, Kaputaş Beach & Kekova',
    destination: Destination.turkey,
    location: 'Kaş, Antalya',
    category: TourCategory.beach,
    price: 760,
    durationDays: 6,
    rating: 4.3,
    reviewCount: 412,
    imageUrl: _unsplash('1593238739364-18cfde30e522'),
    description:
        'Slow days on the Lycian coast: swim at Kaputaş beach, kayak over the '
        'sunken city of Kekova and hike a stretch of the Lycian Way before '
        'dinner at a harbour-side meyhane in Kaş.',
    highlights: [
      'Sea kayaking over the Kekova sunken city',
      'Beach day at Kaputaş',
      'Guided hike on the Lycian Way',
      'Boat trip to Kastellorizo island',
    ],
    included: [
      '5 nights in a sea-view guesthouse',
      'Daily breakfast',
      'Kayak and boat trips',
      'Transfers from Antalya airport',
    ],
    maxGroupSize: 10,
    languages: ['English'],
    departureWeekdays: [_sat],
  ),

  // UAE
  Tour(
    id: 'ae-dubai-highlights',
    title: 'Dubai Highlights: Burj Khalifa & Old Souks',
    destination: Destination.uae,
    location: 'Dubai',
    category: TourCategory.city,
    price: 980,
    durationDays: 4,
    rating: 4.7,
    reviewCount: 1930,
    imageUrl: _unsplash('1512453979798-5ea266f8880c'),
    description:
        'From the 124th floor of the Burj Khalifa to an abra ride across Dubai '
        'Creek, see the city\'s two faces: glittering towers by day and the '
        'gold and spice souks of Deira by night.',
    highlights: [
      'At the Top, Burj Khalifa observation deck',
      'Abra ride across Dubai Creek',
      'Gold and Spice Souks in Deira',
      'Dubai Fountain show and Dubai Mall',
    ],
    included: [
      '3 nights in a 4-star Downtown hotel',
      'Burj Khalifa tickets',
      'Private airport transfers',
      'Half-day guided city tour',
    ],
    maxGroupSize: 14,
    languages: ['English', 'Arabic', 'Russian'],
    departureWeekdays: _daily,
  ),
  Tour(
    id: 'ae-desert-safari',
    title: 'Arabian Desert Safari & Bedouin Camp Night',
    destination: Destination.uae,
    location: 'Dubai Desert Conservation Reserve',
    category: TourCategory.adventure,
    price: 240,
    durationDays: 2,
    rating: 4.8,
    reviewCount: 2675,
    imageUrl: _pexels(19159167),
    description:
        'Dune bashing in a 4x4, a camel ride at golden hour and a night under '
        'the stars at a Bedouin-style camp with a barbecue dinner, henna and '
        'a tanoura show. Return to the city after sunrise coffee.',
    highlights: [
      'Dune bashing in a 4x4 with a certified driver',
      'Camel ride and sandboarding',
      'Barbecue dinner with live tanoura show',
      'Overnight in a private desert tent',
    ],
    included: [
      'Hotel pickup and drop-off in Dubai',
      'Dinner, breakfast and soft drinks',
      'Private tent with bedding',
      'Sandboard equipment',
    ],
    maxGroupSize: 8,
    languages: ['English', 'Arabic'],
    departureWeekdays: _daily,
  ),
  Tour(
    id: 'ae-abu-dhabi-day',
    title: 'Abu Dhabi: Grand Mosque & Louvre Day Trip',
    destination: Destination.uae,
    location: 'Abu Dhabi',
    category: TourCategory.culture,
    price: 180,
    durationDays: 1,
    rating: 4.6,
    reviewCount: 1102,
    imageUrl: _pexels(337904),
    description:
        'A full day in the capital: the white marble Sheikh Zayed Grand Mosque, '
        'the floating dome of the Louvre Abu Dhabi and a stop at Qasr Al Watan '
        'presidential palace, with lunch on Saadiyat Island.',
    highlights: [
      'Guided visit to Sheikh Zayed Grand Mosque',
      'Louvre Abu Dhabi entry',
      'Qasr Al Watan palace',
      'Lunch on Saadiyat Island',
    ],
    included: [
      'Return transport from Dubai',
      'Entrance tickets',
      'Lunch',
      'Professional guide',
    ],
    maxGroupSize: 16,
    languages: ['English', 'French', 'Arabic'],
    departureWeekdays: [_tue, _thu, _sat, _sun],
  ),

  // Thailand
  Tour(
    id: 'th-phi-phi-islands',
    title: 'Phi Phi Islands & Maya Bay Speedboat Tour',
    destination: Destination.thailand,
    location: 'Phuket & Krabi',
    category: TourCategory.beach,
    price: 150,
    durationDays: 1,
    rating: 4.4,
    reviewCount: 3120,
    imageUrl: _unsplash('1504214208698-ea1916a2195a'),
    description:
        'An early start by speedboat beats the crowds to Maya Bay, followed '
        'by snorkelling at Pileh Lagoon, Monkey Beach and a Thai lunch on '
        'Phi Phi Don before returning to Phuket in the afternoon.',
    highlights: [
      'Early access to Maya Bay',
      'Snorkelling at Pileh Lagoon',
      'Monkey Beach and Viking Cave',
      'Thai buffet lunch on Phi Phi Don',
    ],
    included: [
      'Hotel transfers in Phuket',
      'Snorkel gear and life jackets',
      'Lunch, fruit and drinking water',
      'National park fees',
    ],
    maxGroupSize: 30,
    languages: ['English', 'Thai'],
    departureWeekdays: _daily,
  ),
  Tour(
    id: 'th-bangkok-street-food',
    title: 'Bangkok Temples & Street Food Weekend',
    destination: Destination.thailand,
    location: 'Bangkok',
    category: TourCategory.city,
    price: 410,
    durationDays: 3,
    rating: 4.7,
    reviewCount: 1850,
    imageUrl: _unsplash('1508009603885-50cf7c579365'),
    description:
        'Gilded temples by day, sizzling woks by night. See the Grand Palace '
        'and Wat Arun, ride a longtail through the Thonburi canals and eat '
        'your way through Yaowarat, Bangkok\'s Chinatown, after dark.',
    highlights: [
      'Grand Palace, Wat Pho and Wat Arun',
      'Longtail boat through the Thonburi canals',
      'Chinatown street food night walk',
      'Rooftop bar at sunset',
    ],
    included: [
      '2 nights on the riverside',
      'Street food tasting (12+ dishes)',
      'Temple entry fees',
      'Tuk-tuk and boat transfers',
    ],
    maxGroupSize: 12,
    languages: ['English', 'Thai'],
    departureWeekdays: [_fri],
  ),
  Tour(
    id: 'th-chiang-mai-temples',
    title: 'Chiang Mai Temples & Ethical Elephant Sanctuary',
    destination: Destination.thailand,
    location: 'Chiang Mai',
    category: TourCategory.culture,
    price: 560,
    durationDays: 5,
    rating: 4.9,
    reviewCount: 976,
    imageUrl: _unsplash('1528181304800-259b08848526'),
    description:
        'Northern Thailand at an easy pace: golden Doi Suthep, a cooking class '
        'with a market visit, a day with rescued elephants at a no-riding '
        'sanctuary and the Sunday Walking Street market.',
    highlights: [
      'Wat Phra That Doi Suthep at sunrise',
      'Full day at an ethical elephant sanctuary',
      'Thai cooking class with market tour',
      'Sunday Walking Street market',
    ],
    included: [
      '4 nights in an Old City boutique hotel',
      'Sanctuary visit with lunch',
      'Cooking class',
      'Airport transfers',
    ],
    maxGroupSize: 12,
    languages: ['English'],
    departureWeekdays: [_mon, _thu],
  ),
  Tour(
    id: 'th-khao-sok-krabi',
    title: 'Khao Sok Jungle Lake & Krabi Coast',
    destination: Destination.thailand,
    location: 'Khao Sok & Krabi',
    category: TourCategory.nature,
    price: 690,
    durationDays: 7,
    rating: 4.8,
    reviewCount: 640,
    imageUrl: _unsplash('1519451241324-20b4ea2c4220'),
    description:
        'Sleep in floating bungalows on Cheow Lan Lake, surrounded by '
        'limestone karsts and one of the oldest rainforests on Earth, then '
        'finish with three days of beaches and island hopping around Railay.',
    highlights: [
      'Two nights in floating raft houses on Cheow Lan Lake',
      'Jungle trek and cave exploration',
      'Railay Beach and Phra Nang Cave',
      'Four-island longtail tour',
    ],
    included: [
      '6 nights accommodation',
      'All meals at the lake',
      'Park fees and guided treks',
      'Transfers between Khao Sok and Krabi',
    ],
    maxGroupSize: 10,
    languages: ['English', 'German'],
    departureWeekdays: [_sun],
  ),

  // Maldives
  Tour(
    id: 'mv-overwater-villa',
    title: 'Overwater Villa Retreat in South Malé Atoll',
    destination: Destination.maldives,
    location: 'South Malé Atoll',
    category: TourCategory.beach,
    price: 3450,
    durationDays: 7,
    rating: 4.9,
    reviewCount: 512,
    imageUrl: _unsplash('1514282401047-d79a71a590e8'),
    description:
        'A week in an overwater villa with a private deck and steps straight '
        'into the lagoon. Mornings on the house reef, afternoons at the spa '
        'and one sunset dolphin cruise on a traditional dhoni.',
    highlights: [
      'Overwater villa with direct lagoon access',
      'House reef snorkelling with turtles',
      'Sunset dolphin cruise',
      'Couples spa treatment',
    ],
    included: [
      '6 nights, half board',
      'Return speedboat transfers from Malé',
      'Snorkel equipment',
      'One spa treatment per guest',
    ],
    maxGroupSize: 4,
    languages: ['English', 'Russian'],
    departureWeekdays: _daily,
  ),
  Tour(
    id: 'mv-maafushi-snorkel',
    title: 'Maafushi Snorkel Safari & Sandbank Picnic',
    destination: Destination.maldives,
    location: 'Maafushi, Kaafu Atoll',
    category: TourCategory.adventure,
    price: 1150,
    durationDays: 5,
    rating: 4.5,
    reviewCount: 388,
    imageUrl: _unsplash('1573843981267-be1999ff37cd'),
    description:
        'The Maldives on a guesthouse budget: snorkel with nurse sharks and '
        'manta rays, picnic on a deserted sandbank and spend a day pass at a '
        'luxury resort, all from the local island of Maafushi.',
    highlights: [
      'Snorkelling with nurse sharks and stingrays',
      'Manta ray point excursion',
      'Private sandbank picnic',
      'Resort day pass with lunch',
    ],
    included: [
      '4 nights in a beachfront guesthouse',
      'Breakfast and dinner',
      'Three boat excursions',
      'Public ferry and speedboat transfers',
    ],
    maxGroupSize: 10,
    languages: ['English'],
    departureWeekdays: [_mon, _wed, _fri],
  ),
  Tour(
    id: 'mv-baa-atoll-mantas',
    title: 'Baa Atoll Manta Season Island Escape',
    destination: Destination.maldives,
    location: 'Baa Atoll Biosphere Reserve',
    category: TourCategory.nature,
    price: 4290,
    durationDays: 8,
    rating: 4.8,
    reviewCount: 221,
    imageUrl: _unsplash('1540202404-a2f29016b523'),
    description:
        'Time your stay with manta season in a UNESCO biosphere reserve. '
        'Seaplane in, swim with feeding mantas at Hanifaru Bay and unwind on '
        'a quiet island with just a handful of villas.',
    highlights: [
      'Seaplane flight over the atolls',
      'Hanifaru Bay manta ray snorkel',
      'Marine biologist talks',
      'Private sandbank dinner',
    ],
    included: [
      '7 nights, full board',
      'Return seaplane transfers',
      'Two guided snorkel excursions',
      'Marine conservation fee',
    ],
    maxGroupSize: 6,
    languages: ['English', 'Italian'],
    departureWeekdays: [_sat],
  ),

  // Georgia
  Tour(
    id: 'ge-tbilisi-old-town',
    title: 'Tbilisi Old Town, Sulphur Baths & Wine Bars',
    destination: Destination.georgia,
    location: 'Tbilisi',
    category: TourCategory.city,
    price: 430,
    durationDays: 4,
    rating: 4.7,
    reviewCount: 905,
    imageUrl: _unsplash('1565008576549-57569a49371d'),
    description:
        'Wander the carved balconies of Old Tbilisi, soak in the domed sulphur '
        'baths of Abanotubani and taste amber qvevri wines with a sommelier. '
        'Includes a day trip to Mtskheta, Georgia\'s ancient capital.',
    highlights: [
      'Narikala Fortress by cable car',
      'Private sulphur bath session',
      'Natural wine tasting with a sommelier',
      'Day trip to Mtskheta and Jvari Monastery',
    ],
    included: [
      '3 nights in an Old Town boutique hotel',
      'Supra dinner with polyphonic singing',
      'Wine tasting',
      'Airport transfers',
    ],
    maxGroupSize: 14,
    languages: ['English', 'Russian', 'Georgian'],
    departureWeekdays: [_thu, _sun],
  ),
  Tour(
    id: 'ge-kazbegi-mountains',
    title: 'Kazbegi & Gergeti Trinity Church Mountain Trip',
    destination: Destination.georgia,
    location: 'Stepantsminda, Kazbegi',
    category: TourCategory.nature,
    price: 340,
    durationDays: 2,
    rating: 4.9,
    reviewCount: 1370,
    imageUrl: _pexels(16660047),
    description:
        'Drive the Georgian Military Highway past Ananuri fortress and the '
        'Gudauri viewpoint, then hike up to the 14th-century Gergeti Trinity '
        'Church beneath the glaciers of Mount Kazbek.',
    highlights: [
      'Georgian Military Highway road trip',
      'Ananuri fortress and Zhinvali reservoir',
      'Hike to Gergeti Trinity Church',
      'Russia-Georgia Friendship Monument',
    ],
    included: [
      '1 night in a mountain lodge',
      'Breakfast and dinner',
      'Return transport from Tbilisi',
      'Mountain guide',
    ],
    maxGroupSize: 12,
    languages: ['English', 'Russian'],
    departureWeekdays: [_tue, _sat],
  ),
  Tour(
    id: 'ge-svaneti-trek',
    title: 'Svaneti Trek: Mestia to Ushguli',
    destination: Destination.georgia,
    location: 'Mestia, Svaneti',
    category: TourCategory.adventure,
    price: 720,
    durationDays: 6,
    rating: 4.8,
    reviewCount: 296,
    imageUrl: _pexels(8934181),
    description:
        'A classic four-day hut-to-hut trek through the High Caucasus, from '
        'the stone defence towers of Mestia to Ushguli, one of the highest '
        'inhabited villages in Europe, sleeping in family guesthouses.',
    highlights: [
      'Four days of guided trekking',
      'Medieval Svan defence towers',
      'Chalaadi glacier hike',
      'Ushguli beneath Mount Shkhara',
    ],
    included: [
      '5 nights in family guesthouses',
      'All meals during the trek',
      'Luggage transfer between villages',
      'Certified mountain guide',
    ],
    maxGroupSize: 10,
    languages: ['English', 'Russian'],
    departureWeekdays: [_mon],
  ),

  // Uzbekistan
  Tour(
    id: 'uz-silk-road-classic',
    title: 'Silk Road Classic: Samarkand, Bukhara & Khiva',
    destination: Destination.uzbekistan,
    location: 'Samarkand · Bukhara · Khiva',
    category: TourCategory.culture,
    price: 1290,
    durationDays: 8,
    rating: 4.9,
    reviewCount: 684,
    imageUrl: _pexels(19473632),
    description:
        'Uzbekistan\'s three great Silk Road cities in one journey: the tiled '
        'madrasahs of the Registan, the trading domes of Bukhara and the '
        'walled inner city of Khiva, linked by high-speed train.',
    highlights: [
      'Registan Square and Shah-i-Zinda necropolis',
      'Bukhara old town and Kalon Minaret',
      'Itchan Kala walled city in Khiva',
      'Afrosiyob high-speed train journeys',
    ],
    included: [
      '7 nights in heritage hotels',
      'Daily breakfast and 3 dinners',
      'Train and domestic flight tickets',
      'Local guide in each city',
    ],
    maxGroupSize: 14,
    languages: ['English', 'Russian', 'Uzbek'],
    departureWeekdays: [_mon, _fri],
  ),
  Tour(
    id: 'uz-samarkand-weekend',
    title: 'Samarkand: Registan & Shah-i-Zinda Weekend',
    destination: Destination.uzbekistan,
    location: 'Samarkand',
    category: TourCategory.culture,
    price: 390,
    durationDays: 3,
    rating: 4.8,
    reviewCount: 512,
    imageUrl: _pexels(7417907),
    description:
        'A long weekend in the city of Amir Timur: the Registan at sunset, '
        'the turquoise avenue of tombs at Shah-i-Zinda, Bibi-Khanym Mosque '
        'and a visit to a paper mill in the Konigil village.',
    highlights: [
      'Registan Square at sunset and after dark',
      'Shah-i-Zinda and Gur-e-Amir mausoleums',
      'Siab Bazaar and Bibi-Khanym Mosque',
      'Silk paper workshop in Konigil',
    ],
    included: [
      '2 nights in a central hotel',
      'Plov lunch at a local home',
      'All entry tickets',
      'Train tickets from Tashkent',
    ],
    maxGroupSize: 16,
    languages: ['English', 'Russian'],
    departureWeekdays: [_fri, _sat],
  ),
  Tour(
    id: 'uz-bukhara-desert-yurt',
    title: 'Bukhara Old City & Kyzylkum Desert Yurt Stay',
    destination: Destination.uzbekistan,
    location: 'Bukhara & Kyzylkum Desert',
    category: TourCategory.culture,
    price: 560,
    durationDays: 4,
    rating: 4.7,
    reviewCount: 318,
    imageUrl: _pexels(19439118),
    description:
        'Explore Bukhara\'s 2,000-year-old centre, from the Ark fortress to '
        'Lyabi-Hauz pond, then head into the Kyzylkum desert for a night in '
        'a yurt camp by Aydarkul Lake with camel rides and a campfire.',
    highlights: [
      'Po-i-Kalyan complex and Kalon Minaret',
      'Ark fortress and the trading domes',
      'Night in a yurt camp in the Kyzylkum desert',
      'Swim in Aydarkul Lake',
    ],
    included: [
      '2 nights in Bukhara, 1 night in a yurt',
      'Breakfast daily, dinner at the camp',
      'Camel ride',
      '4x4 transfers',
    ],
    maxGroupSize: 12,
    languages: ['English', 'Russian', 'French'],
    departureWeekdays: [_wed, _sun],
  ),
]);
