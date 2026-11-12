# ✅ StickerSwap Uygulama ve İyileştirme TODO Listesi (`todos.md`)

> **Referanslar:** [Savukat.md](Savukat.md) & [FixRoad.md](FixRoad.md)  
> **Başlangıç Durumu:** `v1.0.6+2006` (`main` branch)  
> **Hedef Sürüm:** `v1.0.7+2007` (Production-Ready)

---

## 🌿 Git ve Branch Çalışma Kuralı (Her Görev İçin Zorunlu)

Doğrudan `main` dalına commit atılmaz. Tüm işler aşağıdaki akışla yürütülür:

- [x] **0.1** `main` üzerinden `develop` branch'ini oluştur ve remote'a pushla (`git checkout -b develop && git push -u origin develop`).
- [ ] **0.2** Her faz/görev için `develop` üzerinden ilgili `fix/*`, `feat/*`, `refactor/*`, `docs/*`, `test/*` veya `chore/*` branch'ini aç.
- [ ] **0.3** Commit mesajlarında Conventional Commits formatını kullan: `<type>(<scope>): <subject>` (örn. `fix(security): sandbox StickerContentProvider file access`).
- [ ] **0.4** Her branch'i `develop`'a merge etmeden önce şu kontrolleri geçir:
  - `flutter analyze --fatal-infos` (0 uyarı / 0 hata)
  - `flutter test` (tüm testler yeşil)
- [ ] **0.5** Sürüm etiketlerinde yalnızca küçük `v` ve 3 hane SemVer kullan (`v1.0.7`).

---

## 🔴 Faz 0: Acil Güvenlik, Analiz ve Repo Temizliği (P0 - Blocker)

