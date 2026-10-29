# StickerSwap 🔄

<p align="center">
  <img src="assets/icon/logo.png" width="130" height="130" alt="StickerSwap Logo" style="border-radius: 26px;" />
</p>

<p align="center">
  <b>Telegram'daki çıkartma (sticker) paketlerini tek tıkla doğrudan WhatsApp'a aktaran modern Flutter uygulaması.</b>
</p>

<p align="center">
  <img src="https://img.shields.io/badge/Platform-Android-green.svg" alt="Platform: Android" />
  <img src="https://img.shields.io/badge/Flutter-3.41%2B-blue.svg" alt="Flutter" />
  <img src="https://img.shields.io/badge/Dart-3.11%2B-0175C2.svg" alt="Dart" />
  <img src="https://img.shields.io/badge/License-MIT-purple.svg" alt="License" />
</p>

---

## 🚀 Öne Çıkan Özellikler

- 📲 **Telegram Hesabınızla Doğrudan Çekme:** Telefon numaranız ve onay kodunuzla güvenli bir şekilde bağlanın; Telegram hesabınızda yüklü olan tüm çıkartma paketlerini anında listeleyin.
- 🎬 **Tam Hareketli Çıkartma Desteği (Animated WebP):** Telegram'ın hareketli ve video (.webm / .tgs) çıkartmaları donanım destekli FFmpeg motoru ile WhatsApp standartlarında **Animasyonlu WebP (512x512 piksel, <500 KB, 20-30 fps)** formatına dönüştürülür ve WhatsApp'a hareketli olarak eklenir!
- 🔄 **Telegram'dan 'Paylaş' ile Doğrudan Aktarım:** Telegram uygulamasında herhangi bir çıkartma paketinde "Paylaş" butonuna bastığınızda StickerSwap otomatik açılır ve paketi içeri aktarır.
- ⚡ **Bağlantı ile Kolay Aktarım:** Telegram bağlantısını (`https://t.me/addstickers/paket_adi`) yapıştırarak da dilediğiniz paketi anında indirebilirsiniz.
- 📐 **WhatsApp Standartlarına %100 Uyum:**
  - Tam **512x512 piksel** şeffaf kanvas uyarlaması.
  - Orantılı ölçekleme ve WhatsApp tavsiyesi 16px kenar boşluğu.
  - Otomatik **WebP** sıkıştırması (< 100 KB statik, < 500 KB hareketli).
  - Otomatik **96x96 piksel** tepsi (tray) simgesi üretimi (< 50 KB).
- 🧩 **Akıllı 30 Çıkartma Sınırı Yönetimi:** WhatsApp tek bir pakette en az 3, en fazla 30 çıkartmaya izin verir. 30'dan fazla çıkartma içeren paketler otomatik olarak **Bölüm 1, Bölüm 2** şeklinde parçalara ayrılır.
- 🎨 **Önizleme & Seçici Aktarım:** Paketteki tüm çıkartmaları grid üzerinde inceleyebilir, istemediklerinizi çıkarıp yalnızca beğendiklerinizi WhatsApp'a aktarabilirsiniz.
- 💾 **Yerel Paket Kütüphanesi ("Paketlerim"):** İndirdiğiniz ve hazırladığınız paketler yerel depolamada saklanır; dilediğiniz zaman tek tıkla tekrar ekleyebilirsiniz.
- 🏷️ **Özelleştirilebilir Yayıncı Adı:** WhatsApp çıkartma tepsisinde görünecek yazar/yayıncı adını kişiselleştirebilirsiniz.
- 🌙 **Modern & Akıcı Tasarım:** Canlı degradeler, koyu tema, glassmorphism kartlar ve akıcı mikro-animasyonlar.

---

## 📱 Ekran Görüntüleri & Akış

1. **Aktar (Ana Sayfa):** Çıkartma bağlantısı yapıştırma, hızlı örnek paket çipleri ve özellik tanıtımları.
2. **Önizleme & Seçim:** Çıkartmaların görsel önizlemesi, emojileri, seçim onay kutuları ve "WhatsApp'a Aktar" butonu.
3. **Paketlerim:** Yerel olarak işlenmiş paketler, WhatsApp durumu ("Yüklü / Bekliyor") ve yönetim butonları.
4. **Ayarlar:** Bot Token yönetimi, canlı bağlantı testi, @BotFather adım adım kurulum rehberi ve yayıncı adı seçimi.

