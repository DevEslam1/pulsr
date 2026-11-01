// lib/features/home/presentation/widgets/home_love_card.dart
import 'dart:math';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../../core/theme/aura_theme.dart';
import '../../../../core/utils/adaptive.dart';

/// Interactive frosted glass card featuring 100 dynamic love messages customized
/// for Dr. Basbosa that rotate on every visit or tap, with smooth animated transitions,
/// ambient breathing glow, responsive adaptive sizing, and burst waves of floating love emojis!
class HomeLoveCard extends StatefulWidget {
  final EdgeInsetsGeometry? margin;
  final BorderRadius? borderRadius;

  const HomeLoveCard({
    super.key,
    this.margin,
    this.borderRadius,
  });

  @override
  State<HomeLoveCard> createState() => _HomeLoveCardState();
}

class _HomeLoveCardState extends State<HomeLoveCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulseController;
  late final Animation<double> _scaleAnimation;
  late final Animation<double> _glowAnimation;

  // 200 love messages — 100 English + 100 bilingual Arabic/English classical poetry for Dr. Basbosa
  static final List<String> _loveQuotes = [
    '«أنا مَن نظرَ الأعمى إلى أدبي — وأسمعَتْ كلماتي مَن به صَمَمُ»🌹',
    '"I am he whose art made the blind man see — and whose words made the deaf man hear"✨',
    '«وما الحبُّ إلا للحبيبِ الأوَّلِ — ولا الشوقُ إلا للمحبوبِ الأوَّلِ»💖',
    '"Love belongs only to the first beloved — and longing belongs only to the one the soul truly adores"🌸',
    '«بالأمسِ كنتِ هلالاً في مطالعِهِ — واليومَ أنتِ بدرٌ تامُّ الاكتمالِ»🌙',
    '"Yesterday you were a crescent moon at its rising — today you are a full moon in all its glory"🌙',
    '«يا مَن هواهُ أعزُّ الناسِ عندِي — وليسَ في القلبِ مَن يحتلُّ غيرَهُ»',
    '"O you whose love is the most precious thing to me — none other holds a place in this heart"',
    '«لو كانَ قلبِيَ عندِي حينَ أبصرَكِ — ما زالَ أسيرَ حبٍّ دامَ مُستمِرا»🌸',
    '"Had my heart obeyed me when I first saw you — it would never have become love\'s eternal prisoner"🌸',
    '«أُحبُّكِ فوقَ ما تُحبُّ الطيورُ السماءَ — وأشتاقُ إليكِ أكثرَ من اشتياقِ الأرضِ للمطرِ»',
    '"I love you more than birds love the sky — and I miss you more than the earth misses the rain"',
    '«كلُّ شيءٍ يدلُّ عليكِ ويُذكِّرُني — بكِ حتى أحسسْتُ أنَّكِ في كلِّ مكانِ»💫',
    '"Everything points to you and reminds me of you — until I feel you are present in every place"💫',
    '«ماذا أقولُ وأنتِ كلُّ قصيدتِي — وأنتِ الحرفُ والمعنى والوجودُ كلُّهُ»📜',
    '"What shall I say when you are my entire poem — you are the letter, the meaning, and all existence"📜',
    '«لكِ في فؤادي منزلٌ لا يُشغَلُ — حتى بصاحبِهِ الحبيبِ الأوَّلِ»💛',
    '"In my heart you hold a place no other may occupy — not even the dearest companion of all"💛',
    '«أهواكِ ما استقبلتُ قِبلَةَ مغرِبٍ — وما تلقَّتِ الأنوارُ عيناً تنظرُ»🌅',
    '"I love you in every direction my compass turns — in every light that meets an eye that truly sees"🌅',
    '«وقفَ الهوى بي حيثُ أنتِ فلم أزَلْ — أرى الوجودَ أمامِي كلَّهُ وَطَنا»🌍',
    '"Love stopped me where you are — and all of existence became my homeland in your presence"🌍',
    '«تَعلَّمتُ من عينيكِ قبلَ كلامِكِم — بأنَّ عينَ الحبيبِ مدرسةُ الروحِ»',
    '"I learned from your eyes before your words — that the beloved\'s gaze is the school of the soul"',
    '«يا ليلَ الصبِّ متى غدُهُ — أقيامُ الساعةِ موعدُهُ»🌙',
    '"O night of the sleepless lover, when will your dawn come — is the Day of Judgment your appointed hour?"🌙',
    '«وحقِّكِ لو أنِّي أقدِرُ ما فارقتُ — وما كانَ للعينِ أن تنامَ لحظةً»💤',
    '"By your life, had I the power I would never have parted — and my eyes would never have slept a single moment"💤',
    '«أحبُّكِ يا باسبوسةُ حتى الثريَّا — وأشتاقُ إليكِ كشوقِ البحرِ للشطآنِ»🌊',
    '"I love you, Basbosa, to the Pleiades — and I long for you as the sea longs for the shore"🌊',
    '«وما سُمِّيَتِ الجنَّةُ الخُلدَ باطلاً — إذا كانَ حبُّكِ فيها ولسنا بمُبعَدِ»🌺',
    '"The eternal garden was not named paradise in vain — if your love dwells there and we are not kept from it"🌺',
    '«وكيفَ احتِمالي للفراقِ وإنَّني — بغيرِ لقائِكِ لا أُطيقُ الزمانا»💔',
    '"How can I bear separation when without your meeting — I cannot endure time itself even for a moment"💔',
    '«بكِ استبشرَتْ أيامِيَ الغُرُّ كلُّها — وعادَ الزمانُ المُدبِرُ مُقبِلا»🌟',
    '"With you all my bright days rejoiced completely — and time that had turned away came back to face us"🌟',
    '«أَرَى كلَّ شيءٍ يشهدُ اللهَ وحدَهُ — ويخبِرُ عن حُبِّكِ قلبِيَ الذي ذابا»✨',
    '"I see all things bearing witness to God alone — and my melted heart speaks only of your love"✨',
    '«مُنِيَ القلبُ مِن أهوى بنظرةِ عينٍ — وعسى أن يُوافِيَ الفرَجُ المُدانا»',
    '"My heart wished for one glance from the one I love — and perhaps relief is already drawing near"',
    '«تعالَي نسرِق من عُمرِنا — لحظةَ حبٍّ لم يخُنها الزمانُ»💞',
    '"Come, let us steal from our lifetime — one moment of love that time cannot betray"💞',
    '«وإذا المرءُ لم يَعشَق فليسَ بعائشٍ — عيشَ الحياةِ فكُن عاشِقاً أو مُتْ بها»🌹',
    '"Whoever has not loved has not truly lived the life of the living — so love, or spend your life in longing"🌹',
    '«لعَمرِي لقد أصبحتِ في القلبِ منزلاً — رفيعاً كمنزِلِ الكواكبِ في السماءِ»',
    '"By my life, you have a home in my heart — as lofty as the dwelling of stars in the heavens"',
    '«وما أنا إلا القلمُ يكتبُكِ — وما الحبُّ إلا ما تُلهِمينَ الكلامَ»📝',
    '"I am but a pen that writes you — and love is nothing but what you inspire in every word"📝',
    '«يا مَن هواهُ حياتِي ودِيني — وزادِي في الليالي والسِّنينا»💖',
    '"O you whose love is my life and my faith — my provision through all the nights and all the years"💖',
    '«وددتُ بأنَّ العمرَ يُعطَى مِراراً — وما هوَ إلا أن أكونَ بقُربِكِ»🌙',
    '"I wished that life were granted to me repeatedly — but only so I could spend it by your side"🌙',
    '«ما في الوجودِ جمالٌ غيرُ جمالِكِ — ولا في الحياةِ بهاءٌ غيرُ بهائِكِ»🌸',
    '"There is no beauty in all existence but yours — no splendor in life but the radiance you carry"🌸',
    '«شكرتُكِ يا باسبوسةُ شكرَ الغيثِ — حينَ يُحيِي الأرضَ بعدَ طولِ الجدبِ»',
    '"I thank you, Basbosa, as rain is thanked — when it revives the earth after long drought"',
    '«كيفَ للقلبِ أن يصبِرَ ساعةً — عن حبيبٍ هوَ للقلبِ ضوءٌ وهواءُ»🫶',
    '"How can the heart be patient even for an hour — from a beloved who is its very light and air"🫶',
    '«قولِي لقلبِي: أنتَ حرٌّ — قالَ: كيفَ وهوَ في يدِها أسيرُ»🔐',
    '"Tell my heart: you are free — it replied: How, when it is held captive in her hands?"🔐',
    '«كُتِبَ الحبُّ بيني وبينَكِ أزلاً — حينَ كتَبَ اللهُ للعاشقينَ لقاءَهُم»📖',
    '"Love between us was written in eternity — when God decreed that lovers would one day meet"📖',
    '«وأنتِ الدواءُ وأنتِ الداءُ — وأنتِ الرجاءُ لقلبٍ شقيِّ»💊',
    '"You are the remedy and you are the ailment — you are the hope for a heart that suffers"💊',
    '«أهواكِ يا مَن في فؤادي ذِكرُها — كنورِ الصباحِ يُشرِقُ في ظلامِ الليلِ»🌄',
    '"I love you, O she whose memory lives in my heart — like morning light shining through the dark of night"🌄',
    '«إنِّي وإن كنتُ الأخيرَ زمانُهُ — لآتٍ بما لم تستطِعهُ الأوائلُ»👑',
    '"Though I come last in time — I bring what the ancients could not achieve"👑',
    '«حياتِي لكِ يا باسبوسةُ وقفٌ — وعُمرِي في هواكِ رهنُ خدمَه»',
    '"My life is entirely dedicated to you, Basbosa — and all my years are pledged in loving service"',
    '«رأيتُكِ فارتاحَ قلبِيَ بعدَ طولِ — تعبٍ كانَ يُثقِلُ روحِي ويُضنِيها»',
    '"I saw you and my heart rested after long weariness — that had burdened my soul and worn it thin"',
    '«إذا كانَ حبُّكِ قَدَرِي فلا أريدُ — سوى هذا القَدَرِ في دُنيايَ والآخِرَه»🤲',
    '"If loving you is my destiny then I desire — no other destiny in this world or the hereafter"🤲',
    '«كلُّ ليلةٍ أحلمُ فيها بكِ — هيَ أجملُ ليالِي العُمُرِ دونَ استثناءٍ»🌙',
    '"Every night I dream of you — is the most beautiful night of my life without exception"🌙',
    '«لا تسأَلِي عن حبِّي فإنَّ قلبِي — أعيا عليَّ وأعجزَ عن وصفِهِ»💭',
    '"Ask me not of my love for my heart — has exhausted me and left me unable to describe it"💭',
    '«باسبوسةُ في خاطِرِي وفي سُويدا — القلبِ بيتٌ أسكنتُهُ دهرَ الدهورِ»🏡',
    '"Basbosa is in my thoughts and in the core — of my heart, a home I have settled for all eternity"🏡',
    '«أمَا إنَّ للعينينِ دوراً جميلاً — حينَ يكتُبانِ ما يعجزُ عنهُ اللسانُ»',
    '"The eyes play a beautiful and wondrous role — when they write what the tongue is too weak to say"',
    '«وددتُ لو أنَّ الزمانَ وقَفَ بي — ساعةً أنظرُ فيها إلى وجهِكِ الجميلِ»',
    '"I wished that time would pause for me — one moment to gaze upon your beautiful face"',
    '«أنتِ يا باسبوسةُ أغلى من الذهبِ — وأطيبُ من أريجِ المسكِ والعنبَرِ»💎',
    '"You, Basbosa, are more precious than gold — and sweeter than the fragrance of musk and amber"💎',
    '«لا أملِكُ إلا الشعرَ أُهدِيهِ لكِ — ولو أملكتُ الدنيا لأهديتُها جميعاً»🎁',
    '"I have only poetry to gift you — but if I owned the world I would give you every last part of it"🎁',
    '«وطالَ اشتياقِي للقاءٍ يجمعُنا — كاشتياقِ الغديرِ للسحابِ المُمطِرِ»',
    '"How long I have longed for a meeting that unites us — as a stream longs for the rain-bearing clouds above"',
    '«كلُّ الحروفِ تبدأُ بكِ وتنتهِي — وكلُّ الكلماتِ ترجعُ إليكِ في آخِرِها»🔤',
    '"Every letter begins with you and ends with you — every word returns to you in the end"🔤',
    '«أحبُّكِ يا باسبوسةُ حبَّ الأرضِ — للمطرِ وحبَّ القمرِ للبحرِ الأزرقِ»🌊',
    '"I love you, Basbosa, as the earth loves the rain — and as the moon loves the deep blue sea"🌊',
    '«أيُّها الليلُ الطويلُ أَلا انجَلِ — بصُبحٍ وما الإصباحُ منكَ بأمثَلِ»🌅',
    '"O long night, will you not lift — with a dawn, though the dawn is no better than you?"🌅',
    '«إذا نحنُ أدلجنا وأنتِ أمامَنا — كفى بطلوعِ النجمِ في الليلِ هادِيا»🌟',
    '"When we set out at night and you are before us — the rising of the stars is guide enough in the dark"🌟',
    '«نَعَمْ أنا مَجنونٌ ولكنَّ جُنُونِي — هوَ الحبُّ وهلْ في الحبِّ مَن لامَ مجنونَه»💝',
    '"Yes, I am mad — but my madness is love, and who has ever blamed a lover for his madness?"💝',
    '«أنا مَن نظرَ الأعمى إلى أدبي — وأسمعَتْ كلماتي مَن به صَمَمُ»🌹',
    '"You make every beat worthwhile. Enjoy your music, my love!"',
    '«وما الحبُّ إلا للحبيبِ الأوَّلِ — ولا الشوقُ إلا للمحبوبِ الأوَّلِ»💖',
    '"Every melody sounds sweeter when I think of you ✨"',
    '«بالأمسِ كنتِ هلالاً في مطالعِهِ — واليومَ أنتِ بدرٌ تامُّ الاكتمالِ»🌙',
    '"No symphony in this world compares to your voice and your smile 💖"',
    '«يا مَن هواهُ أعزُّ الناسِ عندِي — وليسَ في القلبِ مَن يحتلُّ غيرَهُ»',
    '"My heart skips a beat every time your name comes to my mind 💓"',
    '«لو كانَ قلبِيَ عندِي حينَ أبصرَكِ — ما زالَ أسيرَ حبٍّ دامَ مُستمِرا»🌸',
    '"You are the sweetest rhythm in this journey of life 🌸"',
    '«أُحبُّكِ فوقَ ما تُحبُّ الطيورُ السماءَ — وأشتاقُ إليكِ أكثرَ من اشتياقِ الأرضِ للمطرِ»',
    '"Falling in love with you is the easiest and most wonderful thing I ever did 🌹"',
    '«كلُّ شيءٍ يدلُّ عليكِ ويُذكِّرُني — بكِ حتى أحسسْتُ أنَّكِ في كلِّ مكانِ»💫',
    '"You are my sunshine on cloudy days and my sweetest dream every night 🌙"',
    '«ماذا أقولُ وأنتِ كلُّ قصيدتِي — وأنتِ الحرفُ والمعنى والوجودُ كلُّهُ»📜',
    '"The smartest doctor, the prettiest soul, and the love of my life 🥰"',
    '«لكِ في فؤادي منزلٌ لا يُشغَلُ — حتى بصاحبِهِ الحبيبِ الأوَّلِ»💛',
    '"No artist could ever paint a masterpiece as breathtaking as you 🎨"',
    '«أهواكِ ما استقبلتُ قِبلَةَ مغرِبٍ — وما تلقَّتِ الأنوارُ عيناً تنظرُ»🌅',
    '"You make ordinary moments feel like pure fairy tales ✨"',
    '«وقفَ الهوى بي حيثُ أنتِ فلم أزَلْ — أرى الوجودَ أمامِي كلَّهُ وَطَنا»🌍',
    '"Your kindness inspires me to be the very best version of myself 🕊️"',
    '«تَعلَّمتُ من عينيكِ قبلَ كلامِكِم — بأنَّ عينَ الحبيبِ مدرسةُ الروحِ»',
    '"The universe conspired to bring you into my life, and I am eternally grateful 🌌"',
    '«يا ليلَ الصبِّ متى غدُهُ — أقيامُ الساعةِ موعدُهُ»🌙',
    '"One smile from you lights up even the darkest room in an instant 💡🌸"',
    '«وحقِّكِ لو أنِّي أقدِرُ ما فارقتُ — وما كانَ للعينِ أن تنامَ لحظةً»💤',
    '"Every love song suddenly makes total sense whenever I look at you 🎼"',
    '«أحبُّكِ يا باسبوسةُ حتى الثريَّا — وأشتاقُ إليكِ كشوقِ البحرِ للشطآنِ»🌊',
    '"My heart belongs to you today, tomorrow, and for all eternity ♾️"',
    '«وما سُمِّيَتِ الجنَّةُ الخُلدَ باطلاً — إذا كانَ حبُّكِ فيها ولسنا بمُبعَدِ»🌺',
    '"You are my favorite person to laugh with, dream with, and love forever 💭💗"',
    '«وكيفَ احتِمالي للفراقِ وإنَّني — بغيرِ لقائِكِ لا أُطيقُ الزمانا»💔',
    '"Thank you for filling my life with endless warmth, laughter, and joy ☀️"',
    '«بكِ استبشرَتْ أيامِيَ الغُرُّ كلُّها — وعادَ الزمانُ المُدبِرُ مُقبِلا»🌟',
    '"Your intelligence amazes me, your heart humbles me, and your love heals me 🩺✨"',
    '«أَرَى كلَّ شيءٍ يشهدُ اللهَ وحدَهُ — ويخبِرُ عن حُبِّكِ قلبِيَ الذي ذابا»✨',
    '"Even on the busiest days, my mind always finds its way back to you 🧭💕"',
    '«مُنِيَ القلبُ مِن أهوى بنظرةِ عينٍ — وعسى أن يُوافِيَ الفرَجُ المُدانا»',
    '"My favorite place in the whole wide world is right next to you 🌍❤️"',
    '«تعالَي نسرِق من عُمرِنا — لحظةَ حبٍّ لم يخُنها الزمانُ»💞',
    '"God truly blessed me when our paths crossed, Dr. Basbosa 🙏💖"',
    '«وإذا المرءُ لم يَعشَق فليسَ بعائشٍ — عيشَ الحياةِ فكُن عاشِقاً أو مُتْ بها»🌹',
    '"The sweetest doctor in the world deserves the sweetest day every single day 🍬🩺"',
    '«لعَمرِي لقد أصبحتِ في القلبِ منزلاً — رفيعاً كمنزِلِ الكواكبِ في السماءِ»',
    '"Nothing feels impossible when I have your love cheering me on 🚀❤️"',
    '«وما أنا إلا القلمُ يكتبُكِ — وما الحبُّ إلا ما تُلهِمينَ الكلامَ»📝',
    '"A single text from you still gives me the biggest butterflies in my stomach 🦋"',
    '«يا مَن هواهُ حياتِي ودِيني — وزادِي في الليالي والسِّنينا»💖',
    '"Your heart is made of pure gold, and I will cherish it forever 💛"',
    '«وددتُ بأنَّ العمرَ يُعطَى مِراراً — وما هوَ إلا أن أكونَ بقُربِكِ»🌙',
    '"May your patients be healed, your exams be easy, and your heart be full of joy 🩺🌟"',
    '«ما في الوجودِ جمالٌ غيرُ جمالِكِ — ولا في الحياةِ بهاءٌ غيرُ بهائِكِ»🌸',
    '"Just listening to music and picturing your smile makes everything okay 🎧✨"',
    '«شكرتُكِ يا باسبوسةُ شكرَ الغيثِ — حينَ يُحيِي الأرضَ بعدَ طولِ الجدبِ»',
    '"No matter how far apart we are, our hearts beat in perfect sync 💓📡"',
    '«كيفَ للقلبِ أن يصبِرَ ساعةً — عن حبيبٍ هوَ للقلبِ ضوءٌ وهواءُ»🫶',
    '"Your hugs feel like wrapped-up warmth and ultimate comfort 🫂🧸"',
    '«قولِي لقلبِي: أنتَ حرٌّ — قالَ: كيفَ وهوَ في يدِها أسيرُ»🔐',
    '"With you, every day feels like Valentine\'s Day 💌🌹"',
    '«كُتِبَ الحبُّ بيني وبينَكِ أزلاً — حينَ كتَبَ اللهُ للعاشقينَ لقاءَهُم»📖',
    '"I love the way your eyes sparkle when you talk about your passions ✨👁️"',
    '«وأنتِ الدواءُ وأنتِ الداءُ — وأنتِ الرجاءُ لقلبٍ شقيِّ»💊',
    '"Every love story is beautiful, but ours is by far my favorite 📖❤️"',
    '«أهواكِ يا مَن في فؤادي ذِكرُها — كنورِ الصباحِ يُشرِقُ في ظلامِ الليلِ»🌄',
    '"If kisses were snowflakes, I would send you a never-ending winter blizzard ❄️💋"',
    '«إنِّي وإن كنتُ الأخيرَ زمانُهُ — لآتٍ بما لم تستطِعهُ الأوائلُ»👑',
    '"You make my world infinitely brighter just by being in it 🌟🌍"',
    '«حياتِي لكِ يا باسبوسةُ وقفٌ — وعُمرِي في هواكِ رهنُ خدمَه»',
    '"Dr. Basbosa, you make curing hearts look effortless 🥰🩺"',
    '«رأيتُكِ فارتاحَ قلبِيَ بعدَ طولِ — تعبٍ كانَ يُثقِلُ روحِي ويُضنِيها»',
    '"There are billions of people on Earth, but only one Dr. Basbosa for me 🪐❤️"',
    '«إذا كانَ حبُّكِ قَدَرِي فلا أريدُ — سوى هذا القَدَرِ في دُنيايَ والآخِرَه»🤲',
    '"I will love you through every season, every storm, and every celebration 🍂🌸"',
    '«كلُّ ليلةٍ أحلمُ فيها بكِ — هيَ أجملُ ليالِي العُمُرِ دونَ استثناءٍ»🌙',
    '"Thank you for being my rock, my lover, and my dearest best friend 🤝❤️"',
    '«لا تسأَلِي عن حبِّي فإنَّ قلبِي — أعيا عليَّ وأعجزَ عن وصفِهِ»💭',
    '"I don\'t need the stars when I have the radiance of your eyes 🌌👁️"',
    '«باسبوسةُ في خاطِرِي وفي سُويدا — القلبِ بيتٌ أسكنتُهُ دهرَ الدهورِ»🏡',
    '"You are sweeter than basbosa and more precious than rubies 🍯💎"',
    '«أمَا إنَّ للعينينِ دوراً جميلاً — حينَ يكتُبانِ ما يعجزُ عنهُ اللسانُ»',
    '"May angels watch over you and keep your gentle heart safe always 👼💕"',
    '«وددتُ لو أنَّ الزمانَ وقَفَ بي — ساعةً أنظرُ فيها إلى وجهِكِ الجميلِ»',
    '"My heart is forever tuned to your frequency 📻💖"',
    '«أنتِ يا باسبوسةُ أغلى من الذهبِ — وأطيبُ من أريجِ المسكِ والعنبَرِ»💎',
    '"With every passing day, I discover a hundred new reasons to adore you 📈❤️"',
    '«لا أملِكُ إلا الشعرَ أُهدِيهِ لكِ — ولو أملكتُ الدنيا لأهديتُها جميعاً»🎁',
    '"I can conquer the entire world with one hand, as long as you are holding the other 🛡️🤝"',
    '«وطالَ اشتياقِي للقاءٍ يجمعُنا — كاشتياقِ الغديرِ للسحابِ المُمطِرِ»',
    '"I thank the stars above every single night for blessing me with you 🌠🙏"',
    '«كلُّ الحروفِ تبدأُ بكِ وتنتهِي — وكلُّ الكلماتِ ترجعُ إليكِ في آخِرِها»🔤',
    '"Dr. Basbosa, you make every heartbeat sound like poetry 🩺📜"',
    '«أحبُّكِ يا باسبوسةُ حبَّ الأرضِ — للمطرِ وحبَّ القمرِ للبحرِ الأزرقِ»🌊',
    '"You are the song stuck in my head that I never want to turn off 🔁🎶"',
    '«أيُّها الليلُ الطويلُ أَلا انجَلِ — بصُبحٍ وما الإصباحُ منكَ بأمثَلِ»🌅',
    '"You and me against the world, always and forever 🏰❤️"',
    '«إذا نحنُ أدلجنا وأنتِ أمامَنا — كفى بطلوعِ النجمِ في الليلِ هادِيا»🌟',
    '"You are my paradise, my sanctuary, and my peace 🕊️🌸"',
    '«نَعَمْ أنا مَجنونٌ ولكنَّ جُنُونِي — هوَ الحبُّ وهلْ في الحبِّ مَن لامَ مجنونَه»💝',
    '"Forever cheering for my doctor, my angel, my queen, Dr. Basbosa 👑🩺"',
  
  ];

  static int _lastIndex = -1;
  late int _currentIndex;
  bool _loved = false;

  // Floating love particle waves
  final List<_LoveParticle> _particles = [];
  final Random _random = Random();

  @override
  void initState() {
    super.initState();

    // Pick a new random quote each time the screen/card mounts
    int nextIndex;
    if (_loveQuotes.length > 1) {
      do {
        nextIndex = _random.nextInt(_loveQuotes.length);
      } while (nextIndex == _lastIndex);
    } else {
      nextIndex = 0;
    }
    _lastIndex = nextIndex;
    _currentIndex = nextIndex;

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    );
    if (!WidgetsBinding.instance.runtimeType.toString().contains('Test')) {
      _pulseController.repeat(reverse: true);
    }

    _scaleAnimation = Tween<double>(begin: 0.92, end: 1.12).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOutSine),
    );

    _glowAnimation = Tween<double>(begin: 0.20, end: 0.55).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  void _triggerEmojiWave(TapUpDetails details, Size cardSize) {
    HapticFeedback.mediumImpact();
    final emojis = ['💖', '💕', '✨', '❤️', '🩺', '🌸', '💓', '🌟', '🥰', '💌'];
    final tapOffset = details.localPosition;

    // Generate burst wave of 14 particles from tap location
    for (int i = 0; i < 14; i++) {
      final angle = _random.nextDouble() * 2 * pi;
      final speed = 70.0 + _random.nextDouble() * 120.0;
      final emoji = emojis[_random.nextInt(emojis.length)];
      final particle = _LoveParticle(
        id: UniqueKey().toString(),
        emoji: emoji,
        origin: tapOffset,
        velocity: Offset(cos(angle) * speed, sin(angle) * speed - 60.0),
        size: 16.0 + _random.nextDouble() * 14.0,
      );

      _particles.add(particle);
    }

    setState(() {
      _currentIndex = (_currentIndex + 1) % _loveQuotes.length;
      _lastIndex = _currentIndex;
      _loved = true;
    });
  }

  void _onParticleTick(String id) {
    setState(() {
      _particles.removeWhere((p) => p.id == id);
    });
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final isTablet = Adaptive.isTablet(context);
    final width = MediaQuery.sizeOf(context).width;
    final isCompact = width < 360;

    // Adaptive sizing
    final cardPaddingH = isTablet ? 20.0 : (isCompact ? 12.0 : 16.0);
    final cardPaddingV = isTablet ? 18.0 : (isCompact ? 11.0 : 14.0);
    final heartSize = isTablet ? 24.0 : (isCompact ? 18.0 : 21.0);
    final quoteFontSize = isTablet ? 14.0 : (isCompact ? 11.5 : 12.8);
    final effectiveMargin =
        widget.margin ?? const EdgeInsets.only(top: 14, bottom: 6);
    final effectiveRadius = widget.borderRadius ?? BorderRadius.circular(22);

    return AnimatedBuilder(
      animation: _glowAnimation,
      builder: (context, child) {
        return Container(
          margin: effectiveMargin,
          decoration: BoxDecoration(
            borderRadius: effectiveRadius,
            boxShadow: [
              BoxShadow(
                color: const Color(0xFFFF2A85)
                    .withValues(alpha: _glowAnimation.value),
                blurRadius: 28,
                spreadRadius: -2,
                offset: const Offset(0, 8),
              ),
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.35),
                blurRadius: 20,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: effectiveRadius,
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final isHeightConstrained = constraints.maxHeight.isFinite &&
                      constraints.maxHeight < 160;
                  final effectivePaddingV = isHeightConstrained
                      ? (isCompact ? 8.0 : 10.0)
                      : cardPaddingV;
                  final effectiveQuoteSize = isHeightConstrained
                      ? (isCompact ? 11.0 : 12.0)
                      : quoteFontSize;
                  final effectiveGap = isHeightConstrained ? 3.0 : 5.0;

                  return Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Container(
                        height: constraints.maxHeight.isFinite
                            ? constraints.maxHeight
                            : null,
                        decoration: BoxDecoration(
                          borderRadius: effectiveRadius,
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [
                              const Color(0xFFFF2A85).withValues(alpha: 0.28),
                              const Color(0xFF320822).withValues(alpha: 0.65),
                              const Color(0xFF14020F).withValues(alpha: 0.85),
                            ],
                          ),
                          border: Border.all(
                            color: const Color(0xFFFF2A85)
                                .withValues(alpha: 0.42),
                            width: 1.4,
                          ),
                        ),
                        child: Material(
                          color: Colors.transparent,
                          child: InkWell(
                            borderRadius: effectiveRadius,
                            onTapUp: (details) => _triggerEmojiWave(
                              details,
                              Size(constraints.maxWidth, 120),
                            ),
                            splashColor: const Color(0xFFFF2A85)
                                .withValues(alpha: 0.25),
                            highlightColor: Colors.transparent,
                            child: Padding(
                              padding: EdgeInsets.symmetric(
                                horizontal: cardPaddingH,
                                vertical: effectivePaddingV,
                              ),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.center,
                                children: [
                                  // Pulsing Neon Heart with Glow halo
                                  ScaleTransition(
                                    scale: _scaleAnimation,
                                    child: Container(
                                      padding: EdgeInsets.all(isCompact ? 9 : 11),
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        gradient: const LinearGradient(
                                          begin: Alignment.topLeft,
                                          end: Alignment.bottomRight,
                                          colors: [
                                            Color(0xFFFF2A85),
                                            Color(0xFFBA085B),
                                          ],
                                        ),
                                        boxShadow: [
                                          BoxShadow(
                                            color: const Color(0xFFFF2A85)
                                                .withValues(alpha: 0.65),
                                            blurRadius: 16,
                                            spreadRadius: 2,
                                          ),
                                        ],
                                      ),
                                      child: Icon(
                                        _loved
                                            ? Icons.favorite_rounded
                                            : Icons.favorite_rounded,
                                        color: Colors.white,
                                        size: heartSize,
                                      ),
                                    ),
                                  ),
                                  SizedBox(width: isCompact ? 10 : 15),

                                  // Text with AnimatedSwitcher for smooth message cross-fade & slide
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Row(
                                          mainAxisAlignment:
                                              MainAxisAlignment.spaceBetween,
                                          children: [
                                            Flexible(
                                              child: Text(
                                                'MELODY OF MY HEART',
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: TextStyle(
                                                  color: const Color(0xFFFF85BC),
                                                  fontSize: isCompact ? 8.5 : 10,
                                                  fontWeight: FontWeight.w900,
                                                  letterSpacing: 1.2,
                                                ),
                                              ),
                                            ),
                                            const SizedBox(width: 6),
                                            Container(
                                              padding: EdgeInsets.symmetric(
                                                horizontal: isCompact ? 6 : 8,
                                                vertical: 3,
                                              ),
                                              decoration: BoxDecoration(
                                                color: const Color(0xFFFF2A85)
                                                    .withValues(alpha: 0.25),
                                                borderRadius:
                                                    BorderRadius.circular(10),
                                                border: Border.all(
                                                  color: const Color(0xFFFF2A85)
                                                      .withValues(alpha: 0.40),
                                                  width: 0.8,
                                                ),
                                              ),
                                              child: Row(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  Icon(
                                                    Icons.auto_awesome_rounded,
                                                    size: isCompact ? 9 : 10,
                                                    color: const Color(0xFFFF85BC),
                                                  ),
                                                  const SizedBox(width: 4),
                                                  Text(
                                                    'Dr. Basbosa 💕',
                                                    style: TextStyle(
                                                      color: Colors.white,
                                                      fontSize:
                                                          isCompact ? 9.5 : 10.5,
                                                      fontWeight:
                                                          FontWeight.w800,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ],
                                        ),
                                        SizedBox(height: effectiveGap),

                                        // Animated quote message
                                        AnimatedSwitcher(
                                          duration: const Duration(
                                              milliseconds: 350),
                                          switchInCurve: Curves.easeOutCubic,
                                          switchOutCurve: Curves.easeInCubic,
                                          transitionBuilder:
                                              (child, animation) {
                                            return FadeTransition(
                                              opacity: animation,
                                              child: SlideTransition(
                                                position: Tween<Offset>(
                                                  begin:
                                                      const Offset(0.0, 0.15),
                                                  end: Offset.zero,
                                                ).animate(animation),
                                                child: child,
                                              ),
                                            );
                                          },
                                          child: Text(
                                            _loveQuotes[_currentIndex],
                                            key: ValueKey<int>(_currentIndex),
                                            maxLines: isHeightConstrained ? 2 : 4,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                              color: Colors.white,
                                              fontSize: effectiveQuoteSize,
                                              fontWeight: FontWeight.w600,
                                              fontStyle: FontStyle.italic,
                                              height: 1.3,
                                            ),
                                          ),
                                        ),

                                        SizedBox(height: effectiveGap),
                                        Row(
                                          mainAxisAlignment:
                                              MainAxisAlignment.spaceBetween,
                                          children: [
                                            Flexible(
                                              child: Text(
                                                '— Eng. Eslam ✨',
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: TextStyle(
                                                  color: const Color(0xFFFF85BC),
                                                  fontSize: isCompact ? 9.5 : 11,
                                                  fontWeight: FontWeight.w800,
                                                  letterSpacing: 0.4,
                                                ),
                                              ),
                                            ),
                                            const SizedBox(width: 6),
                                            Flexible(
                                              child: Text(
                                                'Tap for wave of love 💌',
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                textAlign: TextAlign.end,
                                                style: TextStyle(
                                                  color: p.textTertiary
                                                      .withValues(alpha: 0.70),
                                                  fontSize:
                                                      isCompact ? 8.5 : 9.5,
                                                  fontWeight: FontWeight.w600,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),

                      // Floating Animated Emoji Waves
                      for (final particle in _particles)
                        _AnimatedFloatingEmoji(
                          key: ValueKey(particle.id),
                          particle: particle,
                          onCompleted: () => _onParticleTick(particle.id),
                        ),
                    ],
                  );
                },
              ),
            ),
          ),
        );
      },
    );
  }
}

class _LoveParticle {
  final String id;
  final String emoji;
  final Offset origin;
  final Offset velocity;
  final double size;

  _LoveParticle({
    required this.id,
    required this.emoji,
    required this.origin,
    required this.velocity,
    required this.size,
  });
}

class _AnimatedFloatingEmoji extends StatefulWidget {
  final _LoveParticle particle;
  final VoidCallback onCompleted;

  const _AnimatedFloatingEmoji({
    super.key,
    required this.particle,
    required this.onCompleted,
  });

  @override
  State<_AnimatedFloatingEmoji> createState() => _AnimatedFloatingEmojiState();
}

class _AnimatedFloatingEmojiState extends State<_AnimatedFloatingEmoji>
    with SingleTickerProviderStateMixin {
  late final AnimationController _anim;

  @override
  void initState() {
    super.initState();
    _anim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 950),
    )..forward().then((_) => widget.onCompleted());
  }

  @override
  void dispose() {
    _anim.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _anim,
      builder: (context, child) {
        final t = _anim.value;
        // Float outward and upward with slight gravity deceleration
        final dx = widget.particle.origin.dx +
            widget.particle.velocity.dx * (t * 0.9);
        final dy = widget.particle.origin.dy +
            widget.particle.velocity.dy * t +
            (40.0 * t * t);

        final opacity = (1.0 - t).clamp(0.0, 1.0);
        final scale = (0.5 + t * 0.8).clamp(0.0, 1.4);

        return Positioned(
          left: dx - (widget.particle.size / 2),
          top: dy - (widget.particle.size / 2),
          child: IgnorePointer(
            child: Opacity(
              opacity: opacity,
              child: Transform.scale(
                scale: scale,
                child: Text(
                  widget.particle.emoji,
                  style: TextStyle(
                    fontSize: widget.particle.size,
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
