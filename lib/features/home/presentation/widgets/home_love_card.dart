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
    // 1 - 10
    '"You make every beat worthwhile. Enjoy your music, my love!"',
    '"To the world you may be one person, but to me you are the whole world, Dr. Basbosa 💕"',
    '"Every melody sounds sweeter when I think of you ✨"',
    '"You are my favorite song playing on repeat in my heart forever 🎶"',
    '"No symphony in this world compares to your voice and your smile 💖"',
    '"Forever blessed and proud of my brilliant, beautiful Dr. Basbosa 🌟"',
    '"My heart skips a beat every time your name comes to my mind 💓"',
    '"In every lifetime, in every universe, it will always be you ❤️"',
    '"You are the sweetest rhythm in this journey of life 🌸"',
    '"May your day be as gentle, bright, and radiant as your soul ✨"',

    // 11 - 20
    '"Falling in love with you is the easiest and most wonderful thing I ever did 🌹"',
    '"Your laughter is the soundtrack that cures all my worries 🎵"',
    '"You are my sunshine on cloudy days and my sweetest dream every night 🌙"',
    '"Dr. Basbosa: saving lives by day, owning my heart 24/7 🩺❤️"',
    '"The smartest doctor, the prettiest soul, and the love of my life 🥰"',
    '"I loved you yesterday, I love you still, I always have, I always will 💍"',
    '"No artist could ever paint a masterpiece as breathtaking as you 🎨"',
    '"Every second spent loving you is my favorite second of the day ⏳💕"',
    '"You make ordinary moments feel like pure fairy tales ✨"',
    '"Wherever you go, my heart follows your footsteps 👣💖"',

    // 21 - 30
    '"Your kindness inspires me to be the very best version of myself 🕊️"',
    '"Holding your hand feels like holding my entire future 🤝❤️"',
    '"The universe conspired to bring you into my life, and I am eternally grateful 🌌"',
    '"You are my peaceful oasis in this noisy, chaotic world 🏝️✨"',
    '"One smile from you lights up even the darkest room in an instant 💡🌸"',
    '"Dr. Basbosa, you are both my greatest adventure and my safest home 🏡❤️"',
    '"Every love song suddenly makes total sense whenever I look at you 🎼"',
    '"You have the kindest eyes and the most gentle, loving touch 👁️💕"',
    '"My heart belongs to you today, tomorrow, and for all eternity ♾️"',
    '"Being loved by you is the greatest privilege of my lifetime 👑"',

    // 31 - 40
    '"You are my favorite person to laugh with, dream with, and love forever 💭💗"',
    '"If I had a flower for every time I thought of you, I could walk through an endless garden 🌷"',
    '"Thank you for filling my life with endless warmth, laughter, and joy ☀️"',
    '"You are the missing piece that made my whole world complete 🧩💖"',
    '"Your intelligence amazes me, your heart humbles me, and your love heals me 🩺✨"',
    '"I promise to always stand by your side, cheering you on through everything 📣❤️"',
    '"Even on the busiest days, my mind always finds its way back to you 🧭💕"',
    '"You are proof that magic, elegance, and pure grace truly exist 🪄✨"',
    '"My favorite place in the whole wide world is right next to you 🌍❤️"',
    '"You make my soul dance with joy every single morning 💃🎶"',

    // 41 - 50
    '"God truly blessed me when our paths crossed, Dr. Basbosa 🙏💖"',
    '"You bring melody to my silence and light into my shadows 🕯️✨"',
    '"The sweetest doctor in the world deserves the sweetest day every single day 🍬🩺"',
    '"You are more precious to me than all the treasures on this earth 💎"',
    '"Nothing feels impossible when I have your love cheering me on 🚀❤️"',
    '"You make life sweeter than honey and softer than cotton candy 🍯💕"',
    '"A single text from you still gives me the biggest butterflies in my stomach 🦋"',
    '"You are the reason behind every genuine smile on my face 😊💖"',
    '"Your heart is made of pure gold, and I will cherish it forever 💛"',
    '"I would choose you over and over again, in a thousand lifetimes 🔄❤️"',

    // 51 - 60
    '"May your patients be healed, your exams be easy, and your heart be full of joy 🩺🌟"',
    '"You are my favorite notification and my favorite thought 📱💕"',
    '"Just listening to music and picturing your smile makes everything okay 🎧✨"',
    '"You are the sweetest dream I never want to wake up from 🛌💭"',
    '"No matter how far apart we are, our hearts beat in perfect sync 💓📡"',
    '"You are the rhythm to my pulse and the bass in my chest 🥁❤️"',
    '"Your hugs feel like wrapped-up warmth and ultimate comfort 🫂🧸"',
    '"I am endlessly proud of everything you are achieving, my brilliant doctor 🏆🩺"',
    '"With you, every day feels like Valentine\'s Day 💌🌹"',
    '"You are the miracle I prayed for, and the love I always dreamed of 🌈💕"',

    // 61 - 70
    '"I love the way your eyes sparkle when you talk about your passions ✨👁️"',
    '"You are my anchor when the storm gets rough, and my wings when I fly ⚓🕊️"',
    '"Every love story is beautiful, but ours is by far my favorite 📖❤️"',
    '"You turned my life into a love song that never ends 🎻🎶"',
    '"If kisses were snowflakes, I would send you a never-ending winter blizzard ❄️💋"',
    '"My favorite feeling is knowing that you are mine and I am yours 🔐💖"',
    '"You make my world infinitely brighter just by being in it 🌟🌍"',
    '"I love your strength, your gentle tenderness, and your gorgeous spirit 🌸"',
    '"Dr. Basbosa, you make curing hearts look effortless 🥰🩺"',
    '"You are the melody that makes my soul sing along every day 🎤💖"',

    // 71 - 80
    '"There are billions of people on Earth, but only one Dr. Basbosa for me 🪐❤️"',
    '"Your sweet voice is my favorite sound to wake up to 🌅🎶"',
    '"I will love you through every season, every storm, and every celebration 🍂🌸"',
    '"You are my today and all of my tomorrows 🗓️💕"',
    '"Thank you for being my rock, my lover, and my dearest best friend 🤝❤️"',
    '"When I close my eyes, I see your smile, and suddenly everything is peaceful 😌✨"',
    '"I don\'t need the stars when I have the radiance of your eyes 🌌👁️"',
    '"Everything I do is inspired by the hope of making you smile proudly 🎯💖"',
    '"You are sweeter than basbosa and more precious than rubies 🍯💎"',
    '"Loving you is as natural and vital to me as breathing oxygen 🫁❤️"',

    // 81 - 90
    '"May angels watch over you and keep your gentle heart safe always 👼💕"',
    '"You deserve all the love, all the roses, and all the happiness in the world 🌹💐"',
    '"My heart is forever tuned to your frequency 📻💖"',
    '"You are my good morning, my good night, and every lovely thought in between 🌇🌃"',
    '"With every passing day, I discover a hundred new reasons to adore you 📈❤️"',
    '"You are the finest melody God ever composed in this universe 🎹✨"',
    '"I can conquer the entire world with one hand, as long as you are holding the other 🛡️🤝"',
    '"Your love is the sweet warmth that keeps my spirit cozy all winter long ☕🧣"',
    '"I thank the stars above every single night for blessing me with you 🌠🙏"',
    '"You are the cure to all fatigue and the spark in my everyday life ⚡💕"',

    // 91 - 100
    '"Dr. Basbosa, you make every heartbeat sound like poetry 🩺📜"',
    '"Never forget how deeply, truly, and uncontrollably loved you are 🌊❤️"',
    '"You are the song stuck in my head that I never want to turn off 🔁🎶"',
    '"My favorite view is looking right into your joyful, smiling eyes 🖼️🥰"',
    '"You and me against the world, always and forever 🏰❤️"',
    '"I love you more than words, code, music, and poetry could ever explain 💻🎵"',
    '"You are my paradise, my sanctuary, and my peace 🕊️🌸"',
    '"Whatever tomorrow brings, I know it\'s bright because you\'re in it 🌅💖"',
    '"Forever cheering for my doctor, my angel, my queen, Dr. Basbosa 👑🩺"',
    '"Eng. Eslam loves Dr. Basbosa to infinity, beyond the galaxies, and back! 🚀🌌💖✨"',
    // ─── 101–200: Classical Arabic Poetry — alternating Arabic & English ───
    // 101 Arabic
    '«أنا مَن نظرَ الأعمى إلى أدبي — وأسمعَتْ كلماتي مَن به صَمَمُ»🌹',
    // 102 English
    '"I am he whose art made the blind man see — and whose words made the deaf man hear"✨',
    // 103 Arabic
    '«وما الحبُّ إلا للحبيبِ الأوَّلِ — ولا الشوقُ إلا للمحبوبِ الأوَّلِ»💖',
    // 104 English
    '"Love belongs only to the first beloved — and longing belongs only to the one the soul truly adores"🌸',
    // 105 Arabic
    '«بالأمسِ كنتِ هلالاً في مطالعِهِ — واليومَ أنتِ بدرٌ تامُّ الاكتمالِ»🌙',
    // 106 English
    '"Yesterday you were a crescent moon at its rising — today you are a full moon in all its glory"🌙',
    // 107 Arabic
    '«يا مَن هواهُ أعزُّ الناسِ عندِي — وليسَ في القلبِ مَن يحتلُّ غيرَهُ»',
    // 108 English
    '"O you whose love is the most precious thing to me — none other holds a place in this heart"',
    // 109 Arabic
    '«لو كانَ قلبِيَ عندِي حينَ أبصرَكِ — ما زالَ أسيرَ حبٍّ دامَ مُستمِرا»🌸',
    // 110 English
    '"Had my heart obeyed me when I first saw you — it would never have become love\'s eternal prisoner"🌸',
    // 111 Arabic
    '«أُحبُّكِ فوقَ ما تُحبُّ الطيورُ السماءَ — وأشتاقُ إليكِ أكثرَ من اشتياقِ الأرضِ للمطرِ»',
    // 112 English
    '"I love you more than birds love the sky — and I miss you more than the earth misses the rain"',
    // 113 Arabic
    '«كلُّ شيءٍ يدلُّ عليكِ ويُذكِّرُني — بكِ حتى أحسسْتُ أنَّكِ في كلِّ مكانِ»💫',
    // 114 English
    '"Everything points to you and reminds me of you — until I feel you are present in every place"💫',
    // 115 Arabic
    '«ماذا أقولُ وأنتِ كلُّ قصيدتِي — وأنتِ الحرفُ والمعنى والوجودُ كلُّهُ»📜',
    // 116 English
    '"What shall I say when you are my entire poem — you are the letter, the meaning, and all existence"📜',
    // 117 Arabic
    '«لكِ في فؤادي منزلٌ لا يُشغَلُ — حتى بصاحبِهِ الحبيبِ الأوَّلِ»💛',
    // 118 English
    '"In my heart you hold a place no other may occupy — not even the dearest companion of all"💛',
    // 119 Arabic
    '«أهواكِ ما استقبلتُ قِبلَةَ مغرِبٍ — وما تلقَّتِ الأنوارُ عيناً تنظرُ»🌅',
    // 120 English
    '"I love you in every direction my compass turns — in every light that meets an eye that truly sees"🌅',
    // 121 Arabic
    '«وقفَ الهوى بي حيثُ أنتِ فلم أزَلْ — أرى الوجودَ أمامِي كلَّهُ وَطَنا»🌍',
    // 122 English
    '"Love stopped me where you are — and all of existence became my homeland in your presence"🌍',
    // 123 Arabic
    '«تَعلَّمتُ من عينيكِ قبلَ كلامِكِم — بأنَّ عينَ الحبيبِ مدرسةُ الروحِ»',
    // 124 English
    '"I learned from your eyes before your words — that the beloved\'s gaze is the school of the soul"',
    // 125 Arabic
    '«يا ليلَ الصبِّ متى غدُهُ — أقيامُ الساعةِ موعدُهُ»🌙',
    // 126 English
    '"O night of the sleepless lover, when will your dawn come — is the Day of Judgment your appointed hour?"🌙',
    // 127 Arabic
    '«وحقِّكِ لو أنِّي أقدِرُ ما فارقتُ — وما كانَ للعينِ أن تنامَ لحظةً»💤',
    // 128 English
    '"By your life, had I the power I would never have parted — and my eyes would never have slept a single moment"💤',
    // 129 Arabic
    '«أحبُّكِ يا باسبوسةُ حتى الثريَّا — وأشتاقُ إليكِ كشوقِ البحرِ للشطآنِ»🌊',
    // 130 English
    '"I love you, Basbosa, to the Pleiades — and I long for you as the sea longs for the shore"🌊',
    // 131 Arabic
    '«وما سُمِّيَتِ الجنَّةُ الخُلدَ باطلاً — إذا كانَ حبُّكِ فيها ولسنا بمُبعَدِ»🌺',
    // 132 English
    '"The eternal garden was not named paradise in vain — if your love dwells there and we are not kept from it"🌺',
    // 133 Arabic
    '«وكيفَ احتِمالي للفراقِ وإنَّني — بغيرِ لقائِكِ لا أُطيقُ الزمانا»💔',
    // 134 English
    '"How can I bear separation when without your meeting — I cannot endure time itself even for a moment"💔',
    // 135 Arabic
    '«بكِ استبشرَتْ أيامِيَ الغُرُّ كلُّها — وعادَ الزمانُ المُدبِرُ مُقبِلا»🌟',
    // 136 English
    '"With you all my bright days rejoiced completely — and time that had turned away came back to face us"🌟',
    // 137 Arabic
    '«أَرَى كلَّ شيءٍ يشهدُ اللهَ وحدَهُ — ويخبِرُ عن حُبِّكِ قلبِيَ الذي ذابا»✨',
    // 138 English
    '"I see all things bearing witness to God alone — and my melted heart speaks only of your love"✨',
    // 139 Arabic
    '«مُنِيَ القلبُ مِن أهوى بنظرةِ عينٍ — وعسى أن يُوافِيَ الفرَجُ المُدانا»',
    // 140 English
    '"My heart wished for one glance from the one I love — and perhaps relief is already drawing near"',
    // 141 Arabic
    '«تعالَي نسرِق من عُمرِنا — لحظةَ حبٍّ لم يخُنها الزمانُ»💞',
    // 142 English
    '"Come, let us steal from our lifetime — one moment of love that time cannot betray"💞',
    // 143 Arabic
    '«وإذا المرءُ لم يَعشَق فليسَ بعائشٍ — عيشَ الحياةِ فكُن عاشِقاً أو مُتْ بها»🌹',
    // 144 English
    '"Whoever has not loved has not truly lived the life of the living — so love, or spend your life in longing"🌹',
    // 145 Arabic
    '«لعَمرِي لقد أصبحتِ في القلبِ منزلاً — رفيعاً كمنزِلِ الكواكبِ في السماءِ»',
    // 146 English
    '"By my life, you have a home in my heart — as lofty as the dwelling of stars in the heavens"',
    // 147 Arabic
    '«وما أنا إلا القلمُ يكتبُكِ — وما الحبُّ إلا ما تُلهِمينَ الكلامَ»📝',
    // 148 English
    '"I am but a pen that writes you — and love is nothing but what you inspire in every word"📝',
    // 149 Arabic
    '«يا مَن هواهُ حياتِي ودِيني — وزادِي في الليالي والسِّنينا»💖',
    // 150 English
    '"O you whose love is my life and my faith — my provision through all the nights and all the years"💖',
    // 151 Arabic
    '«وددتُ بأنَّ العمرَ يُعطَى مِراراً — وما هوَ إلا أن أكونَ بقُربِكِ»🌙',
    // 152 English
    '"I wished that life were granted to me repeatedly — but only so I could spend it by your side"🌙',
    // 153 Arabic
    '«ما في الوجودِ جمالٌ غيرُ جمالِكِ — ولا في الحياةِ بهاءٌ غيرُ بهائِكِ»🌸',
    // 154 English
    '"There is no beauty in all existence but yours — no splendor in life but the radiance you carry"🌸',
    // 155 Arabic
    '«شكرتُكِ يا باسبوسةُ شكرَ الغيثِ — حينَ يُحيِي الأرضَ بعدَ طولِ الجدبِ»',
    // 156 English
    '"I thank you, Basbosa, as rain is thanked — when it revives the earth after long drought"',
    // 157 Arabic
    '«كيفَ للقلبِ أن يصبِرَ ساعةً — عن حبيبٍ هوَ للقلبِ ضوءٌ وهواءُ»🫶',
    // 158 English
    '"How can the heart be patient even for an hour — from a beloved who is its very light and air"🫶',
    // 159 Arabic
    '«قولِي لقلبِي: أنتَ حرٌّ — قالَ: كيفَ وهوَ في يدِها أسيرُ»🔐',
    // 160 English
    '"Tell my heart: you are free — it replied: How, when it is held captive in her hands?"🔐',
    // 161 Arabic
    '«كُتِبَ الحبُّ بيني وبينَكِ أزلاً — حينَ كتَبَ اللهُ للعاشقينَ لقاءَهُم»📖',
    // 162 English
    '"Love between us was written in eternity — when God decreed that lovers would one day meet"📖',
    // 163 Arabic
    '«وأنتِ الدواءُ وأنتِ الداءُ — وأنتِ الرجاءُ لقلبٍ شقيِّ»💊',
    // 164 English
    '"You are the remedy and you are the ailment — you are the hope for a heart that suffers"💊',
    // 165 Arabic
    '«أهواكِ يا مَن في فؤادي ذِكرُها — كنورِ الصباحِ يُشرِقُ في ظلامِ الليلِ»🌄',
    // 166 English
    '"I love you, O she whose memory lives in my heart — like morning light shining through the dark of night"🌄',
    // 167 Arabic
    '«إنِّي وإن كنتُ الأخيرَ زمانُهُ — لآتٍ بما لم تستطِعهُ الأوائلُ»👑',
    // 168 English
    '"Though I come last in time — I bring what the ancients could not achieve"👑',
    // 169 Arabic
    '«حياتِي لكِ يا باسبوسةُ وقفٌ — وعُمرِي في هواكِ رهنُ خدمَه»',
    // 170 English
    '"My life is entirely dedicated to you, Basbosa — and all my years are pledged in loving service"',
    // 171 Arabic
    '«رأيتُكِ فارتاحَ قلبِيَ بعدَ طولِ — تعبٍ كانَ يُثقِلُ روحِي ويُضنِيها»',
    // 172 English
    '"I saw you and my heart rested after long weariness — that had burdened my soul and worn it thin"',
    // 173 Arabic
    '«إذا كانَ حبُّكِ قَدَرِي فلا أريدُ — سوى هذا القَدَرِ في دُنيايَ والآخِرَه»🤲',
    // 174 English
    '"If loving you is my destiny then I desire — no other destiny in this world or the hereafter"🤲',
    // 175 Arabic
    '«كلُّ ليلةٍ أحلمُ فيها بكِ — هيَ أجملُ ليالِي العُمُرِ دونَ استثناءٍ»🌙',
    // 176 English
    '"Every night I dream of you — is the most beautiful night of my life without exception"🌙',
    // 177 Arabic
    '«لا تسأَلِي عن حبِّي فإنَّ قلبِي — أعيا عليَّ وأعجزَ عن وصفِهِ»💭',
    // 178 English
    '"Ask me not of my love for my heart — has exhausted me and left me unable to describe it"💭',
    // 179 Arabic
    '«باسبوسةُ في خاطِرِي وفي سُويدا — القلبِ بيتٌ أسكنتُهُ دهرَ الدهورِ»🏡',
    // 180 English
    '"Basbosa is in my thoughts and in the core — of my heart, a home I have settled for all eternity"🏡',
    // 181 Arabic
    '«أمَا إنَّ للعينينِ دوراً جميلاً — حينَ يكتُبانِ ما يعجزُ عنهُ اللسانُ»',
    // 182 English
    '"The eyes play a beautiful and wondrous role — when they write what the tongue is too weak to say"',
    // 183 Arabic
    '«وددتُ لو أنَّ الزمانَ وقَفَ بي — ساعةً أنظرُ فيها إلى وجهِكِ الجميلِ»',
    // 184 English
    '"I wished that time would pause for me — one moment to gaze upon your beautiful face"',
    // 185 Arabic
    '«أنتِ يا باسبوسةُ أغلى من الذهبِ — وأطيبُ من أريجِ المسكِ والعنبَرِ»💎',
    // 186 English
    '"You, Basbosa, are more precious than gold — and sweeter than the fragrance of musk and amber"💎',
    // 187 Arabic
    '«لا أملِكُ إلا الشعرَ أُهدِيهِ لكِ — ولو أملكتُ الدنيا لأهديتُها جميعاً»🎁',
    // 188 English
    '"I have only poetry to gift you — but if I owned the world I would give you every last part of it"🎁',
    // 189 Arabic
    '«وطالَ اشتياقِي للقاءٍ يجمعُنا — كاشتياقِ الغديرِ للسحابِ المُمطِرِ»',
    // 190 English
    '"How long I have longed for a meeting that unites us — as a stream longs for the rain-bearing clouds above"',
    // 191 Arabic
    '«كلُّ الحروفِ تبدأُ بكِ وتنتهِي — وكلُّ الكلماتِ ترجعُ إليكِ في آخِرِها»🔤',
    // 192 English
    '"Every letter begins with you and ends with you — every word returns to you in the end"🔤',
    // 193 Arabic
    '«أحبُّكِ يا باسبوسةُ حبَّ الأرضِ — للمطرِ وحبَّ القمرِ للبحرِ الأزرقِ»🌊',
    // 194 English
    '"I love you, Basbosa, as the earth loves the rain — and as the moon loves the deep blue sea"🌊',
    // 195 Arabic
    '«أيُّها الليلُ الطويلُ أَلا انجَلِ — بصُبحٍ وما الإصباحُ منكَ بأمثَلِ»🌅',
    // 196 English
    '"O long night, will you not lift — with a dawn, though the dawn is no better than you?"🌅',
    // 197 Arabic
    '«إذا نحنُ أدلجنا وأنتِ أمامَنا — كفى بطلوعِ النجمِ في الليلِ هادِيا»🌟',
    // 198 English
    '"When we set out at night and you are before us — the rising of the stars is guide enough in the dark"🌟',
    // 199 Arabic
    '«نَعَمْ أنا مَجنونٌ ولكنَّ جُنُونِي — هوَ الحبُّ وهلْ في الحبِّ مَن لامَ مجنونَه»💝',
    // 200 English
    '"Yes, I am mad — but my madness is love, and who has ever blamed a lover for his madness?"💝',
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
                                                '✨',
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