---

## 🛠️ Kurulum & Çalıştırma (Android)

### Gereksinimler
- [Flutter SDK](https://docs.flutter.dev/get-started/install) (3.24 veya üstü)
- Android Studio / Android SDK (API Seviyesi 21+)
- WhatsApp veya WhatsApp Business yüklü fiziksel bir Android cihaz ya da emülatör

### Adımlar

1. **Bağımlılıkları İndirin:**
   ```bash
   flutter pub get
   ```

2. **Projeyi Derleyin ve Çalıştırın:**
   ```bash
   flutter run
   ```

3. **Release APK Üretmek İçin:**
   ```bash
   flutter build apk --release
   ```

---

## 🤖 Kendi Telegram Bot Tokenınızı Nasıl Alırsınız?

StickerSwap varsayılan bir bot yapılandırması içerir, ancak kendi özel Telegram botunuzu kullanmak isterseniz 30 saniyede alabilirsiniz:

1. Telegram uygulamanızda **[@BotFather](https://t.me/BotFather)** botunu açın.
2. `/newbot` komutunu gönderin.
3. Botunuz için bir isim (ör: `BenimStickerBotum`) ve kullanıcı adı (ör: `BenimStickerBot_bot`) belirleyin.
4. BotFather'ın size ilettiği HTTP API Token'ı kopyalayın (`123456789:ABCdefGhIJK...`).
5. **StickerSwap > Ayarlar** sekmesine gelip token'ı yapıştırın ve **Test Et** butonuna basın.

---

## 🏗️ Proje Mimarisi

```
stickerswap/
├── android/                   # Android yapılandırması, izinler ve WhatsApp ContentProvider
│   └── app/src/main/
│       └── AndroidManifest.xml # INTERNET izni ve WhatsApp queries tanımları
├── assets/
│   └── icon/                  # Uygulama logosu
├── lib/
│   ├── main.dart              # Uygulama başlangıcı ve tema ayarları
│   ├── models/
│   │   ├── telegram_sticker.dart     # Telegram çıkartma veri modeli
│   │   ├── telegram_sticker_set.dart # Telegram paket veri modeli
│   │   └── saved_pack.dart           # Yerel WhatsApp çıkartma paketi modeli
│   ├── services/
│   │   ├── telegram_service.dart     # Telegram Bot API istemcisi
│   │   ├── sticker_processor.dart    # 512x512 WebP & 96x96 PNG dönüştürücü
│   │   ├── whatsapp_service.dart     # WhatsApp Stickers Handler & Intent köprüsü
│   │   └── storage_service.dart      # SharedPreferences yerel veri yönetimi
│   ├── theme/
│   │   └── app_theme.dart            # Koyu tema, renk paleti ve Google Fonts tipografisi
│   ├── widgets/
│   │   ├── gradient_button.dart      # Özel degrade buton bileşeni
│   │   └── status_badge.dart         # Durum etiketleri
│   └── screens/
│       ├── main_navigation_screen.dart # Alt gezinme çubuğu (Bottom Navigation)
│       ├── home_screen.dart           # Bağlantı girişi ve örnek paketler
│       ├── pack_preview_screen.dart   # Çıkartma önizleme, seçim ve aktarım
│       ├── my_packs_screen.dart       # İndirilen yerel paketler kütüphanesi
│       └── settings_screen.dart       # Token ve yayıncı ayarları
└── test/
    └── widget_test.dart       # Bağlantı ayrıştırma ve model birim testleri
```

---

## 🔒 İzinler & Android Uyumluluğu

- `android.permission.INTERNET`: Telegram API'sinden çıkartma dosyalarını indirmek için gereklidir.
- `queries`: Android 11+ (API 30+) paket görünürlük kuralı gereğince `com.whatsapp`, `com.whatsapp.w4b` ve Telegram uygulamaları manifest dosyasında sorgulanabilir olarak bildirilmiştir.
- `ContentProvider`: WhatsApp'ın çıkartma görsellerine erişebilmesi için `${applicationId}.stickercontentprovider` yetkilisi tanımlanmıştır.

---

## 📄 Lisans

Bu proje MIT lisansı ile lisanslanmıştır.
