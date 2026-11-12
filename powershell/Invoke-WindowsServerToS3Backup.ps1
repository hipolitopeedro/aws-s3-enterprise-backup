<#
.SYNOPSIS
    Compresses Windows Server directories, generates SHA-256 checksums, and uploads backups to Amazon S3.
    Compacta diretórios do Windows Server, gera hashes SHA-256 e envia backups para o Amazon S3.

.DESCRIPTION
    EN: Designed for Windows Server scheduled tasks. Compresses specified folders into a local staging
        directory, computes a SHA-256 hash manifest, uploads both files to Amazon S3 with Server-Side
        Encryption (AES256) and configurable Storage Class (e.g., STANDARD_IA, GLACIER_IR), and cleans
        up local staging archives older than LocalRetentionDays.
    PT: Projetado para o Agendador de Tarefas do Windows Server. Compacta pastas definidas em um diretório
        de staging local, calcula manifesto SHA-256, envia os arquivos para o Amazon S3 com criptografia
        SSE (AES256) e classe de armazenamento configurável, e remove arquivos locais antigos.
#>

[CmdletBinding()]
param (
    [Parameter(Mandatory = $true)]
    [string[]]$SourcePaths,

    [Parameter(Mandatory = $true)]
    [string]$S3Bucket,

    [Parameter(Mandatory = $false)]
    [string]$S3Prefix = "backups/$($env:COMPUTERNAME.ToLower())",

    [Parameter(Mandatory = $false)]
    [ValidateSet("STANDARD", "STANDARD_IA", "ONEZONE_IA", "GLACIER_IR", "DEEP_ARCHIVE")]
    [string]$StorageClass = "STANDARD_IA",

    [Parameter(Mandatory = $false)]
    [string]$StagingDir = "C:\BackupStaging",

    [Parameter(Mandatory = $false)]
    [int]$LocalRetentionDays = 3
)

$ErrorActionPreference = "Stop"

function Write-BackupLog {
    param([string]$Message, [string]$Level = "INFO")
    $Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $Line = "[$Timestamp] [$Level] $Message"
    Write-Host $Line
    if (Test-Path $StagingDir) {
        Add-Content -Path (Join-Path $StagingDir "s3-backup.log") -Value $Line
    }
}

if (-not (Test-Path -Path $StagingDir)) {
    New-Item -ItemType Directory -Path $StagingDir -Force | Out-Null
}

$DateFolder = Get-Date -Format "yyyy-MM-dd"
$Timestamp  = Get-Date -Format "yyyyMMdd_HHmmss"

foreach ($Source in $SourcePaths) {
    if (-not (Test-Path -Path $Source)) {
        Write-BackupLog "Source path not found: $Source" -Level "WARN"
        continue
    }

    $FolderName   = Split-Path -Path $Source -Leaf
    $ArchiveName  = "${FolderName}_${Timestamp}.zip"
    $ArchivePath  = Join-Path $StagingDir $ArchiveName
    $ChecksumPath = "${ArchivePath}.sha256"

    Write-BackupLog "Compressing '$Source' -> '$ArchivePath'..."
    Compress-Archive -Path $Source -DestinationPath $ArchivePath -CompressionLevel Optimal -Force

    $HashObj = Get-FileHash -Path $ArchivePath -Algorithm SHA256
    "$($HashObj.Hash.ToLower())  $ArchiveName" | Set-Content -Path $ChecksumPath -Encoding ASCII
    Write-BackupLog "Generated SHA-256 checksum: $($HashObj.Hash)"

    $S3TargetUri = "s3://$S3Bucket/$S3Prefix/$DateFolder/"
    Write-BackupLog "Uploading '$ArchiveName' to '$S3TargetUri' (StorageClass: $StorageClass)..."

    & aws s3 cp $ArchivePath "$S3TargetUri$ArchiveName" --storage-class $StorageClass --sse AES256 --only-show-errors
    if ($LASTEXITCODE -ne 0) {
        Throw "AWS CLI upload failed for $ArchiveName with exit code $LASTEXITCODE"
    }

    & aws s3 cp $ChecksumPath "$S3TargetUri$ArchiveName.sha256" --storage-class $StorageClass --sse AES256 --only-show-errors
    Write-BackupLog "Successfully uploaded '$ArchiveName' and SHA-256 manifest to Amazon S3." -Level "OK"
}

# Rotate local staging archives
Write-BackupLog "Cleaning up local staging files older than $LocalRetentionDays day(s)..."
$Cutoff = (Get-Date).AddDays(-$LocalRetentionDays)
Get-ChildItem -Path $StagingDir -File | Where-Object {
    ($_.Extension -in @('.zip', '.sha256')) -and ($_.LastWriteTime -lt $Cutoff)
} | ForEach-Object {
    Write-BackupLog "Removing expired local staging file: $($_.Name)"
    Remove-Item -Path $_.FullName -Force
}

Write-BackupLog "Backup job completed successfully." -Level "OK"
