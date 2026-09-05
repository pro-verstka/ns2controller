# ns2controller

Поддержка **Nintendo Switch 2 Pro Controller** по USB в macOS без kext/dext, entitlements и root.
Проверено на macOS 26.6 с Pro Controller 2 (`057E:2069`). NSO GameCube (`2073`) и Joy-Con 2 в зарядном грипе (`2066`/`2067`) заведены в матчинг, но не проверялись.

## Как это работает

По USB контроллер выставляет два интерфейса:

- **interface 0** — стандартный HID Gamepad (Usage Page 1, Usage 5): 21 кнопка и четыре 12-битные оси. macOS вешает на него свой драйвер, но контроллер молчит, пока хост его не «разбудит»;
- **interface 1** — vendor-интерфейс (класс 0xFF) с bulk-endpoint'ами `0x02 OUT` / `0x82 IN`, куда шлётся последовательность инициализации.

`ns2ctl daemon` (LaunchAgent) ловит подключение контроллера через IOKit-нотификации, открывает interface 1 через IOUSBHost, шлёт wake-up и переключает контроллер в HID-совместимый формат отчётов (report ID `0x09`). Дальше macOS сама разбирает отчёты по дескриптору, а Steam, CrossOver/Wine и любые IOHIDManager-приложения видят обычный геймпад. Держать USB-интерфейс открытым не нужно: состояние сохраняется до переподключения.

## Установка

```bash
./scripts/install.sh
```

Скрипт собирает release-бинарник, кладёт его в `~/.local/bin/ns2ctl`, ставит LaunchAgent `com.p1rate.ns2controller` (автозапуск при логине, `KeepAlive`) и пишет лог в `~/Library/Logs/ns2controller.log`.

Удаление:

```bash
./scripts/uninstall.sh
```

## Команды `ns2ctl`

| Команда | Что делает |
|---|---|
| `ns2ctl daemon [--led N] [--format 9\|5] [--variant sdl\|extended] [--hold] [-v]` | Демон: hot-plug, wake-up, повтор после сна Mac |
| `ns2ctl wake [--format 9\|5] [--led N] [-v]` | Разовое пробуждение подключённого контроллера |
| `ns2ctl list` | Показать USB-интерфейс и HID-устройство контроллера |
| `ns2ctl info` | HID Report Descriptor и список элементов |
| `ns2ctl monitor [--values] [--no-reports]` | Сырые input-отчёты (дифф по байтам) и/или распарсенные значения кнопок/осей |
| `ns2ctl sample [SECONDS]` | Гистограмма report ID за интервал |
| `ns2ctl led N` | Индикатор игрока (1–8) |
| `ns2ctl format 9\|5` | Переключить формат отчётов на уже разбуженном контроллере |
| `ns2ctl reset` | Сбросить контроллер (переэнумерация USB) |
| `ns2ctl send HEX...` | Отправить произвольную bulk-команду и показать ответ |
| `ns2ctl flash 0xADDR` | Прочитать блок flash (калибровка и т.п.) |
| `ns2ctl steam-mapping` | Строки `SDL_GAMECONTROLLERCONFIG` для Steam |

## Раскладка HID

Порядок кнопок в отчёте (HID Button N, снято на реальном контроллере):

| N | Кнопка | N | Кнопка | N | Кнопка |
|---|---|---|---|---|---|
| 1 | B | 8 | RS (нажатие) | 15 | − |
| 2 | A | 9 | D-pad ↓ | 16 | LS (нажатие) |
| 3 | Y | 10 | D-pad → | 17 | Home |
| 4 | X | 11 | D-pad ← | 18 | Capture |
| 5 | R | 12 | D-pad ↑ | 19 | GR |
| 6 | ZR | 13 | L | 20 | GL |
| 7 | + | 14 | ZL | 21 | C |

Оси (0…4095, центр ≈ 2048): `X`/`Y` — левый стик, `Rx`/`Rz` — правый. Вправо — рост значения, **вверх — тоже рост** (инверсия относительно HID-конвенции; в SDL-маппинге учтено через `~`). Hat switch в дескрипторе нет: D-pad — четыре кнопки.

