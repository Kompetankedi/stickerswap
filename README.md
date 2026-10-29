# StickerSwap 🔄

<p align="center">
  <img src="assets/icon/logo.png" width="120" height="120" alt="StickerSwap Logo" style="border-radius: 24px;" />
</p>

<p align="center">
  <b>Telegram'daki statik, animasyonlu (.tgs) ve video (.webm) çıkartma paketlerini tek tıkla doğrudan WhatsApp'a aktaran modern, sade ve çift temalı Flutter uygulaması.</b>
</p>

<p align="center">
  <img src="https://img.shields.io/badge/Platform-Android-green.svg" alt="Platform: Android" />
  <img src="https://img.shields.io/badge/Flutter-3.41%2B-blue.svg" alt="Flutter" />
  <img src="https://img.shields.io/badge/Dart-3.11%2B-0175C2.svg" alt="Dart" />
  <img src="https://img.shields.io/badge/Version-v1.0.0-orange.svg" alt="Version" />
  <img src="https://img.shields.io/badge/License-MIT-purple.svg" alt="License" />
</p>

---

## 🚀 Öne Çıkan Özellikler

- ⚡ **Hızlı Bağlantı ile İçe Aktarma:** Herhangi bir Telegram çıkartma paketi bağlantısını (`https://t.me/addstickers/paket_adi`) veya doğrudan paket adını girerek tüm çıkartmaları saniyeler içinde çekin.
- 🤖 **Telegram Bot API & Özel Bot Token Desteği:**
  - Kullanıcılar kendi Telegram bot tokenlarını tanımlayabilir.
  - Uygulama içinde entegre **Adım Adım Bot Token Alma Rehberi** (`@BotFather` doğrudan bağlantısı ve tek tıkla komut kopyalama).
  - Canlı token doğrulama ve test motoru.
- 🎬 **Gelişmiş Çıkartma Desteği & Canlı Önizleme:**
  - **Statik Çıkartmalar:** `.webp` ve `.png` formatları.
  - **Animasyonlu Lottie:** `.tgs` çıkartmaları.
  - **Video Çıkartmalar:** `.webm` (VP9) formatları.
  - Uygulama içinde çıkartmaların hareketlerini oynatan **Canlı Önizleme Vitrini** ve tam ekran detay inceleme penceresi.
- 📐 **WhatsApp Standartlarına %100 Uyum:**
  - Tam **512x512 piksel** şeffaf kanvas yerleşimi ve 16px kenar payı.
  - Otomatik **96x96 piksel** tepsi (tray) simgesi üretimi (< 50 KB).
  - WhatsApp dosya boyutu optimizasyonu (statik < 100 KB, hareketli < 500 KB).
- 🧩 **Akıllı Çoklu Paket (Chunk) Yönetimi:**
  - WhatsApp'ın paket başına 30 çıkartma sınırı doğrultusunda, 30'dan fazla çıkartma içeren paketleri otomatik olarak parçalara ayırma (Örn: Parça 1, Parça 2...).
- 🎨 **Sade, ve Gözü Yormayan Çift Tema:**
  - ☀️ **Açık Tema (Beyaz / Mavi):** Ferah, gözü yormayan minimalist arayüz.
  - 🌙 **Koyu Tema (Siyah / Mavi):** Derin siyahlar ve kurumsal mavi tonları.
  - Üst çubuktan tek dokunuşla anında geçiş ve Ayarlar'dan görsel tema kartı seçimi.
- 💾 **Paketlerim (Yerel Depolama):**
  - İndirilen ve WhatsApp'a aktarılan paketler cihazda saklanır; dilediğiniz zaman tek tıkla yeniden WhatsApp'a eklenebilir.
- 🏷️ **Özelleştirilebilir Yayıncı Adı:**
  - WhatsApp çıkartma tepsisinde görünecek yazar/yayıncı adını özelleştirebilme.

---

## 📱 Ekranlar & Kullanım Akışı

1. **Ana Menü (Aktar):**
   - Çıkartma bağlantısı veya adı giriş alanı.
   - Pano kontrolü (otomatik yapıştırma) ve hızlı paket çekme.
   - Bot Token durum etiketi, token rehber butonu ve anlık tema geçiş düğmesi.
2. **Önizleme & Seçim Ekranı:**
   - Paketin başlığı, çıkartma sayısı ve türü (Statik / Lottie / Video).
   - Canlı hareketli önizleme vitrini (dokunulan çıkartmayı canlı döngüde oynatır).
   - Filtreler (Tümü, Seçili, Kalan), emoji arama ve toplu seçim araçları.
   - WhatsApp'a aktarım ilerleme çubuğu ve durum bilgisi.
3. **Paketlerim:**
   - Yerel kütüphanede kayıtlı paketler, çıkartma sayıları ve türleri.
   - WhatsApp'a tek tıkla tekrar ekleme ve silme yönetimi.
4. **Ayarlar:**
   - Görsel tema seçici (Açık Beyaz/Mavi & Koyu Siyah/Mavi).
   - Bot Token yapılandırması, canlı test ve adım adım kurulum rehberi modalı.
   - Varsayılan çıkartma yayıncısı adı düzenleme.

