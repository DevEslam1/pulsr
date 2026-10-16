// lib/domain/models/quran_surah.dart
import 'package:flutter/foundation.dart';

/// Normalized Surah description within the holy Quran.
@immutable
class QuranSurah {
  final int number;
  final String nameArabic;
  final String nameEnglish;
  final String nameTransliteration;
  final int totalAyahs;
  final bool isMeccan;

  const QuranSurah({
    required this.number,
    required this.nameArabic,
    required this.nameEnglish,
    required this.nameTransliteration,
    required this.totalAyahs,
    required this.isMeccan,
  }) : assert(number >= 1 && number <= 114, 'Surah number must be 1..114');

  String get revelationPlace => isMeccan ? 'Meccan' : 'Medinan';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is QuranSurah &&
          runtimeType == other.runtimeType &&
          number == other.number;

  @override
  int get hashCode => number.hashCode;

  /// Complete, authoritative index of all 114 Surahs of the Holy Quran.
  static const List<QuranSurah> canonicalSurahs = [
    QuranSurah(
        number: 1,
        nameArabic: 'الفاتحة',
        nameEnglish: 'The Opening',
        nameTransliteration: 'Al-Fatihah',
        totalAyahs: 7,
        isMeccan: true),
    QuranSurah(
        number: 2,
        nameArabic: 'البقرة',
        nameEnglish: 'The Cow',
        nameTransliteration: 'Al-Baqarah',
        totalAyahs: 286,
        isMeccan: false),
    QuranSurah(
        number: 3,
        nameArabic: 'آل عمران',
        nameEnglish: 'Family of Imran',
        nameTransliteration: 'Ali \'Imran',
        totalAyahs: 200,
        isMeccan: false),
    QuranSurah(
        number: 4,
        nameArabic: 'النساء',
        nameEnglish: 'The Women',
        nameTransliteration: 'An-Nisa',
        totalAyahs: 176,
        isMeccan: false),
    QuranSurah(
        number: 5,
        nameArabic: 'المائدة',
        nameEnglish: 'The Table Spread',
        nameTransliteration: 'Al-Ma\'idah',
        totalAyahs: 120,
        isMeccan: false),
    QuranSurah(
        number: 6,
        nameArabic: 'الأنعام',
        nameEnglish: 'The Cattle',
        nameTransliteration: 'Al-An\'am',
        totalAyahs: 165,
        isMeccan: true),
    QuranSurah(
        number: 7,
        nameArabic: 'الأعراف',
        nameEnglish: 'The Heights',
        nameTransliteration: 'Al-A\'raf',
        totalAyahs: 206,
        isMeccan: true),
    QuranSurah(
        number: 8,
        nameArabic: 'الأنفال',
        nameEnglish: 'The Spoils of War',
        nameTransliteration: 'Al-Anfal',
        totalAyahs: 75,
        isMeccan: false),
    QuranSurah(
        number: 9,
        nameArabic: 'التوبة',
        nameEnglish: 'The Repentance',
        nameTransliteration: 'At-Tawbah',
        totalAyahs: 129,
        isMeccan: false),
    QuranSurah(
        number: 10,
        nameArabic: 'يونس',
        nameEnglish: 'Jonah',
        nameTransliteration: 'Yunus',
        totalAyahs: 109,
        isMeccan: true),
    QuranSurah(
        number: 11,
        nameArabic: 'هود',
        nameEnglish: 'Hud',
        nameTransliteration: 'Hud',
        totalAyahs: 123,
        isMeccan: true),
    QuranSurah(
        number: 12,
        nameArabic: 'يوسف',
        nameEnglish: 'Joseph',
        nameTransliteration: 'Yusuf',
        totalAyahs: 111,
        isMeccan: true),
    QuranSurah(
        number: 13,
        nameArabic: 'الرعد',
        nameEnglish: 'The Thunder',
        nameTransliteration: 'Ar-Ra\'d',
        totalAyahs: 43,
        isMeccan: false),
    QuranSurah(
        number: 14,
        nameArabic: 'إبراهيم',
        nameEnglish: 'Abraham',
        nameTransliteration: 'Ibrahim',
        totalAyahs: 52,
        isMeccan: true),
    QuranSurah(
        number: 15,
        nameArabic: 'الحجر',
        nameEnglish: 'The Rocky Tract',
        nameTransliteration: 'Al-Hijr',
        totalAyahs: 99,
        isMeccan: true),
    QuranSurah(
        number: 16,
        nameArabic: 'النحل',
        nameEnglish: 'The Bee',
        nameTransliteration: 'An-Nahl',
        totalAyahs: 128,
        isMeccan: true),
    QuranSurah(
        number: 17,
        nameArabic: 'الإسراء',
        nameEnglish: 'The Night Journey',
        nameTransliteration: 'Al-Isra',
        totalAyahs: 111,
        isMeccan: true),
    QuranSurah(
        number: 18,
        nameArabic: 'الكهف',
        nameEnglish: 'The Cave',
        nameTransliteration: 'Al-Kahf',
        totalAyahs: 110,
        isMeccan: true),
    QuranSurah(
        number: 19,
        nameArabic: 'مريم',
        nameEnglish: 'Mary',
        nameTransliteration: 'Maryam',
        totalAyahs: 98,
        isMeccan: true),
    QuranSurah(
        number: 20,
        nameArabic: 'طه',
        nameEnglish: 'Ta-Ha',
        nameTransliteration: 'Ta-Ha',
        totalAyahs: 135,
        isMeccan: true),
    QuranSurah(
        number: 21,
        nameArabic: 'الأنبياء',
        nameEnglish: 'The Prophets',
        nameTransliteration: 'Al-Anbiya',
        totalAyahs: 112,
        isMeccan: true),
    QuranSurah(
        number: 22,
        nameArabic: 'الحج',
        nameEnglish: 'The Pilgrimage',
        nameTransliteration: 'Al-Hajj',
        totalAyahs: 78,
        isMeccan: false),
    QuranSurah(
        number: 23,
        nameArabic: 'المؤمنون',
        nameEnglish: 'The Believers',
        nameTransliteration: 'Al-Mu\'minun',
        totalAyahs: 118,
        isMeccan: true),
    QuranSurah(
        number: 24,
        nameArabic: 'النور',
        nameEnglish: 'The Light',
        nameTransliteration: 'An-Nur',
        totalAyahs: 64,
        isMeccan: false),
    QuranSurah(
        number: 25,
        nameArabic: 'الفرقان',
        nameEnglish: 'The Criterion',
        nameTransliteration: 'Al-Furqan',
        totalAyahs: 77,
        isMeccan: true),
    QuranSurah(
        number: 26,
        nameArabic: 'الشعراء',
        nameEnglish: 'The Poets',
        nameTransliteration: 'Ash-Shu\'ara',
        totalAyahs: 227,
        isMeccan: true),
    QuranSurah(
        number: 27,
        nameArabic: 'النمل',
        nameEnglish: 'The Ant',
        nameTransliteration: 'An-Naml',
        totalAyahs: 93,
        isMeccan: true),
    QuranSurah(
        number: 28,
        nameArabic: 'القصص',
        nameEnglish: 'The Stories',
        nameTransliteration: 'Al-Qasas',
        totalAyahs: 88,
        isMeccan: true),
    QuranSurah(
        number: 29,
        nameArabic: 'العنكبوت',
        nameEnglish: 'The Spider',
        nameTransliteration: 'Al-\'Ankabut',
        totalAyahs: 69,
        isMeccan: true),
    QuranSurah(
        number: 30,
        nameArabic: 'الروم',
        nameEnglish: 'The Romans',
        nameTransliteration: 'Ar-Rum',
        totalAyahs: 60,
        isMeccan: true),
    QuranSurah(
        number: 31,
        nameArabic: 'لقمان',
        nameEnglish: 'Luqman',
        nameTransliteration: 'Luqman',
        totalAyahs: 34,
        isMeccan: true),
    QuranSurah(
        number: 32,
        nameArabic: 'السجدة',
        nameEnglish: 'The Prostration',
        nameTransliteration: 'As-Sajdah',
        totalAyahs: 30,
        isMeccan: true),
    QuranSurah(
        number: 33,
        nameArabic: 'الأحزاب',
        nameEnglish: 'The Combined Forces',
        nameTransliteration: 'Al-Ahzab',
        totalAyahs: 73,
        isMeccan: false),
    QuranSurah(
        number: 34,
        nameArabic: 'سبأ',
        nameEnglish: 'Sheba',
        nameTransliteration: 'Saba',
        totalAyahs: 54,
        isMeccan: true),
    QuranSurah(
        number: 35,
        nameArabic: 'فاطر',
        nameEnglish: 'Originator',
        nameTransliteration: 'Fatir',
        totalAyahs: 45,
        isMeccan: true),
    QuranSurah(
        number: 36,
        nameArabic: 'يس',
        nameEnglish: 'Ya-Sin',
        nameTransliteration: 'Ya-Sin',
        totalAyahs: 83,
        isMeccan: true),
    QuranSurah(
        number: 37,
        nameArabic: 'الصافات',
        nameEnglish: 'Those who set the Ranks',
        nameTransliteration: 'As-Saffat',
        totalAyahs: 182,
        isMeccan: true),
    QuranSurah(
        number: 38,
        nameArabic: 'ص',
        nameEnglish: 'The Letter Saad',
        nameTransliteration: 'Sad',
        totalAyahs: 88,
        isMeccan: true),
    QuranSurah(
        number: 39,
        nameArabic: 'الزمر',
        nameEnglish: 'The Troops',
        nameTransliteration: 'Az-Zumar',
        totalAyahs: 75,
        isMeccan: true),
    QuranSurah(
        number: 40,
        nameArabic: 'غافر',
        nameEnglish: 'The Forgiver',
        nameTransliteration: 'Ghafir',
        totalAyahs: 85,
        isMeccan: true),
    QuranSurah(
        number: 41,
        nameArabic: 'فصلت',
        nameEnglish: 'Explained in Detail',
        nameTransliteration: 'Fussilat',
        totalAyahs: 54,
        isMeccan: true),
    QuranSurah(
        number: 42,
        nameArabic: 'الشورى',
        nameEnglish: 'The Consultation',
        nameTransliteration: 'Ash-Shura',
        totalAyahs: 53,
        isMeccan: true),
    QuranSurah(
        number: 43,
        nameArabic: 'الزخرف',
        nameEnglish: 'The Ornaments of Gold',
        nameTransliteration: 'Az-Zukhruf',
        totalAyahs: 89,
        isMeccan: true),
    QuranSurah(
        number: 44,
        nameArabic: 'الدخان',
        nameEnglish: 'The Smoke',
        nameTransliteration: 'Ad-Dukhan',
        totalAyahs: 59,
        isMeccan: true),
    QuranSurah(
        number: 45,
        nameArabic: 'الجاثية',
        nameEnglish: 'The Crouching',
        nameTransliteration: 'Al-Jathiyah',
        totalAyahs: 37,
        isMeccan: true),
    QuranSurah(
        number: 46,
        nameArabic: 'الأحقاف',
        nameEnglish: 'The Wind-Curved Sandhills',
        nameTransliteration: 'Al-Ahqaf',
        totalAyahs: 35,
        isMeccan: true),
    QuranSurah(
        number: 47,
        nameArabic: 'محمد',
        nameEnglish: 'Muhammad',
        nameTransliteration: 'Muhammad',
        totalAyahs: 38,
        isMeccan: false),
    QuranSurah(
        number: 48,
        nameArabic: 'الفتح',
        nameEnglish: 'The Victory',
        nameTransliteration: 'Al-Fath',
        totalAyahs: 29,
        isMeccan: false),
    QuranSurah(
        number: 49,
        nameArabic: 'الحجرات',
        nameEnglish: 'The Rooms',
        nameTransliteration: 'Al-Hujurat',
        totalAyahs: 18,
        isMeccan: false),
    QuranSurah(
        number: 50,
        nameArabic: 'ق',
        nameEnglish: 'The Letter Qaf',
        nameTransliteration: 'Qaf',
        totalAyahs: 45,
        isMeccan: true),
    QuranSurah(
        number: 51,
        nameArabic: 'الذاريات',
        nameEnglish: 'The Winnowing Winds',
        nameTransliteration: 'Adh-Dhariyat',
        totalAyahs: 60,
        isMeccan: true),
    QuranSurah(
        number: 52,
        nameArabic: 'الطور',
        nameEnglish: 'The Mount',
        nameTransliteration: 'At-Tur',
        totalAyahs: 49,
        isMeccan: true),
    QuranSurah(
        number: 53,
        nameArabic: 'النجم',
        nameEnglish: 'The Star',
        nameTransliteration: 'An-Najm',
        totalAyahs: 62,
        isMeccan: true),
    QuranSurah(
        number: 54,
        nameArabic: 'القمر',
        nameEnglish: 'The Moon',
        nameTransliteration: 'Al-Qamar',
        totalAyahs: 55,
        isMeccan: true),
    QuranSurah(
        number: 55,
        nameArabic: 'الرحمن',
        nameEnglish: 'The Beneficent',
        nameTransliteration: 'Ar-Rahman',
        totalAyahs: 78,
        isMeccan: false),
    QuranSurah(
        number: 56,
        nameArabic: 'الواقعة',
        nameEnglish: 'The Inevitable',
        nameTransliteration: 'Al-Waqi\'ah',
        totalAyahs: 96,
        isMeccan: true),
    QuranSurah(
        number: 57,
        nameArabic: 'الحديد',
        nameEnglish: 'The Iron',
        nameTransliteration: 'Al-Hadid',
        totalAyahs: 29,
        isMeccan: false),
    QuranSurah(
        number: 58,
        nameArabic: 'المجادلة',
        nameEnglish: 'The Pleading Woman',
        nameTransliteration: 'Al-Mujadila',
        totalAyahs: 22,
        isMeccan: false),
    QuranSurah(
        number: 59,
        nameArabic: 'الحشر',
        nameEnglish: 'The Exile',
        nameTransliteration: 'Al-Hashr',
        totalAyahs: 24,
        isMeccan: false),
    QuranSurah(
        number: 60,
        nameArabic: 'الممتحنة',
        nameEnglish: 'She that is to be examined',
        nameTransliteration: 'Al-Mumtahanah',
        totalAyahs: 13,
        isMeccan: false),
    QuranSurah(
        number: 61,
        nameArabic: 'الصف',
        nameEnglish: 'The Ranks',
        nameTransliteration: 'As-Saff',
        totalAyahs: 14,
        isMeccan: false),
    QuranSurah(
        number: 62,
        nameArabic: 'الجمعة',
        nameEnglish: 'Friday',
        nameTransliteration: 'Al-Jumu\'ah',
        totalAyahs: 11,
        isMeccan: false),
    QuranSurah(
        number: 63,
        nameArabic: 'المنافقون',
        nameEnglish: 'The Hypocrites',
        nameTransliteration: 'Al-Munafiqun',
        totalAyahs: 11,
        isMeccan: false),
    QuranSurah(
        number: 64,
        nameArabic: 'التغابن',
        nameEnglish: 'The Mutual Disillusion',
        nameTransliteration: 'At-Taghabun',
        totalAyahs: 18,
        isMeccan: false),
    QuranSurah(
        number: 65,
        nameArabic: 'الطلاق',
        nameEnglish: 'The Divorce',
        nameTransliteration: 'At-Talaq',
        totalAyahs: 12,
        isMeccan: false),
    QuranSurah(
        number: 66,
        nameArabic: 'التحريم',
        nameEnglish: 'The Prohibition',
        nameTransliteration: 'At-Tahrim',
        totalAyahs: 12,
        isMeccan: false),
    QuranSurah(
        number: 67,
        nameArabic: 'الملك',
        nameEnglish: 'The Sovereignty',
        nameTransliteration: 'Al-Mulk',
        totalAyahs: 30,
        isMeccan: true),
    QuranSurah(
        number: 68,
        nameArabic: 'القلم',
        nameEnglish: 'The Pen',
        nameTransliteration: 'Al-Qalam',
        totalAyahs: 52,
        isMeccan: true),
    QuranSurah(
        number: 69,
        nameArabic: 'الحاقة',
        nameEnglish: 'The Reality',
        nameTransliteration: 'Al-Haqqah',
        totalAyahs: 52,
        isMeccan: true),
    QuranSurah(
        number: 70,
        nameArabic: 'المعارج',
        nameEnglish: 'The Ascending Stairways',
        nameTransliteration: 'Al-Ma\'arij',
        totalAyahs: 44,
        isMeccan: true),
    QuranSurah(
        number: 71,
        nameArabic: 'نوح',
        nameEnglish: 'Noah',
        nameTransliteration: 'Nuh',
        totalAyahs: 28,
        isMeccan: true),
    QuranSurah(
        number: 72,
        nameArabic: 'الجن',
        nameEnglish: 'The Jinn',
        nameTransliteration: 'Al-Jinn',
        totalAyahs: 28,
        isMeccan: true),
    QuranSurah(
        number: 73,
        nameArabic: 'المزمل',
        nameEnglish: 'The Enshrouded One',
        nameTransliteration: 'Al-Muzzammil',
        totalAyahs: 20,
        isMeccan: true),
    QuranSurah(
        number: 74,
        nameArabic: 'المدثر',
        nameEnglish: 'The Cloaked One',
        nameTransliteration: 'Al-Muddaththir',
        totalAyahs: 56,
        isMeccan: true),
    QuranSurah(
        number: 75,
        nameArabic: 'القيامة',
        nameEnglish: 'The Resurrection',
        nameTransliteration: 'Al-Qiyamah',
        totalAyahs: 40,
        isMeccan: true),
    QuranSurah(
        number: 76,
        nameArabic: 'الإنسان',
        nameEnglish: 'Man',
        nameTransliteration: 'Al-Insan',
        totalAyahs: 31,
        isMeccan: false),
    QuranSurah(
        number: 77,
        nameArabic: 'المرسلات',
        nameEnglish: 'The Emissaries',
        nameTransliteration: 'Al-Mursalat',
        totalAyahs: 50,
        isMeccan: true),
    QuranSurah(
        number: 78,
        nameArabic: 'النبأ',
        nameEnglish: 'The Tidings',
        nameTransliteration: 'An-Naba',
        totalAyahs: 40,
        isMeccan: true),
    QuranSurah(
        number: 79,
        nameArabic: 'النازعات',
        nameEnglish: 'Those who drag forth',
        nameTransliteration: 'An-Nazi\'at',
        totalAyahs: 46,
        isMeccan: true),
    QuranSurah(
        number: 80,
        nameArabic: 'عبس',
        nameEnglish: 'He Frowned',
        nameTransliteration: '\'Abasa',
        totalAyahs: 42,
        isMeccan: true),
    QuranSurah(
        number: 81,
        nameArabic: 'التكوير',
        nameEnglish: 'The Overthrowing',
        nameTransliteration: 'At-Takwir',
        totalAyahs: 29,
        isMeccan: true),
    QuranSurah(
        number: 82,
        nameArabic: 'الانفطار',
        nameEnglish: 'The Cleaving',
        nameTransliteration: 'Al-Infitar',
        totalAyahs: 19,
        isMeccan: true),
    QuranSurah(
        number: 83,
        nameArabic: 'المطففين',
        nameEnglish: 'The Defrauding',
        nameTransliteration: 'Al-Mutaffifin',
        totalAyahs: 36,
        isMeccan: true),
    QuranSurah(
        number: 84,
        nameArabic: 'الانشقاق',
        nameEnglish: 'The Splitting Open',
        nameTransliteration: 'Al-Inshiqaq',
        totalAyahs: 25,
        isMeccan: true),
    QuranSurah(
        number: 85,
        nameArabic: 'البروج',
        nameEnglish: 'The Mansions of the Stars',
        nameTransliteration: 'Al-Buruj',
        totalAyahs: 22,
        isMeccan: true),
    QuranSurah(
        number: 86,
        nameArabic: 'الطارق',
        nameEnglish: 'The Morning Star',
        nameTransliteration: 'At-Tariq',
        totalAyahs: 17,
        isMeccan: true),
    QuranSurah(
        number: 87,
        nameArabic: 'الأعلى',
        nameEnglish: 'The Most High',
        nameTransliteration: 'Al-A\'la',
        totalAyahs: 19,
        isMeccan: true),
    QuranSurah(
        number: 88,
        nameArabic: 'الغاشية',
        nameEnglish: 'The Overwhelming',
        nameTransliteration: 'Al-Ghashiyah',
        totalAyahs: 26,
        isMeccan: true),
    QuranSurah(
        number: 89,
        nameArabic: 'الفجر',
        nameEnglish: 'The Dawn',
        nameTransliteration: 'Al-Fajr',
        totalAyahs: 30,
        isMeccan: true),
    QuranSurah(
        number: 90,
        nameArabic: 'البلد',
        nameEnglish: 'The City',
        nameTransliteration: 'Al-Balad',
        totalAyahs: 20,
        isMeccan: true),
    QuranSurah(
        number: 91,
        nameArabic: 'الشمس',
        nameEnglish: 'The Sun',
        nameTransliteration: 'Ash-Shams',
        totalAyahs: 15,
        isMeccan: true),
    QuranSurah(
        number: 92,
        nameArabic: 'الليل',
        nameEnglish: 'The Night',
        nameTransliteration: 'Al-Layl',
        totalAyahs: 21,
        isMeccan: true),
    QuranSurah(
        number: 93,
        nameArabic: 'الضحى',
        nameEnglish: 'The Morning Hours',
        nameTransliteration: 'Ad-Duha',
        totalAyahs: 11,
        isMeccan: true),
    QuranSurah(
        number: 94,
        nameArabic: 'الشرح',
        nameEnglish: 'The Relief',
        nameTransliteration: 'Ash-Sharh',
        totalAyahs: 8,
        isMeccan: true),
    QuranSurah(
        number: 95,
        nameArabic: 'التين',
        nameEnglish: 'The Fig',
        nameTransliteration: 'At-Tin',
        totalAyahs: 8,
        isMeccan: true),
    QuranSurah(
        number: 96,
        nameArabic: 'العلق',
        nameEnglish: 'The Clot',
        nameTransliteration: 'Al-\'Alaq',
        totalAyahs: 19,
        isMeccan: true),
    QuranSurah(
        number: 97,
        nameArabic: 'القدر',
        nameEnglish: 'The Power',
        nameTransliteration: 'Al-Qadr',
        totalAyahs: 5,
        isMeccan: true),
    QuranSurah(
        number: 98,
        nameArabic: 'البينة',
        nameEnglish: 'The Clear Proof',
        nameTransliteration: 'Al-Bayyinah',
        totalAyahs: 8,
        isMeccan: false),
    QuranSurah(
        number: 99,
        nameArabic: 'الزلزلة',
        nameEnglish: 'The Earthquake',
        nameTransliteration: 'Az-Zalzalah',
        totalAyahs: 8,
        isMeccan: false),
    QuranSurah(
        number: 100,
        nameArabic: 'العاديات',
        nameEnglish: 'The Courser',
        nameTransliteration: 'Al-\'Adiyat',
        totalAyahs: 11,
        isMeccan: true),
    QuranSurah(
        number: 101,
        nameArabic: 'القارعة',
        nameEnglish: 'The Calamity',
        nameTransliteration: 'Al-Qari\'ah',
        totalAyahs: 11,
        isMeccan: true),
    QuranSurah(
        number: 102,
        nameArabic: 'التكاثر',
        nameEnglish: 'The Rivalry in world increase',
        nameTransliteration: 'At-Takathur',
        totalAyahs: 8,
        isMeccan: true),
    QuranSurah(
        number: 103,
        nameArabic: 'العصر',
        nameEnglish: 'The Declining Day',
        nameTransliteration: 'Al-\'Asr',
        totalAyahs: 3,
        isMeccan: true),
    QuranSurah(
        number: 104,
        nameArabic: 'الهمزة',
        nameEnglish: 'The Traducer',
        nameTransliteration: 'Al-Humazah',
        totalAyahs: 9,
        isMeccan: true),
    QuranSurah(
        number: 105,
        nameArabic: 'الفيل',
        nameEnglish: 'The Elephant',
        nameTransliteration: 'Al-Fil',
        totalAyahs: 5,
        isMeccan: true),
    QuranSurah(
        number: 106,
        nameArabic: 'قريش',
        nameEnglish: 'Quraysh',
        nameTransliteration: 'Quraysh',
        totalAyahs: 4,
        isMeccan: true),
    QuranSurah(
        number: 107,
        nameArabic: 'الماعون',
        nameEnglish: 'The Small Kindness',
        nameTransliteration: 'Al-Ma\'un',
        totalAyahs: 7,
        isMeccan: true),
    QuranSurah(
        number: 108,
        nameArabic: 'الكوثر',
        nameEnglish: 'The Abundance',
        nameTransliteration: 'Al-Kawthar',
        totalAyahs: 3,
        isMeccan: true),
    QuranSurah(
        number: 109,
        nameArabic: 'الكافرون',
        nameEnglish: 'The Disbelievers',
        nameTransliteration: 'Al-Kafirun',
        totalAyahs: 6,
        isMeccan: true),
    QuranSurah(
        number: 110,
        nameArabic: 'النصر',
        nameEnglish: 'The Divine Support',
        nameTransliteration: 'An-Nasr',
        totalAyahs: 3,
        isMeccan: false),
    QuranSurah(
        number: 111,
        nameArabic: 'المسد',
        nameEnglish: 'The Palm Fiber',
        nameTransliteration: 'Al-Masad',
        totalAyahs: 5,
        isMeccan: true),
    QuranSurah(
        number: 112,
        nameArabic: 'الإخلاص',
        nameEnglish: 'The Sincerity',
        nameTransliteration: 'Al-Ikhlas',
        totalAyahs: 4,
        isMeccan: true),
    QuranSurah(
        number: 113,
        nameArabic: 'الفلق',
        nameEnglish: 'The Daybreak',
        nameTransliteration: 'Al-Falaq',
        totalAyahs: 5,
        isMeccan: true),
    QuranSurah(
        number: 114,
        nameArabic: 'الناس',
        nameEnglish: 'Mankind',
        nameTransliteration: 'An-Nas',
        totalAyahs: 6,
        isMeccan: true),
  ];