## Steam

Steam видит контроллер как `Nintendo Switch 2 Pro Controller` через SDL, но его встроенный маппинг для `057e/2069` (`a:b1,b:b0,…,dpup:h0.1`) сделан под другой порядок кнопок: D-pad попадает на нажатия стиков, `+` на триггер, вертикаль стиков перевёрнута. Правильный маппинг лежит в `steam/ns2pro.mapping`; поставить его постоянно (Steam должен быть закрыт, `config.vdf` бэкапится рядом):

```bash
./scripts/steam-install-mapping.sh
```

Скрипт записывает ключ `SDL_GamepadBind` в `~/Library/Application Support/Steam/config/config.vdf` — то же место, куда Steam сохраняет раскладки из своего UI. Разовый вариант без правки конфига — запуск Steam с переменной окружения:

```bash
./scripts/steam-with-ns2.sh
```

Маппинг позиционный (SDL `a` = нижняя кнопка = Nintendo B). Если хочется, чтобы игры видели буквы как на контроллере, включи в Steam → Settings → Controller опцию «Use Nintendo Button Layout». В строке SDL2 C-кнопка не назначена (нет имени), GL/GR — `paddle2`/`paddle1`, Capture — `misc1`. GUID: `030002697e05…0102` (с CRC имени, как в логе Steam), плюс варианты без CRC и со старой версией `0001`.

## CrossOver / Wine

winebus в CrossOver работает через SDL-бэкенд (`Enable SDL=1`, в комплекте `libSDL2 2.30`). Устройство попадает в XInput (то, что видят современные игры вроде DMC или Blood of the Dawnwalker) только если у SDL есть для него маппинг; без маппинга это лишь DirectInput-джойстик (`joy.cpl` видит, игры — нет). Маппинг передаётся SDL через переменную окружения бутылки `SDL_GAMECONTROLLERCONFIG` (секция `[EnvironmentVariables]` в `cxbottle.conf`):

```bash
./scripts/crossover-install-mapping.sh Steam   # имя бутылки из ~/Library/Application Support/CrossOver/Bottles
```

После этого бутылку нужно перезапустить (закрыть все её Windows-программы), тогда winebus создаст XInput-геймпад с D-pad как hat и триггерами как осями.

**Не используйте ключ реестра `HKLM\System\CurrentControlSet\Services\winebus\map`.** В текущем Wine функция `sdl_bus_load_mappings` содержит ошибку (запись в `mappings[count]` после `count++`), и любое значение в этом ключе роняет `winedevice.exe` с winebus — в бутылке пропадают все геймпады. Скрипт удаляет этот ключ, если он есть.

## Протокол (bulk, interface 1)

Кадр: `[cmd, 0x91, 0x00, subcmd, 0x00, len, 0x00, 0x00] + payload[len]`. Ответ приходит по bulk IN и повторяет `cmd`/`subcmd`, байт 5 = `0xF8` — OK.

| Команда | Назначение |
|---|---|
| `07 91 00 01 …` | начало сессии |
| `0C 91 00 02 … 27` / `0C 91 00 04 … 27` | конфигурация отчёта/IMU (значение не влияет на формат) |
| `11 91 00 01 …`, `0A 91 00 08 …`, `01 91 00 0C …`, `01 91 00 01 …`, `08 91 00 02 … 01` | шаги инициализации из SDL |
| `03 91 00 0A 00 04 00 00 XX 00 00 00` | **формат входного отчёта**: `XX=09` — HID (кнопки/оси по дескриптору), `XX=05` — vendor (63 байта, как в SDL/BLE) |
| `03 91 00 0D 00 08 00 00 01 00 FF FF FF FF FF FF` | запуск потока отчётов |
| `09 91 00 07 00 08 00 00 <mask> …` | индикатор игрока (`01, 03, 07, 0F, 09, 05, 0D, 06`) |
| `02 91 00 01 00 08 00 00 00 00 00 00 <addr LE32>` | чтение flash (ответ с 0x10) |
| `03 91 00 01 00 00 00 00` | **сброс** контроллера (переэнумерация USB) |