---

## 🤖 Kendi Telegram Bot Tokenınızı Nasıl Alırsınız?

Uygulama içinde yer alan rehberi kullanarak 1 dakikadan kısa sürede ücretsiz kendi tokenınızı alabilirsiniz:

1. Telegram uygulamanızda **[@BotFather](https://t.me/BotFather)** botunu açın.
2. `/newbot` komutunu gönderin.
3. Botunuz için bir isim (ör: `StickerAktariciBot`) belirleyin.
4. `_bot` ile biten bir kullanıcı adı (ör: `benim_stickerswap_bot`) seçin.
5. BotFather'ın verdiği **HTTP API Token** bilgisini kopyalayın (`123456789:ABCdef...`).
6. **StickerSwap > Ayarlar** sekmesinde Token alanına yapıştırıp **Doğrula & Kaydet** butonuna basın.

---

## 🛠️ Kurulum & Çalıştırma (Android)

### Gereksinimler
- [Flutter SDK](https://docs.flutter.dev/get-started/install) (3.24 veya üstü)
- Android SDK (Min API Seviyesi 21, Target API 34+)
- WhatsApp veya WhatsApp Business yüklü bir Android cihaz / emülatör

### Adımlar

1. **Bağımlılıkları Yükleyin:**
   ```bash
   flutter pub get
   ```

2. **Testleri Çalıştırın:**
   ```bash
   flutter test
   ```

3. **Cihazda Çalıştırın:**
   ```bash
   flutter run
   ```

4. **APK Üretin:**
   ```bash
   flutter build apk --release
   ```

---

## 🏗️ Proje Mimarisi

```
stickerswap/
├── android/                           # Android native yapılandırmaları
│   └── app/src/main/
│       ├── AndroidManifest.xml        # İzinler, queries ve ContentProvider tanımları
│       └── kotlin/.../MainActivity.kt # Video kare çıkarımı için native MethodChannel
├── assets/
│   └── icon/                          # Uygulama logosu ve görseller
├── lib/
│   ├── main.dart                      # Uygulama başlangıcı, ListenableBuilder tema yönetimi
│   ├── models/
│   │   ├── telegram_sticker.dart      # Telegram çıkartma veri modeli
│   │   ├── telegram_sticker_set.dart  # Telegram paket modeli (statik/video/animasyon)
│   │   ├── saved_pack.dart            # Yerel kaydedilen WhatsApp çıkartma paketi modeli
│   │   └── curated_pack.dart          # Paket yardımcı tanımları
│   ├── services/
│   │   ├── telegram_service.dart      # Telegram Bot API istemcisi & token testi
│   │   ├── sticker_processor.dart     # WebP derleyici, video kare işleme & tepsi simgesi
│   │   ├── whatsapp_service.dart      # WhatsApp çıkartma aktarım sağlayıcısı
│   │   └── storage_service.dart       # SharedPreferences yerel veri saklama servisi
│   ├── theme/
│   │   ├── app_theme.dart             # Açık (Beyaz/Mavi) ve Koyu (Siyah/Mavi) tema tanımları
│   │   └── theme_controller.dart      # Dinamik tema yöneticisi
│   ├── widgets/
│   │   ├── animated_sticker_player.dart # Canlı Lottie/Video çıkartma oynatıcı bileşeni
│   │   ├── bot_token_guide_sheet.dart # 5 adımlı interaktif Bot Token rehberi modalı
│   │   ├── glass_card.dart            # Temaya duyarlı sade kart bileşeni
│   │   ├── gradient_button.dart       # Kurumsal buton bileşeni
│   │   └── status_badge.dart          # Durum etiketleri
│   └── screens/
│       ├── main_navigation_screen.dart # Alt gezinme çubuğu (Bottom Navigation)
│       ├── home_screen.dart           # Çıkartma bağlantısı girişi ve ana ekran
│       ├── pack_preview_screen.dart   # Çıkartma seçimi, canlı vitrin ve aktarım
│       ├── my_packs_screen.dart       # Kaydedilen yerel paketler kütüphanesi
│       └── settings_screen.dart       # Tema, Token ve yayıncı ayarları
├── notlar.md                          # Geliştirici yol haritası ve yapılacaklar listesi
├── pubspec.yaml                       # Paket bağımlılıkları ve sürüm yönetimi
└── test/
    └── widget_test.dart               # Birim ve entegrasyon testleri
```

---

## 📌 Geliştirici Notları & Yol Haritası

Devam eden geliştirmeler ve çözülmesi planlanan maddeler [notlar.md](notlar.md) dosyasında kayıt altına alınmıştır:
- WhatsApp animasyonlu WebP standartlarının ve aktarımının pekiştirilmesi.
- 30 çıkartmayı aşan çok parçalı paketlerin aktarım akışının optimize edilmesi.
- Her yeni güncellemede `pubspec.yaml` sürümünün artırılması kuralı.

---

## 📄 Lisans

Bu proje MIT lisansı ile lisanslanmıştır.
