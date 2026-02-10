Скрипт emmc.sh разварачивате образ image.img.xz (которым может быть любой переименованный вами образ Debian) в eMMC память вашей ROCKPI 4B+. Когда операция будет завершена - вы можете достать загрузочную флешку и система автоматически загрузится из eMMC.

Нужно
1. Добавить права на исполнение
chmod +x flash_emmc.sh

3. Выполнить скрипт
sudo ./flash_emmc.sh

---

Для автоматизации создать сервис
sudo nano /etc/systemd/system/auto-flash.service

активировать
sudo systemctl enable auto-flash.service

Создайте файл /etc/systemd/system/auto-flash.service
sudo systemctl daemon-reload
sudo systemctl enable auto-flash.service

