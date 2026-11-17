# Сборка Where Am I - Backrooms под Linux

Краткая инструкция по сборке проекта из исходного кода с помощью Godot Engine 4.7.

---

## 1. Системные требования и зависимости

Для сборки и запуска на дистрибутивах Debian / Ubuntu / Linux Mint:

```bash
sudo apt update
sudo apt install -y wget unzip libvulkan1 libgl1-mesa-dri libx11-6 libxcursor1 libxinerama1 libxrandr2 libxi6 libasound2
```

---

## 2. Установка Godot 4 CLI

Нужен именно Godot **4.7.x** (проверено на 4.7.2): более старые версии не запустят проект.

```bash
wget https://github.com/godotengine/godot/releases/download/4.7.2-stable/Godot_v4.7.2-stable_linux.x86_64.zip
unzip Godot_v4.7.2-stable_linux.x86_64.zip
chmod +x Godot_v4.7.2-stable_linux.x86_64
sudo mv Godot_v4.7.2-stable_linux.x86_64 /usr/local/bin/godot
```

---

## 3. Импорт ассетов (обязательный шаг после распаковки/клонирования)

В репозитории лежат исходные ассеты и их `.import`-файлы, но кэш импорта (`.godot/`) в git не хранится.
Без этого шага игра запустится с ошибками вида
`Failed loading resource: res://.godot/imported/... Make sure resources have been imported by opening the project in the editor at least once.`

```bash
godot --headless --path . --import
```

Команда открывает редактор в headless-режиме, импортирует все ассеты и завершается (вывода при успехе нет).

---

## 4. Запуск из исходников

```bash
godot --path .
```

Или одной командой (импорт + запуск): `./run.sh`

---

## 5. Сборка игры (PCK / Исполняемый пакет)

1. Распакуйте архив с исходным кодом и перейдите в папку:
```bash
tar -xzf whereami-backrooms-source.tar.gz
cd whereami-backrooms-source
```

2. Соберите пакет ресурсов проекта (`WhereAmI.pck`):
```bash
mkdir -p build
godot --headless --path . --export-pack "Linux x86_64" build/WhereAmI.pck
```
*(Или экспортируйте под Linux-шаблон, если установлены export templates: `godot --headless --path . --export-release "Linux x86_64" build/WhereAmI.x86_64`)*.

Доступные пресеты в `export_presets.cfg`: `Windows x86_64`, `Windows x86_32`, `Linux x86_64`, `Linux x86_32`.
Имя пресета должно совпадать точно, иначе экспорт завершится ошибкой «Preset not found».

---

## 6. Запуск

### Вариант А: Запуск с собранным PCK
```bash
godot --main-pack build/WhereAmI.pck
```

### Вариант Б: Прямой запуск из исходников без предварительной сборки
```bash
godot --headless --path . --import   # один раз после клонирования
godot --path .
```
