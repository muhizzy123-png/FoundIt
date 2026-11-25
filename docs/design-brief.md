# Design Brief: Kampus Lost & Found (AWS Serverless)

**Nama / NIM:** Muhammad Izzuddin Prakoso / 24/537712/TK/59618
**Mata kuliah:** Cloud Computing (AWS), Individual Project
**Track:** C, Serverless (API Gateway + Lambda + S3)

## 1. Use Case
Barang yang hilang di lingkungan kampus sering tidak kembali ke pemiliknya karena tidak ada
tempat terpusat untuk melapor atau mencari. Laporan biasanya tersebar di grup chat dan papan
pengumuman, sehingga sulit dicari dan cepat tenggelam.

Kampus Lost & Found menyediakan REST API sederhana agar mahasiswa dapat:
- melaporkan barang yang hilang,
- melaporkan barang yang ditemukan,
- mencari dan melihat daftar laporan,
- menandai barang sebagai sudah diklaim, atau menghapus laporan.

## 2. Track yang Dipilih dan Alasan
**Track C, Serverless.** Alasannya:
- Tidak perlu mengelola server, jadi fokus pada logika dan desain API.
- Biaya mengikuti penggunaan (per request), sehingga hemat kredit Learner Lab.
- Cocok untuk aplikasi CRUD sederhana dengan satu entity.
- Penyimpanan memakai S3 karena DynamoDB tidak tersedia di AWS Learner Lab yang digunakan. Arsitektur tetap serverless.

## 3. Arsitektur
Alur request:

Client (Postman/curl) -> API Gateway (HTTP API) -> Lambda -> S3 -> response JSON

| Komponen | Peran |
|---|---|
| API Gateway (HTTP API) | Menerima request HTTPS dan meneruskan ke Lambda sesuai route |
| AWS Lambda (Python) | Menjalankan logika CRUD dan validasi input |
| Amazon S3 `kampus-lostfound-537712-items` | Menyimpan data laporan, tiap Item sebagai satu objek JSON |
| IAM `LabRole` | Execution role Lambda untuk membaca/menulis S3 dan menulis log |
| CloudWatch Logs | Menyimpan log eksekusi Lambda untuk debugging |

Filter data dilakukan di Lambda, sehingga cocok untuk skala kecil (ratusan item).

Diagram: lihat `docs/architecture.png`.

## 4. Data Entity: `Item`

| Atribut | Tipe | Keterangan |
|---|---|---|
| `itemId` | String | UUID, dibuat oleh Lambda, dipakai sebagai nama objek |
| `title` | String | Nama barang |
| `description` | String | Ciri-ciri barang |
| `type` | String | `lost` atau `found` |
| `location` | String | Lokasi hilang / ditemukan |
| `contact` | String | Kontak pelapor |
| `status` | String | `open` atau `claimed` |
| `createdAt` | String | Timestamp ISO 8601 |

Setiap `Item` disimpan sebagai satu objek JSON di S3 dengan key `items/<itemId>.json`.

## 5. Endpoint CRUD

| Operasi | Method | Path | Deskripsi |
|---|---|---|---|
| Create | POST | `/items` | Buat laporan baru, status awal `open` |
| Read | GET | `/items` | Daftar semua barang, mendukung filter `?status=open` |
| Read | GET | `/items/{id}` | Detail satu barang |
| Update | PUT | `/items/{id}` | Ubah data atau tandai `claimed` |
| Delete | DELETE | `/items/{id}` | Hapus laporan |

Format request/response menggunakan JSON. Kode status: 200 (OK), 201 (dibuat),
400 (input tidak valid), 404 (tidak ditemukan), 500 (error server).

## 6. IAM dan Security
- Lambda menggunakan **LabRole** sebagai execution role, karena Learner Lab tidak mengizinkan
  pembuatan role baru. Role ini memberi akses ke S3 dan CloudWatch Logs.
- Akses S3 hanya lewat Lambda, bucket bersifat private (Block Public Access aktif).
- Input divalidasi di Lambda (field wajib, nilai `type` dan `status` hanya yang diizinkan).
- Tidak ada credential atau access key di repository; `.gitignore` memblokir file sensitif.
- API Gateway diakses lewat HTTPS.

## 7. Rencana Deployment
1. Buat bucket S3 `kampus-lostfound-<nim>-items` (us-east-1, Block Public Access aktif).
2. Buat fungsi Lambda dengan execution role LabRole, lalu upload `lambda/handler.py`.
3. Buat HTTP API di API Gateway, tambahkan route sesuai tabel endpoint, integrasikan ke Lambda.
4. Deploy stage dan catat Invoke URL.
5. Uji dengan curl/Postman dan simpan bukti di `screenshots/`.

## 8. Target Week 12
- Arsitektur dan desain final.
- Bucket S3, fungsi Lambda starter, dan satu route API Gateway terbukti terhubung.
- Repository dengan README, starter code, dan commit bertahap.
