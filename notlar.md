# StickerSwap - Geliştirici Notları & Yapılacaklar (Developer Notes & Roadmap)

---

## 🇹🇷 Türkçe (Turkish)

### 1. WhatsApp'tan Paketi Kaldırırken "Paket Dosyası Mevcut Değil" Hatası (1. ÖNCELİK)
- **Durum:** ✅ **ÇÖZÜLDÜ & DOĞRULANDI** (Sorun Çözüldü)
- **Test Sonucu:** Android 16 (crDroid 12.13, KernelSU root, Redmi Note 12 Pro 4G) üzerinde canlı ADB ContentProvider sorguları (`query`, `read`, `delete`) ile doğrulanmıştır. Eski/yetim ve mevcut paketlerin WhatsApp "Çıkartmalarım" menüsünden ve harici olarak sorunsuz listelenip hatasız kaldırılabildiği kanıtlanmıştır.
- **Tespit Edilen Kök Nedenler:**
  1. **StickerContentProvider İstisna Fırlatması:** `StickerContentProvider.kt` içerisinde `STICKERS_OF_PACK` sorgusunda paket bulunamadığında boş bir cursor dönmek yerine doğrudan `IllegalArgumentException` fırlatılıyordu. WhatsApp silme işlemi veya detay açılışı öncesinde paketi teyit ederken bu istisnayı aldığında işlemi durdurup arayüzde *"Paket dosyası mevcut değil"* hatası veriyordu.
  2. **Metadata Kolon İsimleri ve Eksik Kolon:** WhatsApp resmi StickerContentProvider spesifikasyonunda beklenen `sticker_pack_publisher_email`, `sticker_pack_publisher_website`, `sticker_pack_privacy_policy_website`, `sticker_pack_license_agreement_website` kolonları ön ek olmadan verilmişti ve `whatsapp_will_not_cache_stickers` kolonu tamamen eksikti.
  3. **openFile Metodunun Eksikliği:** Android `ContentProvider`'da `openFile` override edilmediği için dosya okuma çağrılarında sistem varsayılan `FileNotFoundException: No files supported by provider` hatası dönüyor, dosya boyutu `UNKNOWN_LENGTH` olarak veriliyordu.
  4. **Delete Endpoint'inin Unsupported Kalması:** `delete(...)` metodu `UnsupportedOperationException` fırlatıyordu; bu durum silme isteği atan istemcilerin çökmesine neden oluyordu.
  5. **Dinamik Zaman Damgalı (Non-Deterministic) ID Üretimi:** Aktarım sırasında paket ID'lerine `DateTime.now().millisecondsSinceEpoch` eklenmesi sebebiyle her aktarımda yeni bir ID oluşuyor, WhatsApp'ta kalan eski ID'ler yerel depolamada bulunamadığı için yetim kalarak silinemez hale geliyordu.
- **Yapılan İyileştirmeler:**
  - **Güvenli Cursor ve Hata Yönetimi (`StickerContentProvider.kt`):** Bulunamayan paketler için `IllegalArgumentException` yerine boş MatrixCursor (0 satır) dönülecek şekilde güncellendi. `openFile` metodu eklenerek `AssetFileDescriptor` doğrudan dosya boyutuyla (`file.length()`) servis edildi. `delete(...)` metodu yerel depolama ile senkronize edilerek güvenli silme ve `notifyChange` sağlandı. `insert` ve `update` çağrıları çökmeyecek şekilde zararsız safe dönüşe uyarlandı.
  - **WhatsApp Spesifikasyonuna Tam Uyum (`StickerPackModels.kt`):** WhatsApp resmi spesifikasyonundaki 13 adet metadata kolonu birebir uygulandı (`whatsapp_will_not_cache_stickers` dahil). Emojiler virgül `,` ile ayrıldı.
  - **Zaman Damgası Fallback'i (`StickerPackStorage.kt`):** Eski yetim paketlerin tanınabilmesi için zaman damgası temizleme temelli (timestamp-fallback) esnek ID eşleştirme ve temizleme desteği eklendi.
  - **Deterministik Paket Kimlikleri (`pack_preview_screen.dart`):** Paket ID üretimi deterministik hale getirildi (`${packName}_part${idx}`); gereksiz dinamik timestamp kaldırıldı.
  - **MethodChannel Senkronizasyonu (`whatsapp_service.dart` & `my_packs_screen.dart`):** Uygulama içinden silinen paketlerin Android yerel ContentProvider depolamasından da eşzamanlı olarak silinmesi için `deleteStickerPack` MethodChannel entegrasyonu tamamlandı.

