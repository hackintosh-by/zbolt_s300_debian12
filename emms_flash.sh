#!/bin/bash

# --- НАСТРОЙКИ ---
IMAGE_PATH="/home/rock/image.img.xz"
# -----------------

# Проверка запуска от root
if [ "$EUID" -ne 0 ]; then
  echo "Ошибка: Запустите скрипт через sudo!"
  exit 1
fi

echo "=== АВТОМАТИЧЕСКАЯ ПРОШИВКА EMMC ==="

# 1. ПРОВЕРКА ОБРАЗА
if [ ! -f "$IMAGE_PATH" ]; then
    echo "Ошибка: Файл образа не найден по пути: $IMAGE_PATH"
    exit 1
fi

# 2. ОПРЕДЕЛЕНИЕ ДИСКОВ
# Находим устройство, на котором смонтирован корень '/' (это наша SD карта)
CURRENT_ROOT_DEV=$(findmnt -n -o SOURCE /)
# Отрезаем 'p1', 'p2' и т.д., чтобы получить имя диска (например, mmcblk1)
CURRENT_DISK=$(lsblk -no pkname "$CURRENT_ROOT_DEV")

echo "Текущая система загружена с: $CURRENT_DISK (SD-карта)"

# Ищем eMMC. Это должно быть устройство mmcblk*, которое НЕ является текущим диском.
# Обычно mmcblk0 или mmcblk1.
if [ "$CURRENT_DISK" == "mmcblk0" ]; then
    TARGET_DISK="/dev/mmcblk1"
elif [ "$CURRENT_DISK" == "mmcblk1" ]; then
    TARGET_DISK="/dev/mmcblk0"
else
    # Если вдруг названия другие (редко), пробуем угадать или выходим
    echo "Внимание: Нестандартные имена дисков."
    # Пытаемся найти свободный mmcblk
    TARGET_NAME=$(lsblk -d -n -o NAME | grep mmcblk | grep -v "$CURRENT_DISK" | head -n 1)
    if [ -z "$TARGET_NAME" ]; then
        echo "Ошибка: Не удалось найти второй диск (eMMC). Проверьте lsblk."
        exit 1
    fi
    TARGET_DISK="/dev/$TARGET_NAME"
fi

echo "Целевой диск для прошивки (eMMC): $TARGET_DISK"
echo "---------------------------------------------------"
echo "ВНИМАНИЕ! ВСЕ ДАННЫЕ НА $TARGET_DISK БУДУТ УНИЧТОЖЕНЫ!"
echo "Будет записан образ: $IMAGE_PATH"
echo "---------------------------------------------------"

# Тайм-аут для отмены (можно убрать для полной автоматики)
read -p "Нажмите Enter для старта или Ctrl+C для отмены..."

# 3. ПОДГОТОВКА И ПРОШИВКА
echo "[1/4] Размонтирование разделов на $TARGET_DISK..."
umount ${TARGET_DISK}* 2>/dev/null || true

echo "[2/4] Очистка таблицы разделов..."
wipefs -a --force "$TARGET_DISK"
# Затираем начало диска (Bootloader area), чтобы убрать старый мусор
dd if=/dev/zero of="$TARGET_DISK" bs=1M count=16 status=none

echo "[3/4] Запись образа..."
# Используем PV если установлен (для красивого прогресса), иначе просто pipe
if command -v pv >/dev/null; then
    xz -dc "$IMAGE_PATH" | pv | dd of="$TARGET_DISK" bs=1M
else
    xz -dc "$IMAGE_PATH" | dd of="$TARGET_DISK" bs=1M status=progress
fi

echo "[4/4] Синхронизация данных (sync)..."
sync

echo "=== ГОТОВО! ==="
echo "Теперь вы можете выключить плату, вынуть SD-карту и загрузиться с eMMC."
