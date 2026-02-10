#!/bin/bash
# Автоматическая прошивка eMMC с индикацией LED и логом

# --- НАСТРОЙКИ ---
# Путь к образу. Скрипт ищет его СНАЧАЛА на USB, ЗАТЕМ на самой SD-карте.
IMAGE_NAME="image.img.xz"
LOG_FILE="/var/log/flash_emmc.log"

# Индикация светодиодом (Heartbeat по умолчанию на Rock Pi)
LED_TRIGGER="/sys/class/leds/user-led2/trigger" # Зеленый LED
# -----------------

# Функция мигания LED (SOS при ошибке)
led_error() {
    echo "timer" > $LED_TRIGGER
    # Очень быстрое мигание
    echo 100 > "/sys/class/leds/user-led2/delay_on"
    echo 100 > "/sys/class/leds/user-led2/delay_off"
    exit 1
}

# Функция мигания LED (Процесс идет)
led_busy() {
    echo "timer" > $LED_TRIGGER
    # Медленное мигание (1 сек)
    echo 1000 > "/sys/class/leds/user-led2/delay_on"
    echo 1000 > "/sys/class/leds/user-led2/delay_off"
}

exec > >(tee -a "$LOG_FILE") 2>&1
echo "=== ЗАПУСК АВТО-ПРОШИВКИ $(date) ==="

# 1. Поиск eMMC (Цель)
# Ищем диск, который НЕ является текущим корнем
ROOT_DEV=$(findmnt -n -o SOURCE /)
ROOT_DISK=$(lsblk -no pkname "$ROOT_DEV")
# Обычно SD=mmcblk0 или 1. eMMC - другой.
TARGET_DISK=""
for dev in /dev/mmcblk0 /dev/mmcblk1; do
    name=$(basename $dev)
    if [ "$name" != "$ROOT_DISK" ] && [ -b "$dev" ]; then
        TARGET_DISK=$dev
        break
    fi
done

if [ -z "$TARGET_DISK" ]; then
    echo "ОШИБКА: eMMC диск не найден! (Текущий: $ROOT_DISK)"
    led_error
fi

echo "Цель (eMMC): $TARGET_DISK"
echo "Текущий (SD): /dev/$ROOT_DISK"

# 2. Поиск файла образа
IMAGE_PATH=""

# A. Проверяем USB-флешки (если вставлена)
# Монтируем все sd*1
for usb_part in /dev/sd*1; do
    [ -e "$usb_part" ] || continue
    mkdir -p /mnt/usb_check
    mount -o ro "$usb_part" /mnt/usb_check
    if [ -f "/mnt/usb_check/$IMAGE_NAME" ]; then
        IMAGE_PATH="/mnt/usb_check/$IMAGE_NAME"
        echo "Образ найден на USB: $IMAGE_PATH"
        break
    else
        umount /mnt/usb_check
    fi
done

# B. Если на USB нет, ищем на самой SD карте (в /root или /home/rock)
# B. Если на USB нет, ищем на самой SD карте
if [ -z "$IMAGE_PATH" ]; then
    # Проверяем вашу папку (Downloads обычно с большой буквы!)
    if [ -f "/home/radxa/Downloads/$IMAGE_NAME" ]; then
         IMAGE_PATH="/home/radxa/Downloads/$IMAGE_NAME"
    # Проверяем если вдруг папка с маленькой буквы (downloads)
    elif [ -f "/home/radxa/downloads/$IMAGE_NAME" ]; then
         IMAGE_PATH="/home/radxa/downloads/$IMAGE_NAME"
    # Стандартные пути
    elif [ -f "/root/$IMAGE_NAME" ]; then
        IMAGE_PATH="/root/$IMAGE_NAME"
    elif [ -f "/home/rock/$IMAGE_NAME" ]; then
        IMAGE_PATH="/home/rock/$IMAGE_NAME"
    fi
fi

if [ -z "$IMAGE_PATH" ]; then
    echo "ОШИБКА: Файл $IMAGE_NAME не найден ни на USB, ни на SD!"
    led_error
fi

echo "Используем образ: $IMAGE_PATH"
led_busy

# 3. Процесс прошивки
echo "Начинаем запись... Не выключайте питание!"

# Размонтирование и очистка
umount ${TARGET_DISK}* 2>/dev/null || true
wipefs -a --force "$TARGET_DISK"
dd if=/dev/zero of="$TARGET_DISK" bs=1M count=16 status=none

# Запись
if xz -dc "$IMAGE_PATH" | dd of="$TARGET_DISK" bs=4M status=progress conv=fsync; then
    echo "ЗАПИСЬ УСПЕШНА!"
    sync
else
    echo "ОШИБКА ПРИ ЗАПИСИ (dd вернул код ошибки)!"
    led_error
fi

# 4. Финиш
echo "Выключение системы..."
# Включаем LED постоянно, чтобы показать успех перед выключением
echo "default-on" > $LED_TRIGGER
sleep 5
poweroff