---

### 2. Hareketli Çıkartmaların WhatsApp'ta Statik Kalması
- **Durum:** ✅ **ÇÖZÜLDÜ & DOĞRULANDI** (Sorun Çözüldü)
- **Test Sonucu:** Android 16 (crDroid 12.13, KernelSU root, Redmi Note 12 Pro 4G) üzerinde 40 çıkartmalı hareketli bir Telegram video çıkartma paketi ("Aziz Kediler") ile canlı olarak test edilmiştir. WhatsApp ekleme sheet'i çıkartmaları `animated_sticker_view` olarak tanımış, WhatsApp'a başarıyla aktarılmış ve WhatsApp'ın dâhili SQLite veritabanında (`third_party_whitelist_packs`) `is_animated_pack = 1` olarak kaydedilip tüm çıkartmaların `ANIM` / `ANMF` animasyon başlıkları ve çoklu benzersiz kareleri doğrulanmıştır.
- **Tespit Edilen Kök Nedenler:**
  1. **ContentProvider Cursor'ında Eksik `is_animated_sticker` Kolonu:** `StickerPackModels.kt` içerisinde çıkartma sorgularında (`STICKER_COLUMNS`) `is_animated_sticker` kolonu yer almıyordu. WhatsApp çıkartma listesini çekerken bu kolonu bulamadığında çıkartmaları statik (0) kabul ediyordu.
  2. **Android `MediaMetadataRetriever` WebM/VP9 Kare Arama Hatası:** Telegram video çıkartmaları tek anahtar kareye (keyframe 0) sahip VP9 WebM formatındadır. Android'in yerel `MediaMetadataRetriever.getScaledFrameAtTime(...)` fonksiyonu zaman damgalı arama (seek) yapamadığı için tüm karelerde video başındaki 0. kareyi dönüyor ve oluşturulan WebP çıkartması tamamen hareketsiz kalıyordu (tüm karelerin MD5 özeti aynıydı).
  3. **Lottie (.tgs) Desteğinin Eksikliği:** Vektörel animasyonlu Lottie çıkartmaları için animasyonlu WebP dönüştürücü motoru bulunmuyordu.
  4. **Bozuk/Eksik Başlıklı WebM Dosyalarında Aktarım Kilitlenmesi:** Kapsayıcı başlık bilgisi eksik olan bazı video dosyalarında çıkartma aktarım süreci çöktüğü için tüm paket iptal oluyordu.
- **Yapılan İyileştirmeler:**
  - **`is_animated_sticker` Kolon Entegrasyonu (`StickerPackModels.kt`):** `STICKER_COLUMNS` dizisine `is_animated_sticker` kolonu eklendi ve `toStickersCursor` metodunda `if (animatedStickerPack) 1 else 0` olarak dinamik şekilde sağlandı.
  - **Sıralı Donanım/Yazılım Kod Çözücü (`MainActivity.kt`):** `MediaMetadataRetriever` yerine `MediaExtractor` + `MediaCodec` (VP9 dekoder) sıralı ayrıştırma motoru geliştirildi. I420/NV12 renk uzayından NV21'e dönüştürülüp `YuvImage` ile tam zaman çizelgesine yayılan benzersiz hareket kareleri çıkarıldı (18 karede 18 benzersiz kare doğrulanmıştır).
  - **Lottie (.tgs) Çıkartma Motoru (`StickerProcessor.dart`):** `processLottieSticker` metodu eklenerek gzip ile sıkıştırılmış Lottie JSON dosyaları `LottieComposition` ve `LottieDrawable` üzerinden 512x512 şeffaf Canvas'a 16 kare olarak çizdirildi ve animasyonlu WebP oluşturuldu.
  - **Akıllı Thumbnail Fallback'i:** Çözümlenemeyen veya bozuk başlıklı video/Lottie çıkartmaları için Telegram önizleme küçük resmi (`fallbackThumbnailBytes`) kullanılarak iki kareli geçerli animasyonlu WebP üretildi; aktarımın çökmesi engellendi.

---

