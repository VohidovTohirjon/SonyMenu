<p align="center"><img src="docs/icon.png" width="128" alt=""></p>

<h1 align="center">SonyMenu</h1>

<p align="center">Значок в строке меню macOS для наушников Sony WH-1000XM5 и XM6: заряд и переключение шумоподавления в один клик, как у AirPods.</p>

<p align="center"><a href="#english">English below</a></p>

---

## Что умеет

- Значок наушников появляется в строке меню, когда наушники подключены, и пропадает, когда отключены.
- Клик по значку открывает панель в стиле Liquid Glass:
  - заряд батареи и значок зарядки;
  - режимы: **Шумоподавление**, **Внешний звук**, **Выключено**;
  - для внешнего звука: уровень от 1 до 20 и **Фокус на голосе**;
  - переключатель **Автозапуск** (запуск при входе в систему).
- Работает без официального приложения Sony и без интернета: всё идёт напрямую по Bluetooth.

## Совместимость

| Наушники | Статус |
| --- | --- |
| WH-1000XM5 | работает, проверено |
| WH-1000XM6 | должно работать (тот же протокол), не проверено |
| Вкладыши Sony (WF-1000XM5/XM6, LinkBuds и др.) | частично: режимы могут работать, заряд пока не показывается |
| WH-1000XM4, XM3 и старше | не поддерживаются (старая версия протокола) |

Нужна **macOS 26 или новее** (Liquid Glass). Apple Silicon и Intel.

## Установка

1. Скачайте `SonyMenu.zip` со страницы [Releases](../../releases/latest) и распакуйте.
2. Перетащите `SonyMenu.app` в папку «Программы».
3. Приложение не подписано сертификатом Apple, поэтому при первом запуске macOS его заблокирует. Откройте **Системные настройки → Конфиденциальность и безопасность**, внизу нажмите **«Всё равно открыть»** рядом с SonyMenu.
   Или одной командой в Терминале:
   ```bash
   xattr -dr com.apple.quarantine /Applications/SonyMenu.app
   ```
4. Разрешите доступ к Bluetooth, когда macOS спросит.
5. Подключите наушники: значок появится в строке меню.

> Значка не видно? Если строка меню переполнена, macOS прячет значки, которые не помещаются (особенно на MacBook с вырезом). Переключитесь на Finder, у него короткое меню, или уберите лишние значки, перетащив их с зажатой ⌘.

## Сборка из исходников

Нужны инструменты разработчика Xcode (`xcode-select --install`).

```bash
git clone https://github.com/ellyormakhmudov/SonyMenu.git
cd SonyMenu
./build.sh --install
```

`./build.sh --zip` собирает архив для релиза.

## Диагностика

Приложение пишет журнал в `~/Library/Logs/SonyMenu.log`. Если ваши наушники не работают, приложите этот файл к [issue](../../issues).

Проверка без интерфейса: выводит, что ответили наушники, и завершается.

```bash
open -W --stdout /dev/stdout /Applications/SonyMenu.app --args --probe
```

## Как это устроено

Наушники Sony принимают команды по Bluetooth RFCOMM (протокол «MDR», тот же, что у приложения Sony Sound Connect). SonyMenu открывает этот канал, запрашивает заряд и состояние шумоподавления и отправляет команды смены режима. Протокол описан в открытом проекте [mos9527/SonyHeadphonesClient](https://github.com/mos9527/SonyHeadphonesClient) (MIT); здесь он заново реализован на Swift.

- `Sources/SonyMenu/MDR.swift`: упаковка и разбор пакетов.
- `Sources/SonyMenu/Headphones.swift`: Bluetooth-соединение, заряд, режимы.
- `Sources/SonyMenu/Panel.swift`: панель на SwiftUI.
- `Sources/SonyMenu/StatusController.swift`: значок и выпадающее окно.

## Отказ от ответственности

Неофициальный проект, никак не связан с Sony Group Corporation. Sony, WH-1000XM5 и WH-1000XM6 являются товарными знаками их владельцев. Используйте на свой риск.

Лицензия: [MIT](LICENSE).

---

<a id="english"></a>

## English

A macOS menu bar app for Sony WH-1000XM5 / XM6: battery level and noise cancelling / ambient sound control in one click, AirPods-style.

- Icon appears in the menu bar while the headphones are connected.
- Liquid Glass dropdown: battery, **Noise cancelling / Ambient sound / Off**, ambient level 1–20, focus on voice, launch at login.
- Talks to the headphones directly over Bluetooth; no Sony app, no internet.

**Requirements:** macOS 26+, Apple Silicon or Intel. Tested on WH-1000XM5; XM6 should work (same protocol) but is untested. XM4 and older are not supported.

**Install:** download `SonyMenu.zip` from [Releases](../../releases/latest), move the app to Applications. It is not notarized, so allow it in *System Settings → Privacy & Security → Open Anyway* (or run `xattr -dr com.apple.quarantine /Applications/SonyMenu.app`), then allow Bluetooth access.

**Build:** `./build.sh --install` (needs Xcode command line tools).

Protocol knowledge comes from [mos9527/SonyHeadphonesClient](https://github.com/mos9527/SonyHeadphonesClient) (MIT), reimplemented in Swift. Unofficial project, not affiliated with Sony. MIT licensed.
