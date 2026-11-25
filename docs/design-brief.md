# Design Brief: Kampus Lost & Found (AWS Serverless)

**Nama / NIM:** <nama> / <nim>
**Track:** C, Serverless

## Use case
<isi: 2-3 kalimat masalah dan solusi>

## Arsitektur
API Gateway -> Lambda (LabRole) -> DynamoDB. Lihat `architecture.png`.

## Data entity: Item
`itemId` (PK), `title`, `description`, `type`, `location`, `contact`, `status`, `createdAt`

## CRUD endpoints
| Method | Path | Fungsi |
|---|---|---|
| POST | `/items` | Create |
| GET | `/items`, `/items/{id}` | Read |
| PUT | `/items/{id}` | Update |
| DELETE | `/items/{id}` | Delete |

## IAM / Security
<isi: LabRole, validasi input, tanpa credential di repo>
