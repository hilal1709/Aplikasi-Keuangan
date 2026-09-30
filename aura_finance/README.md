# Aura — pencatat keuangan pribadi & keluarga

Aplikasi Android (Flutter) untuk mencatat keuangan secara manual — tanpa sambungan ke bank.
Offline-first (SQLite lokal via Drift) dan tersinkron ke **Neon** (Postgres serverless) agar bisa dipakai bersama pasangan/keluarga.

## Fitur

- **Catat cepat**: pengeluaran, pemasukan, transfer antar dompet — keypad neumorph, kategori, catatan, tanggal.
- **Dompet**: tunai / rekening / e-wallet, saldo awal, dompet bersama atau pribadi.
- **Riwayat**: per hari, cari catatan, filter jenis / dompet / anggota, geser untuk hapus (bisa diurungkan).
- **Budget** per kategori per bulan + notifikasi saat 80% dan 100%, salin dari bulan lalu.
- **Target tabungan** dengan ilustrasi, setor/tarik, perkiraan tanggal tercapai, perayaan saat 100%.
- **Insight**: skor kesehatan finansial, donut kategori, tren 6 bulan, ekspor CSV & laporan PDF.
- **Berulang** (gaji, langganan) tercatat otomatis — juga di latar belakang (WorkManager).
- **Tagihan** dengan pengingat H-1/H-3/H-7; tandai lunas otomatis mencatat pengeluaran & membuat tagihan bulan depan.
- **Rumah tangga**: undang pasangan dengan kode 6 karakter, sinkron realtime lewat Pusher Channels.
- **Push notification** (Pusher Beams) saat pasangan mencatat transaksi, budget 80%/100%, target tercapai, tagihan lunas.
- **Avatar ilustrasi** kartun untuk profil (12 pilihan, termasuk berhijab).
- **Widget layar utama**, kunci sidik jari, mode gelap, sembunyikan saldo.

## Struktur

```
lib/
  core/        tema (token warna dari desain), widget neumorph, ilustrasi clay, util rupiah/tanggal
  data/        Drift (lokal), provider Riverpod, Neon Auth + Data API, sinkronisasi
  domain/      logika murni (skor kesehatan, pengelompokan grafik, tanggal berulang)
  features/    halaman per fitur
  services/    notifikasi, tugas latar, widget, kunci aplikasi
db/migrations/         skema SQL + RLS untuk Neon
server/                Cloudflare Worker (secret Pusher: auth channel, token Beams, kirim notifikasi)
.github/workflows/     build APK
```

## Menjalankan (mode lokal, tanpa akun)

```bash
flutter pub get
dart run build_runner build
flutter run
```

Tanpa alamat Neon, aplikasi tetap berfungsi penuh — data hanya tersimpan di HP.

## Neon (untuk sinkron & berbagi dengan pasangan) — gratis

Aplikasi HP tidak bisa membuka koneksi Postgres langsung, jadi Aura memakai dua layanan bawaan Neon:
**Neon Auth** (login email + kata sandi, menerbitkan JWT) dan **Data API** (REST kompatibel PostgREST yang
memeriksa JWT dan menegakkan Row Level Security).

