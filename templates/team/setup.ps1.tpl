# =============================================================================
# AI South Hack — Setup SSH access for ${team_id}
# =============================================================================
$ErrorActionPreference = "Stop"

# Keep window open on both success and error
trap {
  Write-Host ""
  Write-Host "x  Ошибка: $_" -ForegroundColor Red
  Write-Host ""
  Read-Host "Нажми Enter для выхода"
  exit 1
}

$ScriptDir  = Split-Path -Parent $MyInvocation.MyCommand.Path
$SshDir     = Join-Path $HOME ".ssh\ai-south-hack"
$KeyName    = "${team_id}-key"
$MainConfig = Join-Path $HOME ".ssh\config"
$IncludeLine = "Include $SshDir\ssh-config"

Write-Host "==> Создаём директорию $SshDir"
New-Item -ItemType Directory -Force -Path $SshDir       | Out-Null
New-Item -ItemType Directory -Force -Path "$HOME\.ssh"  | Out-Null

Write-Host "==> Копируем ключи"
Copy-Item "$ScriptDir\$KeyName"     "$SshDir\$KeyName"     -Force
Copy-Item "$ScriptDir\$KeyName.pub" "$SshDir\$KeyName.pub" -Force
Copy-Item "$ScriptDir\ssh-config"   "$SshDir\ssh-config"   -Force

Write-Host "==> Устанавливаем права доступа на приватный ключ"
$acl = Get-Acl "$SshDir\$KeyName"
$acl.SetAccessRuleProtection($true, $false)
$rule = New-Object System.Security.AccessControl.FileSystemAccessRule(
  $env:USERNAME, "FullControl", "Allow"
)
$acl.SetAccessRule($rule)
Set-Acl "$SshDir\$KeyName" $acl

Write-Host "==> Добавляем конфиг в $MainConfig"
if (-not (Test-Path $MainConfig)) {
  New-Item -ItemType File -Force $MainConfig | Out-Null
}
$existing = Get-Content $MainConfig -Raw -ErrorAction SilentlyContinue
if ($existing -and $existing.Contains($IncludeLine)) {
  Write-Host "    (уже есть, пропускаем)"
} else {
  $newContent = "$IncludeLine`r`n`r`n$existing"
  Set-Content $MainConfig $newContent -NoNewline
  Write-Host "    Добавлено."
}

Write-Host "==> Проверяем соединение..."
$null = & {
  $ErrorActionPreference = "Continue"
  ssh -o ConnectTimeout=10 -o BatchMode=yes ${team_id} echo OK 2>&1
}
if ($LASTEXITCODE -eq 0) {
  Write-Host ""
  Write-Host "v  Всё готово! Подключайся командой:" -ForegroundColor Green
  Write-Host ""
  Write-Host "   ssh ${team_id}" -ForegroundColor Cyan
  Write-Host ""
} else {
  Write-Host ""
  Write-Host "!  Ключи установлены, но соединение не проверено (VM может быть ещё недоступна)." -ForegroundColor Yellow
  Write-Host "   Попробуй подключиться позже:" -ForegroundColor Yellow
  Write-Host ""
  Write-Host "   ssh ${team_id}" -ForegroundColor Cyan
  Write-Host ""
}

Read-Host "Нажми Enter для выхода"
