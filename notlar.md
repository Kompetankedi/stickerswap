# StickerSwap - Geliştirici Notları & Yol Haritası (Developer Notes & Roadmap)

---

## 🇹🇷 Türkçe (Turkish)

### 1. Çıkartmalar İlk Kez İndirilip Hazırlanırken Uygulamanın Donması / Yanıt Vermemesi (Optimizasyon İhtiyacı)
- **Öncelik:** 🔴 **YÜKSEK (1. Öncelik)**
- **Durum:** ✅ **TAMAMLANDI & TEST EDİLDİ**
- **Sorun Tanımı:**
  - Donma ve kilitlenme sorunu WhatsApp ekranı açıldığında değil; **kullanıcı paket linkini verip çıkartmaları seçtikten sonra *"WhatsApp'a Aktar"* işlemini ilk başlattığı anda** gerçekleşmektedir.
  - Uygulama bu aşamada çok parçalı veya tekil tüm çıkartmaları (özellikle 30, 50, 120 adet veya hareketli/video WebM) Telegram sunucularından **tek tek çekmeye, karelerini ayrıştırmaya ve dönüştürmeye başladığında** arayüz tamamen donmakta, dokunmatik yanıtsız kalmakta, ilerleme göstergesi takılmakta ve cihazda "Uygulama Yanıt Vermiyor" (ANR) uyarısı oluşma riski doğmaktadır.
- **Tespit Edilen Kök Nedenler:**
  1. **Ana UI Isolate Üzerinde Yoğun CPU Tüketimi (Main Thread Blocking):**
     - Çıkartmaların indirilip yerel olarak hazırlandığı bu ön hazırlık evresinde `StickerProcessor` sınıfındaki görsel işleme operasyonları (`img.decodeImage`, `_fitImage`, `img.compositeImage`, `img.encodeWebP`) Flutter'ın ana UI iş parçacığında (main isolate) senkron çalıştırılmaktadır.
     - Her video çıkartma için Android `MediaCodec` motorundan 18 ham kare çekilmekte; bu 18 karenin her biri ana isolate'te tek tek decode edilip 512x512 canvas'a çizilmekte ve `package:image` saf Dart motoruyla çok katmanlı döngüde (kalite %75, %60, %45, %30) tekrar tekrar WebP olarak sıkıştırılmaktadır.
     - Tek bir video çıkartmanın kodlanması CPU'da 1-3 saniye sürdüğünden, 30 ila 120 çıkartmanın tek tek çekilip işlenmesi ana iş parçacığını dakikalarca kilitli tutmaktadır.
  2. **Seri İndirme ve İşleme Sıralaması (Sequential Pipeline Bottleneck):**
     - Telegram'dan ağ üzerinden tek tek indirme (`downloadSticker`) ile CPU tabanlı görüntü kodlama adımları art arda (sequential) tek bir döngüde çalıştırılmaktadır. Ağ beklemesi ile CPU iş yükünün birbirini bloklaması arayüzün askıda kalma süresini aşırı uzatmaktadır.
  3. **Bellek Şişmesi ve Çöp Toplayıcı (GC) Baskısı:**
     - Onlarca çıkartma işlenirken açılan büyük çözünürlüklü `Image` nesneleri ve ham bayt dizileri RAM'de birikmekte, sistem sık sık Garbage Collection (GC) tetikleyerek arayüzün tamamen duraksamasına yol açmaktadır.