1. Buat proyek di [neon.com](https://neon.com) (free plan).
2. **Auth** → aktifkan *Neon Auth* (Managed Better Auth), metode *Email & password*.
   Untuk pemakaian keluarga, matikan verifikasi email agar daftar langsung bisa masuk.
3. **Data API** → *Enable*, pilih Neon Auth sebagai penyedia auth, centang *Grant public schema access*.
4. **SQL Editor** → tempel isi `db/migrations/20260930000000_init.sql` → **Run**.
   Setelah itu klik **Refresh schema cache** di halaman Data API.
5. Salin dua alamat: *Data API URL* (`https://ep-…apirest….neon.tech/neondb/rest/v1`)
   dan *Auth URL* (`https://ep-…neonauth….neon.tech/neondb/auth`).
6. Isi alamat tadi di `config/app.json`, lalu jalankan:

```bash
flutter run --dart-define-from-file=config/app.json
```

Kedua alamat ini bukan rahasia; tanpa login yang valid tidak ada data yang bisa dibaca.
RLS memastikan setiap baris hanya terlihat oleh anggota rumah tangga yang sama, dan dompet pribadi hanya oleh pembuatnya.

Di aplikasi: **Profil → Rumah tangga → Daftar/Masuk → Buat rumah tangga**, lalu bagikan kode undangan ke pasangan.
Pasangan memasang APK yang sama, daftar, lalu pilih **Gabung dengan kode**.

> Neon free plan tidak di-pause seperti Supabase: komputasi otomatis tidur saat tidak dipakai dan bangun
> sendiri pada permintaan berikutnya (sinkron pertama setelah lama diam bisa lebih lambat ±1 detik).

## Realtime & push notification (Pusher) — gratis

Mengirim event Pusher butuh *secret key* yang tidak boleh ada di dalam APK, jadi ada satu fungsi kecil
di Cloudflare Workers (`server/`). Worker memverifikasi login Neon (JWKS), mengecek keanggotaan rumah tangga
lewat Data API (RLS tetap berlaku), lalu menandatangani channel privat, menerbitkan token Beams, dan mengirim notifikasi.

1. **Pusher Channels** — [dashboard.pusher.com](https://dashboard.pusher.com) → buat app (cluster `ap1` / Singapore).
   Catat `app_id`, `key`, dan `secret` dari tab *App Keys*.
2. **Firebase** (dipakai Beams untuk Android) — [console.firebase.google.com](https://console.firebase.google.com) → buat proyek →
   tambah aplikasi Android dengan package `com.aurafinance.aura_finance` → unduh `google-services.json`
   ke `android/app/`. Di *Project settings → Cloud Messaging*, buat **service account key** (JSON).
3. **Pusher Beams** — dashboard Pusher → Beams → buat instance → *Android* → unggah service account key Firebase tadi.
   Catat `instance_id` dan `primary key` (secret).
4. **Worker** — isi `PUSHER_APP_ID`, `PUSHER_KEY`, `PUSHER_CLUSTER`, `BEAMS_INSTANCE_ID` di `server/wrangler.toml`, lalu:

```bash
cd server
npm install
npx wrangler login
npx wrangler secret put PUSHER_SECRET
npx wrangler secret put BEAMS_SECRET_KEY
npx wrangler deploy
```

5. Isi `AURA_API_URL` (URL worker) dan `BEAMS_INSTANCE_ID` di `config/app.json`, lalu:

```bash
flutter run --dart-define-from-file=config/app.json
```

Tanpa `google-services.json`, aplikasi tetap dibangun; push dimatikan tetapi realtime (Channels) tetap jalan.

## Distribusi gratis (tanpa Play Store)

APK dibangun otomatis oleh GitHub Actions dan diunggah ke **GitHub Releases**.

1. Buat kunci penandatangan (sekali saja, simpan baik-baik — dibutuhkan untuk setiap update):

   ```bash
   keytool -genkey -v -keystore aura-release.jks -keyalg RSA -keysize 2048 -validity 10000 -alias aura
   ```

2. Di repo GitHub → **Settings → Secrets and variables → Actions**, tambahkan:
   `NEON_DATA_API_URL`, `NEON_AUTH_URL`, `AURA_API_URL`, `PUSHER_KEY`, `PUSHER_CLUSTER`, `BEAMS_INSTANCE_ID`,
   `GOOGLE_SERVICES_JSON_BASE64`, `KEYSTORE_BASE64` (isi file .jks di-base64), `KEYSTORE_PASSWORD`, `KEY_ALIAS`, `KEY_PASSWORD`.
3. Rilis:

   ```bash
   git tag v0.1.0
   git push origin v0.1.0
   ```

4. Buka halaman Releases di HP, unduh `app-arm64-v8a-release.apk`, lalu pasang
   (izinkan "Instal aplikasi tidak dikenal" untuk browser). Update berikutnya cukup pasang APK versi baru.

Build lokal: `flutter build apk --release --split-per-abi --dart-define=...` → `build/app/outputs/flutter-apk/`.

## Sinkronisasi — cara kerja

- Setiap perubahan ditulis ke SQLite dengan tanda `dirty` (outbox).
- Saat online: baris `dirty` di-upsert lewat Data API, lalu baris yang `server_updated_at`-nya lebih baru ditarik.
- Konflik: *last-write-wins* per baris berdasarkan `updated_at`.
- Hapus = *soft delete* (`deleted_at`) supaya penghapusan ikut tersinkron.
- Setelah perubahan terkirim, HP ini memanggil Worker `/notify`; Worker memicu event Pusher Channels ke HP lain
  (yang langsung menarik data) dan push Pusher Beams untuk transaksi/budget/target/tagihan.
- Cadangan tanpa Pusher: polling tiap 30 detik saat aplikasi di layar dan saat dibuka kembali.

## Tes

```bash
flutter analyze
flutter test
```
