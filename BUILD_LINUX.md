# Сборка Where Am I - Backrooms под Linux

Краткая инструкция по сборке проекта из исходного кода с помощью Godot Engine 4.

---

## 1. Системные требования и зависимости

Для сборки и запуска на дистрибутивах Debian / Ubuntu / Linux Mint:

```bash
sudo apt update
sudo apt install -y wget unzip libvulkan1 libgl1-mesa-dri libx11-6 libxcursor1 libxinerama1 libxrandr2 libxi6 libasound2
```

---

## 2. Установка Godot 4 CLI

Скачайте официальный headless-бинарник Godot (версия 4.x):

```bash
wget https://github.com/godotengine/godot/releases/download/4.7.2-stable/Godot_v4.7.2-stable_linux.x86_64.zip
unzip Godot_v4.7.2-stable_linux.x86_64.zip
chmod +x Godot_v4.7.2-stable_linux.x86_64
sudo mv Godot_v4.7.2-stable_linux.x86_64 /usr/local/bin/godot
```

---

## 3. Сборка игры (PCK / Исполняемый пакет)

1. Распакуйте архив с исходным кодом и перейдите в папку:
```bash
tar -xzf whereami-backrooms-source.tar.gz
cd whereami-backrooms-source
```

2. Соберите пакет ресурсов проекта (`WhereAmI.pck`):
```bash
mkdir -p build
godot --headless --export-pack "Windows Desktop" build/WhereAmI.pck
```
*(Или экспортируйте под Linux-шаблон, если установлены export templates: `godot --headless --export-release "Linux" build/WhereAmI.x86_64`)*.

---

## 4. Запуск

### Вариант А: Запуск с собранным PCK
```bash
godot --main-pack build/WhereAmI.pck
```

### Вариант Б: Прямой запуск из исходников без предварительной сборки
```bash
godot --path .
```