- **Tamamlanan Optimizasyonlar & Eylem Planı:**
  - [x] **Arka Plan Isolate (Worker Threads) Entegrasyonu:** Ağır görsel çözme, boyutlandırma ve WebP kodlama adımları `Isolate.run` ile arka plan worker iş parçacıklarına taşındı. Ana UI iş parçacığı serbest bırakılarak 60/120 FPS akıcılık korundu; isolate işi bitince RAM çöp toplayıcı yükü olmadan otomatik temizlendi.
  - [x] **Boru Hattı (Pipelined Concurrent Processing):** İndirme (I/O bound) işlemi ile görüntü işleme (CPU bound) eşzamanlı çalışacak şekilde kuyruk yapısına (3 eşzamanlı worker) alındı. Çıkartmalar paralel olarak indirilip işlenmekte, sıraları bozulmadan WhatsApp paketlerine aktarılmaktadır.
  - [x] **WebP Kodlama Performansının İyileştirilmesi:** Android tarafında donanım hızlandırmalı yerel WebP sıkıştırma API'si (`compressStaticWebP`) entegre edildi. Dart tarafında ise kare sayısı ve ilk geçiş kalite oranı (q:70) optimize edilerek gereksiz tekrarlı kodlama döngüleri engellendi.
  - [x] **Kullanıcı Geri Bildirimi ve Akıcı İlerleme Görselleştirmesi:** Çıkartmalar hazırlanırken gerçek zamanlı yüzde (`%XX`), mevcut durum (`Hazırlanıyor: X / Y çıkartma`) `TweenAnimationBuilder` ile akıcı animasyonla gösterilmekte; kullanıcıya anında güvenli "İşlemi İptal Et" seçeneği ve sayfa çıkışında `PopScope` koruması sunuldu.

---

### 2. Bazı Çıkartmaların WhatsApp'a Eklenememesi & Hata Vermesi (`handleStickerPackPreviewResult`)
- **Öncelik:** 🔴 **YÜKSEK (2. Öncelik)**
- **Durum:** 🟡 **DÜZELTMELER UYGULANDI (Test Sırasında 3. Madde Ağ Hatasına Takıldı - Beklemede)**
- **Sorun Tanımı:**
  - Çok parçalı veya tekil çıkartma paketleri WhatsApp'a eklenirken bazı parçalar sorunsuz eklenirken (örn. `@kynik` paketinin Parça 2, 3 ve 4'ü başarıyla eklendi), bazı parçalarda (örn. `@kynik Part 1` ve `bruuh Part 1, Part 2`) ekleme işlemi başarısiz olmaktadır.
  - WhatsApp tarafında *"There's a problem with the sticker pack. Unable to add to WhatsApp"* sistem uyarısı çıkmakta ve `AddThirdPartyStickerPackActivity` sonucunda `validation_error = handleStickerPackPreviewResult` dönmektedir.

- **Örnek Hata Ekran Görüntüleri:**
  | `bruuh` Paketi: Parça 1 ve 2 Hata Aldı | `@kynik` Paketi: Parça 1 Hata Aldı, Parça 2-4 Eklendi |
  | :---: | :---: |
  | ![bruuh Hata Ekranı](assets/screenshots/error_bruuh_preview_result.jpg) | ![kynik WhatsApp Doğrulama Hatası](assets/screenshots/error_kynik_whatsapp_validation.jpg) |
  | *Görsel 1: `bruuh` video paketinde her iki parça da `handleStickerPackPreviewResult` hatasıyla başarısız oldu.* | *Görsel 2: `kynik` paketinde 2, 3 ve 4. parçalar onaylanırken 1. parçada WhatsApp "There's a problem with the sticker pack" uyarısıyla reddetti.* |

