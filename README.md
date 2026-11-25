# Lost & Found Kampus

Aplikasi serverless di AWS untuk melaporkan dan mencari barang hilang atau ditemukan di lingkungan kampus.

- **Mata kuliah:** Cloud Computing (AWS), Individual Project
- **Nama / NIM:** <nama> / <nim>
- **Track:** C, Serverless (API Gateway + Lambda + DynamoDB)

## 1. Latar Belakang & Use Case
Barang yang hilang di kampus sering tidak kembali karena tidak ada tempat terpusat untuk melapor.
Aplikasi ini menyediakan REST API sederhana agar mahasiswa bisa melaporkan barang hilang,
melaporkan barang yang ditemukan, dan menandai barang yang sudah diklaim.

## 2. Arsitektur

![Architecture](docs/architecture.png)

Alur request:
Client -> API Gateway -> Lambda (LabRole) -> DynamoDB -> response JSON

| Komponen | Fungsi |
|---|---|
| API Gateway (HTTP API) | Pintu masuk HTTPS, routing ke Lambda |
| AWS Lambda (Python 3.x) | Logika CRUD dan validasi input |
| DynamoDB (`LostFoundItems`) | Penyimpanan data, on-demand |
| IAM (`LabRole`) | Execution role Lambda untuk akses DynamoDB |
| CloudWatch Logs | Log dan debugging |

## 3. Data Entity: `Item`

| Atribut | Tipe | Keterangan |
|---|---|---|
| `itemId` | String (PK) | UUID |
| `title` | String | Nama barang |
| `description` | String | Ciri-ciri barang |
| `type` | String | `lost` atau `found` |
| `location` | String | Lokasi hilang / ditemukan |
| `contact` | String | Kontak pelapor |
| `status` | String | `open` atau `claimed` |
| `createdAt` | String | Timestamp ISO 8601 |

## 4. API Endpoints

| Method | Path | Deskripsi |
|---|---|---|
| POST | `/items` | Buat laporan baru |
| GET | `/items` | Daftar semua barang (opsional `?status=open`) |
| GET | `/items/{id}` | Detail satu barang |
| PUT | `/items/{id}` | Update data / ubah status |
| DELETE | `/items/{id}` | Hapus laporan |

Contoh request:

```bash
curl -X POST https://<api-id>.execute-api.us-east-1.amazonaws.com/items \
  -H "Content-Type: application/json" \
  -d '{"title":"Dompet hitam","type":"lost","location":"Gedung C","contact":"08xx"}'
```

## 5. Security & IAM
- Lambda memakai `LabRole` (Learner Lab tidak mengizinkan pembuatan role baru).
- Input divalidasi di Lambda sebelum ditulis ke DynamoDB.
- Tidak ada credential di dalam repo.
- <opsional: API key / usage plan>

## 6. Struktur Repository

```
lost-and-found/
├── README.md
├── docs/
│   ├── architecture.png
│   └── design-brief.md
├── lambda/
│   └── handler.py
├── events/          # contoh payload untuk test
└── screenshots/     # bukti AWS
```

## 7. Deployment Plan

1. Buat tabel DynamoDB `LostFoundItems` (partition key `itemId`, on-demand).
2. Buat fungsi Lambda, upload `lambda/handler.py`, set execution role ke `LabRole`.
3. Buat HTTP API di API Gateway, tambahkan route sesuai tabel endpoint, integrasikan dengan Lambda.
4. Deploy stage dan catat Invoke URL.
5. Uji dengan `curl` / Postman.

## 8. Bukti Setup AWS (Week 12)

## 9. Progress

## 10. Catatan & Keterbatasan
- Memakai AWS Learner Lab, sehingga resource mengikuti batas sesi lab.
- Region: us-east-1.