> **Önerilen Branch:** `fix/p0-security-and-hygiene` (veya her madde için ayrı `fix/*` / `chore/*` branch'i)

### 0.1 Bağımlılık ve Statik Analiz Onarımı
- [x] `pubspec.yaml` `dependencies` altına `characters: ^1.3.0` ekle (`lib/services/whatsapp_service.dart` doğrudan bağımlılığı).
- [x] `flutter pub get` çalıştır.
- [x] `flutter analyze --fatal-infos` komutunun 0 hata / 0 info ile geçtiğini doğrula.
- [x] Örnek commit: `chore(deps): add characters dependency to pubspec.yaml`

### 0.2 `StickerContentProvider` Path Traversal Açığının Kapatılması
- [x] `android/app/src/main/kotlin/com/example/stickerswap/whatsapp/StickerContentProvider.kt` içinde `isPathSandboxed(context, file)` yardımcı metodunu ekle.
- [x] İzin verilen kök dizinleri `context.filesDir`, `context.cacheDir` ve `context.getExternalFilesDir(null)` canonical path'leri ile sınırla.
- [x] `shared_prefs`, `databases` ve `no_backup` dizinlerine erişimi kesin olarak engelle.
- [x] `resolveAssetFile` içindeki tüm dönüş noktalarını `isPathSandboxed` kontrolünden geçir; geçersiz yollarda `null` döndür.
- [x] Örnek commit: `fix(security): enforce canonical path sandboxing in StickerContentProvider`

### 0.3 Bot Token Güvenliği (`flutter_secure_storage` + Migration)
- [x] `pubspec.yaml` içine `flutter_secure_storage: ^9.2.2` ekle ve `flutter pub get` çalıştır.
- [x] `lib/services/storage_service.dart` içinde `FlutterSecureStorage` (Android'de `encryptedSharedPreferences: true`) entegre et.
- [x] Eski `SharedPreferences` içinde düz metin saklanan token varsa okuyup güvenli depoya taşıyan ve eski kaydı silen otomatik migration yaz.
- [x] `getBotToken()` asenkron (`Future<String?>`) olacağı için token okuyan tüm servis/ekran çağrılarını (`telegram_service.dart`, `home_screen.dart`, `settings_screen.dart`, `pack_preview_screen.dart`, testler vb.) güncelle.
- [x] Token temizleme (`clearBotToken`) durumunda hem secure storage hem legacy key'in silindiğini doğrula.
- [x] Örnek commit: `fix(security): encrypt bot token with flutter_secure_storage and migrate legacy prefs`

### 0.4 Ephemeral Derleme Artıklarını Temizleme ve `.gitignore` Sertleştirme
- [x] `macos/Flutter/ephemeral/` ve `linux/flutter/generated_*` dosyalarını Git takibinden çıkar (`git rm -r --cached ...`).
- [x] `.gitignore` dosyasına ephemeral, `GeneratedPluginRegistrant.swift`, `.swiftpm/` ve `pubspec.lock` hariç `*.lock` kurallarını ekle.
- [x] `git status` ile çalışma ağacının ve build sonrası durumun temiz kaldığını doğrula.
- [x] Örnek commit: `chore(git): untrack ephemeral build artifacts and harden gitignore`

### Faz 0 Çıkış Kriteri
- [x] `flutter analyze --fatal-infos` temiz geçti.
- [x] `flutter test` temiz geçti.
- [x] Android debug build alıp cihaz/emülatörde bot token kaydetme, okuma ve WhatsApp'a aktarma akışı doğrulandı. *(Redmi Note 12 Pro 4G / `2209116AG`, Android 16 üzerinde debug `2.0.0+2010` ile `FlutterSharedPreferences.xml` -> `FlutterSecureStorage.xml` migrasyonu, Ayarlar `Test Et & Kaydet`, traversal engeli ve WhatsApp aktarımı doğrulandı.)*
- [x] `fix/p0-security-and-hygiene` -> `develop` merge edildi.

---

## 🟡 Faz 1: Dokümantasyon Şeffaflığı ve Log Hijyeni (P1 - Yüksek)

> **Önerilen Branch'ler:** `docs/readme-and-token-onboarding`, `fix/release-log-hygiene`

### 1.1 `README.md` ve Kullanıcı Bilgilendirmesi
- [x] `README.md` içindeki *"Uygulama hazır olarak gelir"* ifadesini kaldır; Telegram Bot Token'ın neden gerekli olduğunu ve @BotFather ile ~1 dakikada nasıl alınacağını net şekilde açıkla.
- [x] Platform destek tablosunu güncelle (Android: Tam Destek; iOS: Desteklenmiyor / aktif geliştirme planlanmıyor — yalnızca Android odaklı).
- [x] `CuratedPack` UI'da henüz aktif değilse README'deki ifadeyi güncel duruma göre düzelt (veya Faz 3.2 ile birlikte senkronize et).
- [x] İlk açılışta/link aramada token tanımlı değilse kullanıcıya kırmızı hata yerine dostane "İlk Kurulum / Token Ekle" yönlendirmesi (banner/sheet) ekle.
- [x] Örnek commit: `docs(readme): clarify bot token requirement and platform support`

### 1.2 Canlı Kod Log Hijyeni (Debug Guards & ProGuard/R8)
- [x] `MainActivity.kt`, `WhatsAppMethodHandler.kt`, `StickerContentProvider.kt` ve `StickerPackStorage.kt` içindeki `Log.d` / `Log.i` / `Log.v` çağrılarını `BuildConfig.DEBUG` korumasına al (hassas dosya yolu/hash sızıntısını önle).
- [x] Android release yapılandırması (`proguard-rules.pro`) için `android.util.Log` debug/info/verbose stripping kurallarını ekle.
- [x] Dart dosyalarındaki çıplak `print` çağrılarını temizle; yalnızca `kDebugMode` kontrollü `debugPrint` kullan.
- [x] Örnek commit: `fix(logging): guard native and dart debug logs in release builds`

### Faz 1 Çıkış Kriteri
- [x] `flutter analyze --fatal-infos` ve `flutter test` geçti.
- [x] Release modda hassas yol/token/hash loglarının düşmediği doğrulandı (`flutter build apk --release` + `BuildConfig.DEBUG` + ProGuard/R8 kuralları).
- [x] Branch'ler `develop` içine merge edildi.

---

## 🟡 Faz 2: Mimari Refactoring ve Android Native Kararlılık (P1 - Yüksek)

> **Önerilen Branch'ler:** `refactor/pack-preview-screen`, `fix/native-threadpool-and-codec`

### 2.1 `pack_preview_screen.dart` (2257 Satır) Parçalanması & State Management
- [x] İş mantığı, indirme kuyruğu, isolate havuzu ve çok parçalı bölme akışını `lib/services/sticker_export_orchestrator.dart` (`ChangeNotifier` tabanlı) içine taşı.
- [x] Seçili çıkartma canlı oynatıcısını `lib/widgets/live_hero_preview.dart` dosyasına çıkar.
- [x] Izgara görünümü, çoklu seçim ve 1–30 limit/rozet yönetimini `lib/widgets/sticker_selection_grid.dart` dosyasına çıkar.
- [x] İlerleme çubuğu, yüzde ve iptal kontrolünü `lib/widgets/export_progress_sheet.dart` dosyasına çıkar.
- [x] `lib/screens/pack_preview_screen.dart` dosyasını sadece ekran iskeleti ve bileşen orkestrasyonuna indirge.
- [x] Kontrolsüz `setState()` çağrıları yerine `ChangeNotifier` / `ValueNotifier` (veya belirlenecek state management) ile yalnızca ilgili alt widget'ların yeniden çizilmesini sağla.
- [x] Örnek commit: `refactor(preview): split PackPreviewScreen into orchestrator and modular widgets`

### 2.2 Android Native Thread Havuzu (`MainActivity.kt`)
- [x] `android/app/src/main/kotlin/com/example/stickerswap/MainActivity.kt` içindeki kontrolsüz `Thread { }.start()` çağrılarını kaldır.
- [x] Sabit boyutlu `private val mediaExecutor: ExecutorService = Executors.newFixedThreadPool(3)` tanımla.
- [x] `extractFrames` ve `compressStaticWebP` çağrılarını `mediaExecutor.execute { ... }` üzerinden çalıştır, sonuçları `runOnUiThread` ile döndür.
- [x] `onDestroy()` içinde `mediaExecutor.shutdownNow()` çağırarak zombie thread sızıntısını önle.
- [x] Örnek commit: `refactor(android): replace raw Thread spawns with fixed ExecutorService pool`

### 2.3 MediaCodec Kararlılığı (VP9 Timeout & NV21 Stride)
- [x] `MainActivity.kt` içindeki `dequeueOutputBuffer` döngüsüne ~1.5 saniyelik watchdog timeout ekle; kilitlenme durumunda yazılımsal decoder'a (`preferSoftware = true`) düş.
- [x] `imageToNv21` ve `rawYuvToNv21` fonksiyonlarında `rowStride` ve `pixelStride` hizalamalarını gözden geçirip cihaz/yonga seti kaynaklı yeşil çizgi / renk kayması risklerini düzelt.
- [x] Örnek commit: `fix(media): add VP9 decoder watchdog timeout and harden YUV stride handling`

### Faz 2 Çıkış Kriteri
- [x] `flutter analyze --fatal-infos` ve `flutter test` geçti. (Ayrıca `flutter build apk --debug` ve `flutter build apk --release` geçti.)
- [x] Fiziksel Android cihazda animasyonlu (`.tgs` ve `.webm`) + statik paket aktarımı, iptal ve ardışık paket açma/kapama test edildi. *(`2209116AG` Android 16 cihazında statik `Animals`, `.tgs` `HotCherry`, `.webm` `sonerinkarisi_by_fStikBot`, `İşlemi İptal Et` ve ardışık aç-kapa akışları başarıyla doğrulandı.)*
- [x] Branch'ler `develop` içine merge edildi. (`refactor/pack-preview-screen`, `fix/native-threadpool-and-codec`)

---

## 🟢 Faz 3: WhatsApp Güvencesi, Curated Packs ve Yasal Uyum (P2 - Orta)

> **Önerilen Branch'ler:** `feat/preflight-validator`, `feat/curated-packs-ui`, `feat/legal-and-ios-fallback`

### 3.1 WhatsApp Ön Doğrulama Sigortası (`StickerPreFlightValidator`)
- [x] `lib/services/sticker_pre_flight_validator.dart` (veya uygun servis modülü) oluştur: boyut (<= sınır), kare sayısı, animasyon süresi (<= 3000 ms), boyutlandırma (512x512) ve emoji kurallarını aktarım öncesi denetle.
- [x] Sorunlu çıkartma varsa tüm paketin WhatsApp tarafından reddedilmesini beklemeden kullanıcıya seçenek sun (sorunlu çıkartmayı hariç tut / yeniden sıkıştır).
- [x] Örnek commit: `feat(whatsapp): add StickerPreFlightValidator before export intent`

### 3.2 `CuratedPack` Özelliğinin UI'a Bağlanması *(Daha Sonra Kaldırıldı)*
- [x] `lib/models/curated_pack.dart` ve `CuratedPacksCarousel` bileşeni eklendi; ardından ürün kararıyla (yalnızca kullanıcının kendi bağlantısını aktarması amacıyla) ana ekrandan ve kod tabanından tamamen kaldırıldı.
- [x] `README.md` açıklamaları güncel duruma göre güncellendi.

### 3.3 Hukuki Sorumluluk Reddi & iOS Çökme Koruması
- [x] `lib/screens/settings_screen.dart` (ve gerekirse ilk kurulum akışı) içine telif hakları, bağımsız araç sorumluluk reddi (Telegram/WhatsApp ile resmi bağ olmadığı) ve kullanım bilgilendirmesi bölümü ekle.
- [x] `lib/services/whatsapp_service.dart` / UI tarafında iOS platformu algılandığında `MissingPluginException` fırlatmak yerine kullanıcıya *"StickerSwap yalnızca Android için geliştirilmektedir; iOS WhatsApp aktarımı desteklenmemektedir"* bilgilendirme diyaloğu göster.
- [x] Örnek commit: `feat(compliance): add legal disclaimer in settings and safe iOS export fallback`

### Faz 3 Çıkış Kriteri
- [x] `flutter analyze --fatal-infos` ve `flutter test` geçti.
- [x] `CuratedPack` akışı, pre-flight doğrulama senaryoları ve yasal metin UI üzerinde kontrol edildi. *(Widget & birim testleri ile doğrulandı)*
- [x] Branch'ler `develop` içine merge edildi. (`feat/preflight-validator`, `feat/curated-packs-ui`, `feat/legal-and-ios-fallback`)

---

## 🟢 Faz 4: Test Mühendisliği, CI/CD ve `v2.0.0` Yayını (P2 - Orta)

> **Önerilen Branch'ler:** `test/api-and-native-security`, `chore/github-actions-ci`

### 4.1 Mock HTTP ile Telegram API Test Takımı
- [x] `test/telegram_api_mock_test.dart` oluştur (`http/testing.dart` `MockClient` kullanarak).
- [x] Senaryoları test et:
  - `401 Unauthorized` (geçersiz bot token)
  - `429 Too Many Requests` (rate limit yönetimi)
  - Ağ kopması / timeout ve retry-backoff davranışı
  - Geçersiz/boş API yanıtı
- [x] Örnek commit: `test(telegram): add mock HTTP error and rate-limit tests`

### 4.2 Android Native Güvenlik ve Depolama Testleri
- [x] `android/app/src/test/kotlin/com/example/stickerswap/` altında JUnit / Robolectric test altyapısını ekle.
- [x] `StickerContentProviderSecurityTest.kt`: path traversal (`/data/data/.../shared_prefs/...`, `../`) denemelerinin reddedildiğini (`null`) ve geçerli sticker dosyalarının sunulduğunu doğrula.
- [x] `StickerPackStorageTest.kt`: paket kayıt/okuma ve geçersiz veri senaryolarını doğrula.
- [x] `android/gradlew -p android :app:testDebugUnitTest` komutunun temiz geçtiğini doğrula. *(Not: üst düzey `./gradlew test` üçüncü parti `url_launcher_android` eklenti testini Java 17/SDK 36 uyumsuzluğuyla tetiklediği için uygulama testleri `:app:testDebugUnitTest` üzerinden koşturulur.)*
- [x] Örnek commit: `test(android): add unit tests for StickerContentProvider sandboxing and storage`

### 4.3 GitHub Actions CI İş Akışı
- [x] `.github/workflows/verify.yml` dosyasını oluştur (`push` ve `pull_request` tetiklemeli):
  - `flutter pub get`
  - `flutter analyze --fatal-infos`
  - `flutter test`
  - Android `./android/gradlew -p android :app:testDebugUnitTest`
- [x] Örnek commit: `chore(ci): add GitHub Actions verification workflow`

### 4.4 Sürüm Yükseltme ve Yayın (`v2.0.0+2010`)
- [x] `pubspec.yaml` sürümünü `2.0.0+2010` (ve Ayarlar ekranı sürüm bilgisini) olarak güncelle.
- [x] `notes.md` / changelog özetini güncelle.
- [x] `develop` üzerinde tüm testleri ve CI kontrollerini son kez doğrula.
- [x] `develop` -> `main` merge et, `git tag v2.0.0` oluştur ve `main` + tag'i pushla.

---

## 📌 Hızlı İlerleme Özeti
- [x] **Hazırlık:** `develop` branch açıldı
- [x] **Faz 0 (P0):** Güvenlik, analiz ve repo temizliği tamamlandı *(canlı cihaz doğrulaması dahil)*
- [x] **Faz 1 (P1):** README ve log hijyeni tamamlandı *(release logcat dahil doğrulandı)*
- [x] **Faz 2 (P1):** God Screen parçalandı ve native thread/codec sertleştirildi *(fiziksel cihaz testleri dahil doğrulandı)*
- [x] **Faz 3 (P2):** Pre-flight validator, CuratedPack UI, yasal uyarı ve iOS fallback tamamlandı
- [x] **Faz 4 (P2):** Mock API testleri, Android testleri, CI ve `v2.0.0` etiketi tamamlandı

---

## 📱 Canlı Cihaz Test Listesi (Redmi Note 12 Pro 4G — Android 16 / ADB)

- [x] **T1 (Faz 0) Legacy Bot Token Migrasyonu:** `1.0.5+2006` -> `2.0.0+2010` debug güncellemesi sonrasında plain-text `flutter.bot_token` anahtarının `FlutterSharedPreferences.xml`'den silinip `FlutterSecureStorage.xml` (`EncryptedSharedPreferences`) içine taşındığı doğrulandı.
- [x] **T2 (Faz 0) Bot Token Okuma & Kaydetme (`SettingsScreen`):** Ayarlar ekranında kayıtlı token'ın okunduğu ve `Test Et & Kaydet` ile canlı Telegram `getMe` doğrulaması (`✅ Bağlantı başarılı (539 ms)`) sonrası yalnızca `FlutterSecureStorage.xml`'e kaydedildiği doğrulandı.
- [x] **T3 (Faz 0) `StickerContentProvider` Path Traversal Koruması:** `content read` ile `../shared_prefs/FlutterSecureStorage.xml` ve `%2F` traversal denemelerinin engellendiği (gizli veri yerine fallback WebP döndüğü) cihaz üzerinde doğrulandı.
- [x] **T4 (Faz 2) Statik & Çok Parçalı Paket Aktarımı:** `Animals` (`Just zoo it Part 1`, 30 çıkartma, `22–38 KB`) dönüştürülüp WhatsApp `AddThirdPartyStickerPackActivity` onay ekranından başarıyla aktarıldı (`1 / 2 parça eklendi`).
- [x] **T5 (Faz 2) Mid-Export İptal Testi (`İşlemi İptal Et`):** Aktif video/dönüşüm işlemi (`%87`, `7 / 8`) sürerken `İşlemi İptal Et` butonuna basılarak çökme olmadan iptal edildiği (`WhatsApp'a aktarım işlemi iptal edildi.`) doğrulandı.
- [x] **T6 (Faz 2) Animasyonlu `.tgs` (Lottie) WhatsApp Aktarımı:** `HotCherry` (34 `.tgs` çıkartması; `12–22` kare, `1500–3000 ms`, maks `294K`) dönüştürülüp `Hot Cherry Part 1` (30 çıkartma) WhatsApp `AddThirdPartyStickerPackActivity` üzerinden başarıyla eklendi (`1 / 2 parça eklendi`).
- [x] **T7 (Faz 2) Animasyonlu `.webm` (Video / `MediaCodec` VP9) Sıfırdan Dönüşüm & Aktarım:** `sonerinkarisi_by_fStikBot` `_wa_v4.webp` önbellekleri temizlenip `Executors.newFixedThreadPool(3)` (3 paralel thread) + `MediaCodec` + YUV/NV21 akışıyla tüm 8 `.webm` çıkartması sıfırdan üretildi (`54K–209K`) ve WhatsApp'a başarıyla aktarıldı.
- [x] **T8 (Faz 2) Ardışık Paket Açma/Kapama Kararlılığı:** `PepeTheKing`, `Animals`, `sonerinkarisi_by_fStikBot` ve `HotCherry` arka arkaya açılıp kapatıldı; `logcat` üzerinde sıfır çökme/ANR/exception (`NO_CRASHES`) gözlemlendi.
- [x] **T9 (Faz 3) `CuratedPacksCarousel` & `SettingsScreen` UI Kontrolleri:** `Sevimli` / `Memeler` filtre chip'leri, `@PepeTheKing` kartıyla paket önizleme açılışı (`Pepe the King`), yasal uyarı kartı ve `2.0.0+2010` sürüm bilgisi cihaz üzerinde doğrulandı.
- [x] **T10 (Faz 1) Release APK (`v2.0.0+2010`) Log Hijyeni:** `app-release.apk` (non-debuggable) kurulup `.webm` dönüşümü ve traversal isteği çalıştırıldı; `adb logcat` içinde `StickerContentProvider`, `MainActivity`, `WhatsAppMethodHandler`, `StickerPackStorage` veya Dart tarafında hassas yol/token/hash sızıntısı olmadığı (`ZERO_APP_LOGS`) doğrulandı.