### 3. Çok Parçalı Paketlerde Sonsuz Döngü / Askıda Kalma Sorunu
- **Durum:** ✅ **ÇÖZÜLDÜ & DOĞRULANDI** (Sorun Çözüldü)
- **Test Sonucu:** Android 16 (crDroid 12.13, KernelSU root) fiziksel cihaz üzerinde ADB ile canlı olarak test edilmiş; çok parçalı paketlerin parçalara ayrılması, her bir parçanın WhatsApp'a eklenmesi ve kullanıcı kontrollü bir sonraki parçaya geçiş adımlarının sorunsuz çalıştığı doğrulanmıştır.
- **Tespit Edilen Kök Neden:**
  - `whatsapp_stickers_handler` üçüncü taraf eklentisinin Android tarafındaki `onActivityResult` metodunda başarılı dönüş (`RESULT_OK`) ve kullanıcı iptali (`RESULT_CANCELED`) durumlarında MethodChannel `result.success(...)` metodunun çağrılmadığı, bu nedenle Flutter tarafındaki `await addStickerPack(...)` Future'ının asla tamamlanmadığı ve sonsuza kadar await'te kaldığı tespit edildi.
  - Ayrıca 30'dan fazla çıkartma içeren paketlerde, ilk parça WhatsApp'a gönderildikten sonra WhatsApp'ın Activity lifecycle'ı ile senkronize olmadan arka planda körü körüne döngü çalıştırılması WhatsApp intent çakışmalarına ve arayüz kilitlenmelerine yol açıyordu.
- **Yapılan İyileştirmeler:**
  - **Yerel Kotlin Motoruna Geçiş:** Bozuk ve eski `whatsapp_stickers_handler` paketi projeden tamamen kaldırılarak yerine doğrudan projenin Android altyapısına özel `StickerContentProvider`, `StickerPackStorage` ve `WhatsAppMethodHandler` yerel sınıfları geliştirildi.
  - **Eksiksiz Activity Result Yönetimi:** WhatsApp ekleme intent'inin (`com.whatsapp.intent.action.ENABLE_STICKER_PACK`) sonucu `onActivityResult` üzerinden dinlenerek hem `RESULT_OK` (eklendi), hem `RESULT_CANCELED` (kullanıcı iptal etti), hem de `validation_error` durumları net `WhatsAppExportResult` modeliyle Flutter'a anında ve güvenle aktarıldı.
  - **Kullanıcı Kontrollü Çok Parçalı Aktarım Arayüzü (`_MultiPartExportSheet`):**
    - 30'dan fazla çıkartma seçildiğinde tüm çıkartmalar ve tepsi simgeleri önce yerel olarak işlenir ve güvenle kaydedilir.
    - Kullanıcıya parçaları (Parça 1/X, Parça 2/X...) listeleyen modern, kurumsal bir aktarım modalı sunulur.
    - Kullanıcı WhatsApp'ta her bir parçayı onaylayıp döndüğünde ilgili parça yeşil tik ile işaretlenir ve bir sonraki parça otomatik olarak aktif hale getirilir. Kullanıcı dilediğinde süreci duraklatabilir veya "Daha Sonra Tamamla" seçeneğiyle çıkabilir. Askıda kalma ve kilitlenme sorunu tamamen ortadan kaldırıldı.

---

### 4. Sade & Kurumsal Tasarım (Neon ve Liquid Glass Efektlerinin Kaldırılması)
- **Durum:** ✅ **YAPILDI** (Tamamlandı)
- **Yapılan İyileştirmeler:**
  - `AppTheme`: Neon/aşırı parlak tonlar kaldırılarak göz yormayan dengeli, modern kurumsal renk paletine (Slate 50 - 900, dengeli kurumsal mavi tonları `Color(0xFF2563EB)`) geçildi.
  - `GlassCard`: Arka plan bulanıklığı (BackdropFilter blur), parlak kenarlıklar ve neon gölgeler kaldırıldı. Temiz, düz, yüksek kontrastlı ve kurumsal kart yapısına dönüştürüldü.
  - `GradientButton`: Aşırı neon glow gölgeleri kaldırılarak hafif, kurumsal gölge ve dengeli buton geçişleri uygulandı.
  - Ekranlar (`HomeScreen`, `MainNavigationScreen`, `MyPacksScreen`, `PackPreviewScreen`, `SettingsScreen`, `BotTokenGuideSheet`): Tüm kartlar, butonlar, modallar ve chip'ler kurumsal ve minimalist tasarım standartlarına uyarlandı.

---

