import 'package:hugeicons/hugeicons.dart';

typedef HugeIconData = List<List<dynamic>>;

/// Kunci ikon yang disimpan di database -> ikon Hugeicons.
/// Disimpan sebagai string supaya aman disinkronkan & tidak bergantung versi paket.
const Map<String, HugeIconData> categoryIcons = {
  'food': HugeIcons.strokeRoundedRestaurant01,
  'coffee': HugeIcons.strokeRoundedCoffee02,
  'groceries': HugeIcons.strokeRoundedShoppingCart01,
  'transport': HugeIcons.strokeRoundedCar01,
  'taxi': HugeIcons.strokeRoundedTaxi,
  'bus': HugeIcons.strokeRoundedBus01,
  'home': HugeIcons.strokeRoundedHome11,
  'bills': HugeIcons.strokeRoundedInvoice01,
  'internet': HugeIcons.strokeRoundedWifi01,
  'phone': HugeIcons.strokeRoundedSmartPhone01,
  'health': HugeIcons.strokeRoundedMedicine01,
  'fitness': HugeIcons.strokeRoundedDumbbell01,
  'shopping': HugeIcons.strokeRoundedShoppingBag02,
  'fashion': HugeIcons.strokeRoundedShirt01,
  'entertainment': HugeIcons.strokeRoundedFilm01,
  'games': HugeIcons.strokeRoundedGameController03,
  'education': HugeIcons.strokeRoundedMortarboard01,
  'book': HugeIcons.strokeRoundedBook02,
  'baby': HugeIcons.strokeRoundedBaby01,
  'gift': HugeIcons.strokeRoundedGift,
  'travel': HugeIcons.strokeRoundedAirplane01,
  'subscription': HugeIcons.strokeRoundedRepeat,
  'delivery': HugeIcons.strokeRoundedDeliveryTruck01,
  'store': HugeIcons.strokeRoundedStore01,
  'salary': HugeIcons.strokeRoundedBriefcase01,
  'bonus': HugeIcons.strokeRoundedAward01,
  'freelance': HugeIcons.strokeRoundedMoney03,
  'investment': HugeIcons.strokeRoundedChartLineData01,
  'receive': HugeIcons.strokeRoundedMoneyReceive01,
  'coins': HugeIcons.strokeRoundedCoins01,
  'other': HugeIcons.strokeRoundedTag01,
};

HugeIconData categoryIcon(String key) => categoryIcons[key] ?? HugeIcons.strokeRoundedTag01;

/// Nada warna kategori — diambil dari keluarga warna referensi
/// (rose, blush, sage, clay) supaya grafik tetap harmonis.
const categoryTones = <int>[
  0xFFFE64A3, // rose
  0xFFFEACA8, // blush
  0xFF979F7E, // sage
  0xFFC98B6B, // clay
  0xFFAF2365, // berry
  0xFF7C8C6E, // moss
  0xFFE7A977, // apricot
  0xFF8C4C4A, // cocoa
  0xFFB795C9, // lilac dust
  0xFF6E9AA3, // slate teal
];
