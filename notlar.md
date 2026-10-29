# StickerSwap - Geliştirici Notları & Yapılacaklar (Developer Notes & Roadmap)

---

## 🇹🇷 Türkçe (Turkish)

### 1. Hareketli Çıkartmaların WhatsApp'ta Statik Kalması
- **Sorun:** Çıkartmalar uygulama içi önizlemede canlı ve hareketli olarak oynatılabildiği halde, WhatsApp'a aktarıldıktan sonra WhatsApp sohbetinde statik/hareketsiz olarak kalmaktadır.
- **Yapılacaklar:**
  - WhatsApp'ın kabul ettiği animasyonlu WebP standartları (WebP `ANIM` / `ANMF` chunk'ları, şeffaf arka plan, loop sayısı = 0, dosya boyutu sınırı <= 500 KB, 512x512 piksel) ve Android `ContentProvider`'ın `animated_sticker_pack` alanıyla ilgili doğrulamalar incelenmeli.
  - Video/Lottie'den oluşturulan WebP dosyalarının WhatsApp tarafından animasyon olarak tanınmasını engelleyen dönüştürme veya provider parametreleri tespit edilip düzeltilmeli.

---

### 2. Çok Parçalı Paketlerde Sonsuz Döngü / Askıda Kalma Sorunu
- **Sorun:** 30'dan fazla çıkartma seçildiğinde paket parçalara ayrılmaktadır (Örn: Parça 1/4). İlk parça WhatsApp'a gönderilip kullanıcı WhatsApp'ın "Ekle" butonuna bastıktan sonra uygulama bir sonraki parçaya geçmemekte ve ekranda sonsuz döngüde (loading/freeze) takılı kalmaktadır.
- **Yapılacaklar:**
  - `pack_preview_screen.dart` ve `whatsapp_service.dart` içerisindeki çok parçalı aktarım döngüsü yeniden yapılandırılmalı.
  - WhatsApp'ın `AddThirdPartyStickerPackActivity` intent'inin dönüşü (activity result) doğru şekilde ele alınmalı; kullanıcı onay verdikten veya reddettikten sonra bir sonraki parçaya geçiş güvenli ve kullanıcı kontrollü bir adımla sağlanmalı.

---

### 3. Sade & Kurumsal Tasarım (Neon ve Liquid Glass Efektlerinin Kaldırılması)
- **Sorun:** Tasarımda yer alan neon/parlak renkler ve kartlarda kullanılan "liquid glass" (cam/bulanıklık/parıltılı kenarlık) efektleri göz yormakta ve karmaşık hissettirmektedir.
- **Yapılacaklar:**
  - Neon tonlar yerine sade, kurumsal, gözü yormayan dengeli renk paletleri kullanılmalı.
  - Div/kart benzeri tüm kutulardan (`GlassCard`, bulanık arka planlar, aşırı gölgeler) liquid glass tarzı efektler tamamen kaldırılmalı.
  - Düz, net, minimalist, kontrastı yüksek ve okunabilirliği üst düzey kurumsal kartlar ve bileşenler oluşturulmalı.

---

### 4. Sürüm Numaralandırma Kuralı (Version Increment)
- **Kural:** Her eklenen veya güncellenen özellik/düzeltmeden sonra `pubspec.yaml` dosyasındaki uygulama sürümü birer rakam artırılmalıdır.
- **Örnek:**
  - `1.0.0+1` ➡️ `1.0.1+2`
  - `1.0.1+2` ➡️ `1.0.2+3`

---
---

## 🇬🇧 English

### 1. Animated Stickers Appearing Static in WhatsApp
- **Issue:** Even though animated stickers animate properly in the in-app preview player, they remain completely motionless/static once imported into WhatsApp.
- **Action Items:**
  - Inspect WhatsApp's strict requirements for Animated WebP (`ANIM` / `ANMF` chunks, transparent canvas, loop count = 0, max 500 KB file size, 512x512 resolution) and the Android `ContentProvider`'s `animated_sticker_pack` flag.
  - Identify and fix whatever causes WhatsApp to treat the imported WebP stickers as static images instead of motion stickers.

---

### 2. Multi-Part Pack Export Infinite Loop / Freeze
- **Issue:** When a sticker pack contains more than 30 stickers and is divided into multiple parts (e.g., Part 1/4), the first part is sent to WhatsApp. However, after the user confirms by tapping the "Add" button in WhatsApp, the app does not proceed to the remaining parts and gets stuck in an infinite loading/freeze state.
- **Action Items:**
  - Restructure the multi-part export loop in `pack_preview_screen.dart` and `whatsapp_service.dart`.
  - Properly handle WhatsApp's `AddThirdPartyStickerPackActivity` result so that upon completion/return, the app smoothly advances to the next batch or provides user-directed batch progression.

---

### 3. Clean & Corporate UI (Eliminate Neon Colors & Liquid Glass)
- **Issue:** Neon color accents and liquid glassmorphism (blurs, glossy borders, deep ambient glows) cause visual fatigue and feel overly flashy.
- **Action Items:**
  - Replace neon colors with subtle, corporate, eye-pleasing tones.
  - Remove all liquid glassmorphism effects (e.g. `GlassCard`, backdrop filters, excessive glows) from container cards and dialogs.
  - Implement clean, solid, minimalist, easily readable, and professional components.

---

### 4. Application Versioning Rule
- **Rule:** After every newly added or updated feature/bugfix, the application version in `pubspec.yaml` must be incremented by one patch number.
- **Example:**
  - `1.0.0+1` ➡️ `1.0.1+2`
  - `1.0.1+2` ➡️ `1.0.2+3`