  static QuranSurah? byNumber(int number) {
    if (number < 1 || number > 114) return null;
    return canonicalSurahs[number - 1];
  }
}

/// Normalized description of a renowned Quran reciter.
@immutable
class QuranReciter {
  final String id;
  final String nameEnglish;
  final String nameArabic;
  final String riwayah;
  final String bio;

  const QuranReciter({
    required this.id,
    required this.nameEnglish,
    required this.nameArabic,
    required this.riwayah,
    this.bio = '',
  });

  static const List<QuranReciter> canonicalReciters = [
    QuranReciter(
      id: 'alafasy',
      nameEnglish: 'Mishary Rashid Alafasy',
      nameArabic: 'مشاري راشد العفاسي',
      riwayah: 'Hafs \'an \'Asim',
      bio:
          'Renowned for measured tempo, crystal-clear Tajweed makharij, and emotional depth.',
    ),
    QuranReciter(
      id: 'abdul_basit',
      nameEnglish: 'Abdul Basit Abdul Samad',
      nameArabic: 'عبد الباسط عبد الصمد',
      riwayah: 'Hafs \'an \'Asim (Mujawwad & Murattal)',
      bio:
          'Golden Era legend celebrated for phenomenal breath control and soaring resonant maqamat.',
    ),
    QuranReciter(
      id: 'minshawi',
      nameEnglish: 'Muhammad Siddiq Al-Minshawi',
      nameArabic: 'محمد صديق المنشاوي',
      riwayah: 'Hafs \'an \'Asim',
      bio:
          'Beloved for poignant, reverent spiritual delivery and pristine articulation.',
    ),
    QuranReciter(
      id: 'husary',
      nameEnglish: 'Mahmoud Khalil Al-Husary',
      nameArabic: 'محمود خليل الحصري',
      riwayah: 'Hafs \'an \'Asim / Qalun',
      bio:
          'The undisputed benchmark for Tajweed accuracy and Quranic education.',
    ),
    QuranReciter(
      id: 'muaiqly',
      nameEnglish: 'Maher Al-Muaiqly',
      nameArabic: 'ماهر المعيقلي',
      riwayah: 'Hafs \'an \'Asim',
      bio:
          'Imam of Al-Masjid Al-Haram in Mecca with powerful, soulful acoustics.',
    ),
    QuranReciter(
      id: 'dossari',
      nameEnglish: 'Yasser Al-Dossari',
      nameArabic: 'ياسر الدوسري',
      riwayah: 'Hafs \'an \'Asim',
      bio: 'Dynamic pacing with majestic resonance and rich vocal projection.',
    ),
    QuranReciter(
      id: 'yassin_warsh',
      nameEnglish: 'Yassin Al-Jazaery',
      nameArabic: 'ياسين الجزائري',
      riwayah: 'Warsh \'an Nafi\'',
      bio: 'Leading master of the North African Warsh recitation style.',
    ),
  ];
}

/// Verse text payload for synchronized Mushaf rendering and Hifz recall.
@immutable
class QuranAyahText {
  final int surahNumber;
  final int ayahNumber;
  final String textArabic;
  final String textEnglish;

  const QuranAyahText({
    required this.surahNumber,
    required this.ayahNumber,
    required this.textArabic,
    this.textEnglish = '',
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is QuranAyahText &&
          runtimeType == other.runtimeType &&
          surahNumber == other.surahNumber &&
          ayahNumber == other.ayahNumber;

  @override
  int get hashCode => Object.hash(surahNumber, ayahNumber);
}