### 5. Sürüm Numaralandırma Kuralı (Version Increment)
- **Durum:** ✅ **UYGULANDI**
- **Açıklama:** Yapılan değişiklikler ve giderilen hatalar doğrultusunda `pubspec.yaml` sürümü güncellendi:
  - `1.0.1+2` ➡️ `1.0.2+3` ➡️ `1.0.3+4` ➡️ `1.0.4+5` olarak artırıldı (WhatsApp hareketli çıkartma desteği, VP9 MediaCodec ve ContentProvider güncellemeleri).

---
---

## 🇬🇧 English

### 1. "Sticker Pack File Does Not Exist" Error on Deleting Pack from WhatsApp (TOP PRIORITY)
- **Status:** ✅ **RESOLVED & VERIFIED** (Issue Fixed)
- **Test Results:** Live tested on Android 16 physical device (crDroid 12.13, KernelSU root, Redmi Note 12 Pro 4G) using direct ADB ContentProvider queries (`query`, `read`, `delete`). Verified that existing, orphan, and deleted packs are gracefully queried and removed from WhatsApp without throwing errors.
- **Identified Root Causes:**
  1. **Unhandled IllegalArgumentException in ContentProvider:** When queried for a pack that did not exist in storage, `StickerContentProvider.kt` threw `IllegalArgumentException` instead of returning an empty Cursor. WhatsApp caught this IPC exception and displayed *"Sticker pack file does not exist"*, aborting the removal.
  2. **Metadata Column Names & Missing Field:** Columns were missing WhatsApp's required `sticker_pack_` prefix and the `whatsapp_will_not_cache_stickers` column was omitted entirely.
  3. **Missing `openFile` Implementation:** Only `openAssetFile` was implemented, causing `openFile` calls to throw `FileNotFoundException: No files supported by provider`, while `UNKNOWN_LENGTH` confused decoders.
  4. **Delete Throwing UnsupportedOperationException:** `delete(...)` threw an exception instead of removing the record from `StickerPackStorage`.
  5. **Non-Deterministic Pack Identifiers:** Appending `DateTime.now().millisecondsSinceEpoch` on export created phantom orphan IDs in WhatsApp whenever a pack was re-exported.
- **Implemented Fixes:**
  - `StickerContentProvider.kt`: Returns empty MatrixCursors for missing packs, implements `openFile`, passes exact file lengths in `AssetFileDescriptor`, and safely handles `delete(...)` with content resolver notifications.
  - `StickerPackModels.kt`: Synchronized all 13 metadata columns with the official WhatsApp sticker specification and formatted emoji strings with comma delimiters.
  - `StickerPackStorage.kt`: Added resilient ID normalization and timestamp-stripping fallback for querying and deleting legacy packs.
  - `pack_preview_screen.dart`: Made pack identifiers deterministic (`${packName}_part${idx}`).
  - `whatsapp_service.dart` & `my_packs_screen.dart`: Integrated `deleteStickerPack` MethodChannel to keep storage synchronized when deleting packs in-app.

---

### 2. Animated Stickers Appearing Static in WhatsApp
- **Status:** ✅ **RESOLVED & VERIFIED** (Issue Fixed)
- **Test Results:** Live tested on Android 16 (crDroid 12.13, KernelSU root, Redmi Note 12 Pro 4G) using a 40-sticker animated Telegram video pack ("Aziz Kediler"). WhatsApp native sticker dialog recognized every item via `animated_sticker_view`. The pack was successfully imported into WhatsApp, verified in WhatsApp's internal database (`third_party_whitelist_packs`) with `is_animated_pack = 1`, and stored with valid WebP `ANIM`/`ANMF` chunks and unique frames.
- **Identified Root Causes:**
  1. **Missing `is_animated_sticker` Column in ContentProvider:** In `StickerPackModels.kt`, `STICKER_COLUMNS` omitted `is_animated_sticker`. WhatsApp defaulted each sticker to static (0) when this column was missing.
  2. **Android `MediaMetadataRetriever` Seeking Bug in VP9 WebM:** Telegram animated video stickers are VP9 WebMs with only a single keyframe at timestamp 0. `MediaMetadataRetriever.getScaledFrameAtTime(...)` failed to seek inter-frames and returned the exact same keyframe 0 for every timestamp, resulting in motionless WebPs where all extracted frames were byte-identical.
  3. **Lack of Lottie (.tgs) Animated WebP Pipeline:** Vector Lottie stickers had no dedicated multi-frame renderer for animated WebP export.
  4. **Premature Export Aborts on Malformed Video Headers:** Single video stickers with non-standard container headers caused the entire export process to throw and cancel.