Отчёт `0x09` (64 байта): `[1..2]` счётчик, `[3..5]` 21 кнопка bit-packed, `[6..11]` четыре 12-битные оси (X, Y, Rx, Rz), дальше vendor-данные (IMU и т.п.). Отчёт `0x05`: `[5..8]` кнопки, `[11..16]` стики, `0x2B` метка времени, `0x31…0x3C` акселерометр/гироскоп.

## Ограничения

- **Только USB.** По Bluetooth контроллер использует проприетарный BLE GATT-протокол, и чтобы он стал системным геймпадом, нужно виртуальное HID-устройство — а это restricted-entitlement (`com.apple.developer.hid.virtual.device`) либо DriverKit с платным Apple Developer Program.
- **Стики отдаются сырыми, без калибровки.** В HID-режиме контроллер шлёт необработанные 12-битные значения: центр ≈ 2004/2104 (левый) и 2043/2114 (правый), физический ход ≈ ±1550 при логическом диапазоне 0…4095. Игры и SDL масштабируют по дескриптору, поэтому полное отклонение выглядит как ~75 % — персонаж «идёт», а не бежит, порог спринта не достигается. Заводская калибровка лежит во flash (`ns2ctl flash 0x13080` / `0x130C0`, со смещения 0x28: центр, ход вниз, ход вверх — три 12-битные пары), но применить её к HID-потоку без виртуального устройства негде: ни одна из проверенных конфигурационных команд (`0x0A/08`, `0x0A/02`, `0x08/02`, `0x0C/01…05`, `0x03/0B…0E`) режим стиков не меняет, winebus и SDL значения не масштабируют. Частичные обходы: в Steam Input — outer deadzone/anti-deadzone в раскладке игры (только для игр, идущих через Steam Input); в CrossOver — XInput-обёртка вроде x360ce с anti-deadzone.
- **GameController framework не видит устройство.** `GCController.controllers()` не возвращает generic HID-геймпад без hat switch и известного VID/PID, поэтому игры на GameController (Lies of P и большинство Unreal/Unity-портов, Apple Arcade) контроллер не увидят. Работают игры, читающие IOKit HID/SDL напрямую (Batman Arkham и другие порты Feral, сам Steam-клиент). Обход — Windows-версия игры в CrossOver.
- **Вибрация и гироскоп** до игр не доходят: у generic HID-геймпада нет канала для этого. Гироскоп лежит в vendor-байтах отчёта, при желании его можно отдавать эмуляторам через DSU/cemuhook-сервер.
- **D-pad — четыре кнопки, а не hat switch**; в Steam и в Wine (через SDL-маппинг) это учтено.

Все четыре первых пункта снимает виртуальный контроллер (DriverKit dext или CoreHID `HIDVirtualDevice`), для которого нужен платный Apple Developer Program: демон читал бы vendor-отчёт `0x05` с калибровкой и IMU и публиковал бы, например, виртуальный Xbox/DualSense-геймпад, который GameController framework и Steam понимают нативно.

## Диагностика

```bash
tail -f ~/Library/Logs/ns2controller.log
ns2ctl list
ns2ctl sample 1
ns2ctl monitor --values --no-reports
```

Если отчёты не идут — `ns2ctl reset`, демон разбудит контроллер заново. Кабель должен быть с data-линиями.

## Источники

- SDL3 `SDL_hidapi_switch2.c` — последовательность инициализации, LED, вибрация: https://github.com/libsdl-org/SDL/blob/main/src/joystick/hidapi/SDL_hidapi_switch2.c
- `ikz87/NSW2-controller-enabler` — расширенная последовательность: https://github.com/ikz87/NSW2-controller-enabler
- `dannydarvish/Switch2ProMac` — Steam на macOS через pyusb: https://github.com/dannydarvish/Switch2ProMac
- HID-дескриптор: https://github.com/raspberrypi/linux/issues/7374
