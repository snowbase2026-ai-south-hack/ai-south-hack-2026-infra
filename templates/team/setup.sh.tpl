#!/usr/bin/env bash
# =============================================================================
# AI South Hack — Setup SSH access for ${team_id}
# =============================================================================
set -e

# Keep terminal open on error (useful when double-clicking the script)
trap 'echo ""; echo "x  Ошибка на строке $LINENO. Нажми Enter для выхода."; read -r; exit 1' ERR

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SSH_DIR="$HOME/.ssh/ai-south-hack"
KEY_NAME="${team_id}-key"
MAIN_CONFIG="$HOME/.ssh/config"
INCLUDE_LINE="Include $SSH_DIR/ssh-config"

echo "==> Создаём директорию $SSH_DIR"
mkdir -p "$SSH_DIR"
mkdir -p "$HOME/.ssh"

echo "==> Копируем ключи"
cp "$SCRIPT_DIR/$KEY_NAME"     "$SSH_DIR/$KEY_NAME"
cp "$SCRIPT_DIR/$KEY_NAME.pub" "$SSH_DIR/$KEY_NAME.pub"
cp "$SCRIPT_DIR/ssh-config"    "$SSH_DIR/ssh-config"

echo "==> Устанавливаем права доступа"
chmod 700 "$SSH_DIR"
chmod 600 "$SSH_DIR/$KEY_NAME"
chmod 644 "$SSH_DIR/$KEY_NAME.pub"
chmod 644 "$SSH_DIR/ssh-config"

echo "==> Добавляем конфиг в $MAIN_CONFIG"
touch "$MAIN_CONFIG"
chmod 600 "$MAIN_CONFIG"
if grep -qF "$INCLUDE_LINE" "$MAIN_CONFIG" 2>/dev/null; then
  echo "    (уже есть, пропускаем)"
else
  tmp=$(mktemp)
  printf '%s\n\n' "$INCLUDE_LINE" > "$tmp"
  cat "$MAIN_CONFIG" >> "$tmp"
  mv "$tmp" "$MAIN_CONFIG"
  chmod 600 "$MAIN_CONFIG"
  echo "    Добавлено."
fi

echo "==> Проверяем соединение..."
if ssh -o ConnectTimeout=10 -o BatchMode=yes ${team_id} echo "OK" 2>/dev/null; then
  echo ""
  echo "v  Всё готово! Подключайся командой:"
  echo ""
  echo "    ssh ${team_id}"
  echo ""
else
  echo ""
  echo "!  Ключи установлены, но соединение не проверено (VM может быть ещё недоступна)."
  echo "   Попробуй подключиться позже:"
  echo ""
  echo "    ssh ${team_id}"
  echo ""
fi

read -rp "Нажми Enter для выхода..."