- **Tespit Edilen Kritik Kök Nedenler (WhatsApp Dahili Doğrulayıcı Analizi):**
  WhatsApp'ın yerel `AddThirdPartyStickerPackActivity` ve `StickerPackValidator` modülleri çıkartma paketlerini içeri alırken çok katı kurallarla doğrular. Parça içindeki tek bir çıkartmanın veya ContentProvider şemasının kural dışı olması tüm parçanın reddedilmesine yol açar:
  1. **ContentProvider Sütun Şeması Uyuşmazlığı (`STICKER_COLUMNS` & `METADATA_COLUMNS`):**
     - WhatsApp resmi Android sözleşmesine göre `stickers/<pack_id>` sorgusunda MatrixCursor **sadece 2 sütun** (`sticker_file_name`, `sticker_emoji`) bekler. Kodda ise 4 sütun (`sticker_accessibility_text` ve `is_animated_sticker`) döndürülüyordu.
     - `metadata/<pack_id>` sorgusunda 11. sütun resmi spesifikasyonda `avoid_cache` iken eski kodda `whatsapp_will_not_cache_stickers` olarak tanımlıydı. WhatsApp `cursor.getColumnIndexOrThrow("avoid_cache")` çağrısı yaptığında `IllegalArgumentException` fırlatıyor ve doğrudan `handleStickerPackPreviewResult` ile işlemi iptal ediyordu.
  2. **Android İzin ve Doğrudan Paket Hedefleme (`grantUriPermissions` & `createChooser`):**
     - `AndroidManifest.xml` içerisindeki `<provider>` etiketinde `android:grantUriPermissions="true"` eksikti ve Intent'e `FLAG_GRANT_READ_URI_PERMISSION` eklenmiyordu.
     - Intent `Intent.createChooser` ile sarılarak başlatılıyordu; bu durum modern Android sürümlerinde Intent paket hedeflemesini (`setPackage`) sıfırlamakta ve `onActivityResult` geri bildiriminin kaybolmasına veya doğrulayıcı erişim engeline yol açmaktaydı.
  3. **Cihazda Kalan Eski / Hatalı Önbellek Dosyaları (Stale Cache Bypass):**
     - Önceki denemelerde üretilen ve WhatsApp kurallarına uymayan eski WebP/tray dosyaları cihaz hafızasında kalmıştı. `outputFile.exists()` kontrolü dosya boyutu sınırda olduğu için eski dosyaları doğrudan geri döndürüyor ve yeni kodlayıcı mantığının çalışmasını engelliyordu.
  4. **Video Çıkartma Küçük Resim Çökmesi (Thumbnail Fallback):**
     - `thumbFileId` boş olduğunda video sticker'ın kendi `.webm` `fileId`si küçük resim olarak indirilmeye çalışılıyor ve Dart görsel çözücüsü `.webm` dosyasını çözemeyip hata alıyordu.
  5. **Animasyon Süresi ve Kare Kuralları (Total Duration <= 3000 ms, Frames >= 2):**
     - WhatsApp hareketli çıkartmalarda toplam sürenin en fazla 3000 ms (3 saniye), her kare süresinin en az 8 ms ve en az 2 kare olmasını katı bir şekilde kontrol eder.

- **Tamamlanan İyileştirmeler & Eylem Planı (v2):**
  - [x] **ContentProvider Şeması Standartlaştırıldı:** `STICKER_COLUMNS` kesin olarak 2 sütuna (`sticker_file_name`, `sticker_emoji`) indirgendi. `METADATA_COLUMNS` 11. sütun resmi `avoid_cache` olarak güncellendi.
  - [x] **Manifest ve Intent Yetkilendirmesi:** `<provider>` etiketine `android:grantUriPermissions="true"` eklendi. Intent'e `FLAG_GRANT_READ_URI_PERMISSION` ve doğrudan `com.whatsapp` / `com.whatsapp.w4b` paket hedeflemesi verilerek `createChooser` kaldırıldı.
  - [x] **Aktarımda Zorunlu Yeniden Üretim (`forceRefresh: true`):** WhatsApp'a aktarım başlatıldığında veya tekrar denendiğinde cihazdaki eski/hatalı önbellek dosyaları baypas edilerek her çıkartma taze olarak yeniden kodlanır.
  - [x] **Kare ve Süre Garantisi (<= 3000 ms, >= 2 Kare):** `totalDuration <= 3000 ms` ve `frameDelay >= 8 ms` garantisi eklendi. 4. aşama (Strategy 4) 2 karelik minimal sıkıştırma basamağı eklendi.
  - [x] **Parça Başına Animasyon Belirleme:** `isAnimatedPack` kontrolü `selected.any` yerine ilgili parçaya (`chunk.any`) bağlandı; statik parçaların hareketli olarak işaretlenmesi engellendi.
  - [x] **Video Önizleme Güvencesi:** Video çıkartmalar için küçük resim bulunamadığında `.webm` dosyasının küçük resim sanılarak indirilmesi engellendi; yerel `extractFrames` YUV/NV21 çözümü güçlendirildi.
  - [x] **Sıkı Dosya Boyutu Koruması (Strict 480 KB Ceiling):** Kodlanan her WebP'nin boyutu 480 KB (500 KB WhatsApp sınırı altında) tavan sınırına bağlandı. Çok aşamalı kalite düşürme (q:70 -> 55 -> 40 -> 25 -> 15) yetersiz kalırsa kare sayısı dinamik olarak seyreltilerek (downsampling: 15 -> 8 -> 4 kare) 500 KB sınırının aşılması imkânsız kılındı. Tek kareli hareketli çıkartmalar için 2 kare çoğaltma güvencesi (`numFrames >= 2`) ve statik çıkartmalar için <= 96 KB tavanı uygulandı.
  - [x] **Emoji Filtreleme & Standartlaştırma (1-3 Emoji Sanitization):** `WhatsAppService.sanitizeEmojis` metodu eklendi; Telegram'dan gelen kontrolsüz emojiler, ZWJ/cilt tonu birleşik karakterleri, boşluklar ve metinler taranarak 1 ila 3 geçerli Unicode emojisine sınırlandı. Boş/geçersiz olanlar için varsayılan güvenli "⭐" emojisi atandı.
  - [x] **Parça Başına Benzersiz Tepsi Simgesi (Unique Tray Icon per Part):** Her parça için bağımsız `tray_${packId}.png` dosyası oluşturuldu. Sadece ilk karenin kullanılması, tam 96x96 piksel transparent canvas'a çizilmesi ve level 9 / renk kuantizasyonu ile <= 48 KB PNG olması garantiye alındı.

