# Amazon S3 Enterprise Backup & Storage Lifecycle Automation

![AWS S3](https://img.shields.io/badge/Amazon_S3-569A31?style=for-the-badge&logo=amazons3&logoColor=white)
![PowerShell](https://img.shields.io/badge/PowerShell-5391FE?style=for-the-badge&logo=powershell&logoColor=white)
![Bash](https://img.shields.io/badge/Bash%20%2F%20Shell-121011?style=for-the-badge&logo=gnu-bash&logoColor=white)
![Python](https://img.shields.io/badge/Python-3776AB?style=for-the-badge&logo=python&logoColor=white)

> **English:** Complete automation suite for hybrid corporate backups (**Windows Server & Linux to Amazon S3**), including compressed archive staging, **SHA-256 integrity verification**, Server-Side Encryption (`SSE-S3` / `SSE-KMS`), automated **S3 Lifecycle tiering** (`Standard-IA` -> `Glacier` -> `Deep Archive`), SLA freshness auditing via Python (`boto3`), and anti-ransomware least-privilege IAM policies.
>
> **Português:** Suíte completa de automação para backups corporativos híbridos (**Windows Server e Linux para o Amazon S3**), incluindo compactação em staging local, **verificação de integridade SHA-256**, criptografia no servidor (`SSE-S3` / `SSE-KMS`), **políticas de ciclo de vida S3** (`Standard-IA` -> `Glacier` -> `Deep Archive`), auditoria de SLA de backups via Python (`boto3`) e políticas IAM de privilégio mínimo contra ransomware.

---

## Architecture & Backup Flow / Arquitetura e Fluxo de Backup

1. **Local Compression & Hashing (On-Premises / Hybrid Servers)**:
   - Windows Server (`Invoke-WindowsServerToS3Backup.ps1`) and Linux (`s3-linux-backup-sync.sh`) compress target directories/databases into timestamped archives and generate a `.sha256` integrity manifest.
2. **Encrypted Upload to Amazon S3**:
   - Archives are uploaded to structured prefixes (`s3://<bucket>/backups/<hostname>/<YYYY-MM-DD>/`) with mandatory Server-Side Encryption (`AES256`) and direct placement into cost-optimized storage classes (`STANDARD_IA`).
3. **Anti-Ransomware IAM Isolation**:
   - Backup agents use an append-only IAM Policy (`policies/s3-backup-iam-least-privilege.json`) that grants `s3:PutObject` but explicitly denies `s3:DeleteObject`, ensuring a compromised host cannot wipe cloud backups.
4. **Automated Storage Tiering (FinOps)**:
   - S3 Lifecycle rules (`policies/s3-backup-lifecycle-policy.json`) transition backups to `GLACIER` after 90 days and `DEEP_ARCHIVE` after 180 days, and abort incomplete multipart uploads after 7 days.
5. **Daily SLA & Freshness Verification**:
   - `python/s3_backup_verifier.py` inspects the S3 bucket to verify that every server completed a backup within the last 24 hours and summarizes storage usage by Storage Class.

---

## Repository Structure / Estrutura do Repositório

| File | Description (EN) | Descrição (PT-BR) |
| :--- | :--- | :--- |
| [`powershell/Invoke-WindowsServerToS3Backup.ps1`](powershell/Invoke-WindowsServerToS3Backup.ps1) | Compresses Windows Server directories, generates SHA-256 manifests, uploads to Amazon S3 with SSE, and rotates local staging files. | Compacta diretórios no Windows Server, gera manifesto SHA-256, envia ao Amazon S3 com criptografia SSE e limpa arquivos locais antigos. |
| [`bash/s3-linux-backup-sync.sh`](bash/s3-linux-backup-sync.sh) | Bash script for Linux servers to archive directories (`.tar.gz`), generate SHA-256 checksums, and upload to Amazon S3 via AWS CLI. | Script Bash para servidores Linux que compacta diretórios (`.tar.gz`), gera hash SHA-256 e envia para o Amazon S3 via AWS CLI. |
| [`python/s3_backup_verifier.py`](python/s3_backup_verifier.py) | Python (`boto3`) tool that audits S3 backup prefixes to detect missing/stale backups (>24h) and reports storage consumption by tier. | Utilitário em Python (`boto3`) que audita os prefixos no S3 para detectar backups atrasados (>24h) e calcula o consumo por classe de armazenamento. |
| [`policies/s3-backup-lifecycle-policy.json`](policies/s3-backup-lifecycle-policy.json) | Amazon S3 Lifecycle Configuration JSON transitioning backups across `STANDARD_IA`, `GLACIER`, and `DEEP_ARCHIVE`. | Configuração de Lifecycle do Amazon S3 (JSON) movendo backups automaticamente entre `STANDARD_IA`, `GLACIER` e `DEEP_ARCHIVE`. |
| [`policies/s3-backup-iam-least-privilege.json`](policies/s3-backup-iam-least-privilege.json) | Least-privilege IAM policy for backup agents (allows upload, denies deletion to protect against ransomware). | Política IAM de privilégio mínimo para agentes de backup (permite upload e bloqueia exclusão para proteção contra ransomware). |

---

## Usage Examples / Exemplos de Uso

### 1. Windows Server Backup to S3 (PowerShell)
```powershell
.\powershell\Invoke-WindowsServerToS3Backup.ps1 `
    -SourcePaths @("D:\Shares\Finance", "D:\SQLBackups") `
    -S3Bucket "corp-infra-backups-prod" `
    -StorageClass "STANDARD_IA" `
    -LocalRetentionDays 3
```

### 2. Linux Server Backup to S3 (Bash)
```bash
chmod +x bash/s3-linux-backup-sync.sh
./bash/s3-linux-backup-sync.sh /etc/nginx corp-infra-backups-prod STANDARD_IA 3
```

### 3. Verify Daily Backup SLA & Storage Tiers (Python Boto3)
```bash
python python/s3_backup_verifier.py \
    --bucket corp-infra-backups-prod \
    --prefix backups/ \
    --max-age-hours 26
```

### 4. Apply S3 Lifecycle Policy via AWS CLI
```bash
aws s3api put-bucket-lifecycle-configuration \
    --bucket corp-infra-backups-prod \
    --lifecycle-configuration file://policies/s3-backup-lifecycle-policy.json
```
