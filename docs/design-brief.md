# Design Brief: Kampus Lost & Found (AWS Serverless)

**Nama / NIM:** Muhammad Izzuddin Prakoso / 24/537712/TK/59618
**Mata kuliah:** Cloud Computing (AWS), Individual Project
**Track:** C, Serverless (API Gateway + Lambda + DynamoDB)

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

## 3. Arsitektur
Alur request:

Client (Postman/curl) -> API Gateway (HTTP API) -> Lambda -> DynamoDB -> response JSON

| Komponen | Peran |
|---|---|
| API Gateway (HTTP API) | Menerima request HTTPS dan meneruskan ke Lambda sesuai route |
| AWS Lambda (Python) | Menjalankan logika CRUD dan validasi input |
| DynamoDB `LostFoundItems` | Menyimpan data laporan (mode on-demand) |
| IAM `LabRole` | Execution role Lambda untuk membaca/menulis DynamoDB dan menulis log |
| CloudWatch Logs | Menyimpan log eksekusi Lambda untuk debugging |

Filter data dilakukan di Lambda setelah `Scan`, sehingga cocok untuk skala kecil (ratusan item).

Diagram: lihat `docs/architecture.png`.

## 4. Data Entity: `Item`

| Atribut | Tipe | Keterangan |
|---|---|---|
| `itemId` | String (partition key) | UUID, dibuat oleh Lambda |
| `title` | String | Nama barang |
| `description` | String | Ciri-ciri barang |
| `type` | String | `lost` atau `found` |
| `location` | String | Lokasi hilang / ditemukan |
| `contact` | String | Kontak pelapor |
| `status` | String | `open` atau `claimed` |
| `createdAt` | String | Timestamp ISO 8601 |

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
  pembuatan role baru. Role ini memberi akses ke DynamoDB dan CloudWatch Logs.
- Akses DynamoDB hanya lewat Lambda, tabel tidak diekspos langsung ke publik.
- Input divalidasi di Lambda (field wajib, nilai `type` dan `status` hanya yang diizinkan).
- Tidak ada credential atau access key di repository; `.gitignore` memblokir file sensitif.
- API Gateway diakses lewat HTTPS.

## 7. Rencana Deployment
1. Buat tabel DynamoDB `LostFoundItems` (partition key `itemId`, on-demand).
2. Buat fungsi Lambda dengan execution role LabRole, lalu upload `lambda/handler.py`.
3. Buat HTTP API di API Gateway, tambahkan route sesuai tabel endpoint, integrasikan ke Lambda.
4. Deploy stage dan catat Invoke URL.
5. Uji dengan curl/Postman dan simpan bukti di `screenshots/`.

## 8. Target Week 12
- Arsitektur dan desain final.
- Tabel DynamoDB, fungsi Lambda starter, dan satu route API Gateway terbukti terhubung.
- Repository dengan README, starter code, dan commit bertahap.