---

### 3. Telegram'dan Çıkartmalar İndirilirken Ağ / Soket Kesintisi (`ClientRead failed`)
- **Öncelik:** 🟡 **ORTA / YÜKSEK (3. Madde)**
- **Durum:** ⏳ **BEKLEMEDE (Kullanıcı İsteğiyle İlerleyen Zamanda Bakılacak)**
- **Sorun Tanımı:**
  - 120 çıkartmalık büyük video paketleri (`@kynik` gibi) `forceRefresh: true` ile sıfırdan indirilip hazırlanırken, Telegram sunucularından `.webm` dosyaları çekilirken geçici ağ/soket kesintisi oluşmakta ve hazırlık ekranında şu hata belirmektedir:
    `Hata: ClientRead failed, uri=https://api.telegram.org/file/bot.../stickers/file_1616.webm`
  - Ekran görüntüsü: [`assets/Bug.png`](file:///Users/kompetankedi/Documents/GitHub/stickerswap/assets/Bug.png)
- **Tespit Edilen Kök Neden:**
  - `telegram_service.dart` içerisindeki `downloadSticker` metodunda tekil `http.get` çağrısı yapılmakta; Telegram API veya mobil/Wi-Fi ağında soket anlık koptuğunda (`ClientException: ClientRead failed`) herhangi bir yeniden deneme (retry) mekanizması olmadığı için tüm işlem tek bir hatada abort edilmektedir.
- **İleride Yapılacak Çözüm Planı:**
  - `downloadSticker` çağrısına en az 3 defa otomatik yeniden deneme (exponential backoff: 1s, 2s, 4s) eklenmesi.
  - Zaten tam indirilmiş geçerli dosyaların ağ hatasında silinmeden korunması ve sadece başarısız olan dosyanın tekrar talep edilmesi.

---
---

## 🇬🇧 English (Developer Summary)

### 1. App Freezing & Unresponsiveness During Initial Bulk Sticker Download & Preparation (Optimization Needed)
- **Priority:** 🔴 **HIGH (Item 1)**
- **Status:** ✅ **COMPLETED & TESTED**
- **Issue:** The freeze does *not* occur when WhatsApp itself opens; rather, it happens **immediately when the user provides the pack link, selects stickers, and first taps *"Export to WhatsApp"***. At this stage, the app fetches each sticker from Telegram servers one by one, extracts video frames, and converts them to Animated WebP locally. During this sequential bulk preparation process, the main UI thread completely freezes, touch becomes unresponsive, progress freezes, and there is a high risk of an ANR (Application Not Responding) dialog.
- **Root Causes:**
  1. **Main UI Isolate Blocking:** CPU-heavy decoding, canvas composition, and WebP encoding in `StickerProcessor` run synchronously on Flutter's main thread during this preparation loop.
  2. **Sequential Pipeline Bottleneck:** Downloading stickers from Telegram one by one and sequentially processing each one locks the UI for minutes (especially on 30-120 sticker packs).
  3. **High Memory & GC Pressure:** Heavy frame allocation and decoding creates frequent garbage collection pauses and interface lockups.
- **Action Items Completed:**
  - [x] Offloaded heavy image operations to background Dart Isolates (`Isolate.run`) so the UI remains fluid at 60/120 FPS during preparation, with intermediate buffers cleanly freed upon worker completion.
  - [x] Implemented concurrent downloading and processing pipelines (bounded concurrency pool of 3 workers), overlapping I/O and CPU workloads without changing sticker order.
  - [x] Implemented hardware-accelerated native Android WebP compression (`compressStaticWebP`), and optimized Animated WebP encoding passes and frame counts.
  - [x] Implemented smooth real-time progress visualization with `TweenAnimationBuilder`, an immediate "İşlemi İptal Et" cancellation action, and `PopScope` exit protection.

---

### 2. Sticker Pack Import Failures in WhatsApp (`handleStickerPackPreviewResult`)
- **Priority:** 🔴 **HIGH (Item 2)**
- **Status:** 🟡 **FIXES APPLIED (On Hold: Test Blocked by Item 3 Network Issue)**
- **Issue:** Certain pack parts fail to import into WhatsApp with the error `handleStickerPackPreviewResult...` and a native toast saying *"There's a problem with the sticker pack. Unable to add to WhatsApp"*, while other parts in the same pack succeed (e.g. `@kynik Part 1` failed, but Parts 2, 3, and 4 succeeded).
- **Screenshots:**
  - `assets/screenshots/error_bruuh_preview_result.jpg` (`bruuh` Parts 1 & 2 failed)
  - `assets/screenshots/error_kynik_whatsapp_validation.jpg` (`kynik` Part 1 rejected by WhatsApp validator)
- **Suspected Causes & Implemented Root Cause Fixes:**
  1. **ContentProvider Cursor Schema:** `STICKER_COLUMNS` reduced to exact 2-column contract (`sticker_file_name`, `sticker_emoji`), and metadata column 11 renamed to `avoid_cache` from `whatsapp_will_not_cache_stickers`.
  2. **Grant URI Permissions:** Added `android:grantUriPermissions="true"` in AndroidManifest and `FLAG_GRANT_READ_URI_PERMISSION` on the intent, removing `createChooser` to target WhatsApp directly.
  3. **Stale Cache Bypass:** Added `forceRefresh: true` on export to prevent re-using corrupt or non-compliant cached WebPs.
  4. **Animated Duration and Size:** Strictly bounded to $\le 3000\text{ ms}$ total duration and $\le 480\text{ KB}$ file size with $\ge 2$ frames.
- **Action Items Completed:**
  - [x] **Enforce strict size guards ($\le 480\text{ KB}$):** Implemented multi-tier quality fallback (70->55->40->25->15) and dynamic frame downsampling (15->8->4 frames) to make exceeding the 500 KB ceiling impossible. Enforced 2-frame duplication for single-frame animations and $\le 96\text{ KB}$ for static stickers.
  - [x] **Sanitize sticker emojis (1 to 3 valid Unicode emojis):** Added `WhatsAppService.sanitizeEmojis` to parse grapheme clusters, trim to max 3, discard text/garbage, and safely fallback to "⭐".
  - [x] **Unique tray icon per part:** Generated `tray_${packId}.png` uniquely sized at 96x96 pixels PNG ($\le 48\text{ KB}$) using level 9 compression and palette quantization.
  - [x] **Pre-validation & Contextual error parsing:** Added in-app pre-validation in Dart before dispatching to WhatsApp, enhanced native Android diagnostics logging, and mapped `handleStickerPackPreviewResult` into actionable user-facing error messages.

---

### 3. Network / Socket Interruption During Bulk Sticker Download (`ClientRead failed`)
- **Priority:** 🟡 **MEDIUM / HIGH (Item 3)**
- **Status:** ⏳ **ON HOLD (Will address later as requested)**
- **Issue:** When preparing large 120-sticker video packs (such as `@kynik`) with fresh downloads, bulk concurrent HTTP fetching from Telegram triggers a socket/network read error:
  `Hata: ClientRead failed, uri=https://api.telegram.org/file/bot.../stickers/file_1616.webm`
- **Screenshot:** `assets/Bug.png`
- **Root Cause:**
  - Single `http.get` in `downloadSticker` lacking automated retries or exponential backoff on abrupt socket closures (`ClientException: ClientRead failed`).
- **Future Action Plan:**
  - Implement 3-pass retry with exponential backoff (1s, 2s, 4s) in `telegram_service.dart`.
  - Preserve valid downloaded files across socket interruptions to avoid re-downloading existing stickers.