- **Implemented Fixes:**
  - **`is_animated_sticker` Column Added (`StickerPackModels.kt`):** Added `is_animated_sticker` to `STICKER_COLUMNS` and dynamically populated `if (animatedStickerPack) 1 else 0` in `toStickersCursor()`.
  - **Sequential MediaExtractor + MediaCodec Decoder Pipeline (`MainActivity.kt`):** Replaced non-seeking `MediaMetadataRetriever` with sequential `MediaExtractor` and `MediaCodec` (VP9) decoding. Converts raw planar I420/semiplanar NV12 buffers to NV21 and outputs high-quality compressed JPEGs across the timeline (verified 18 distinct frames with unique MD5 hashes).
  - **Lottie (.tgs) Canvas Renderer (`StickerProcessor.dart`):** Implemented `processLottieSticker`, unzipping `.tgs` streams, loading `LottieComposition`, and rendering 16 frames onto a 512x512 transparent canvas to assemble compliant animated WebPs.
  - **Graceful Thumbnail Fallback:** Added `fallbackThumbnailBytes` handling to prevent export failures on malformed video/Lottie stickers by generating valid 2-frame looping animated WebPs from cached thumbnails.

---

### 3. Multi-Part Pack Export Infinite Loop / Freeze
- **Status:** ✅ **RESOLVED & VERIFIED** (Issue Fixed)
- **Test Results:** Live tested on Android 16 physical device (crDroid 12.13, KernelSU root) via ADB; verified that multi-part pack splitting, WhatsApp intent callbacks, and user-guided sequential part importing function flawlessly without freezes.
- **Identified Root Cause:**
  - In the third-party `whatsapp_stickers_handler` plugin, the Android `onActivityResult` method failed to invoke MethodChannel `result.success(...)` upon `RESULT_OK` or `RESULT_CANCELED`. Consequently, the Flutter `await addStickerPack(...)` future never resolved and hung indefinitely.
  - Running an unguided loop for packs split into multiple parts without respecting the Android Activity return lifecycle caused race conditions and UI freezes.
- **Implemented Fixes:**
  - **Native Kotlin Integration:** Completely eliminated the buggy `whatsapp_stickers_handler` package and implemented native `StickerContentProvider`, `StickerPackStorage`, and `WhatsAppMethodHandler` directly within the project.
  - **Deterministic Activity Result Handling:** Properly handles WhatsApp's `AddThirdPartyStickerPackActivity` callbacks, accurately returning `added`, `cancelled`, and `validation_error` statuses back to Dart.
  - **User-Guided Multi-Part Batch Sheet (`_MultiPartExportSheet`):**
    - Large packs (> 30 stickers) are processed and locally stored ahead of time.
    - An interactive corporate modal sheet guides the user through each part (e.g. Part 1/3, Part 2/3), indicating completion with checkmarks and allowing smooth, user-controlled progression with cancel/resume support.

---

### 4. Clean & Corporate UI (Eliminate Neon Colors & Liquid Glass)
- **Status:** ✅ **DONE** (Completed)
- **Completed Improvements:**
  - `AppTheme`: Neon / overly saturated vibrant colors replaced with a balanced, corporate slate palette and professional blues.
  - `GlassCard`: BackdropFilter blurs, glossy glowing borders, and intense neon shadows completely removed. Replaced with clean, crisp, solid corporate cards.
  - `GradientButton`: Neon glow shadows eliminated; simplified to clean, elegant button styling.
  - Screens (`HomeScreen`, `MainNavigationScreen`, `MyPacksScreen`, `PackPreviewScreen`, `SettingsScreen`, `BotTokenGuideSheet`): Updated to maintain consistent, clean, and professional visual hierarchy across both dark and light modes.

---

### 5. Application Versioning Rule
- **Status:** ✅ **APPLIED**
- **Note:** Following the native multi-part WhatsApp export engine upgrade, StickerContentProvider removal fix, and animated sticker pipeline implementation, `pubspec.yaml` was incremented:
  - `1.0.1+2` ➡️ `1.0.2+3` ➡️ `1.0.3+4` ➡️ `1.0.4+5`.
