# Проект KATE / ВЕБ-КАНАЛ (Documents/vk)

## Назначение
Переработать Kate Mobile (`com.perm.kate`, v133.11): оставить нативный UI, но все данные
(новости/диалоги/история/longpoll) получать через собственный **web-канал**
(живая браузерная сессия VK в WebView: куки → `web_token` → `web.api.vk.ru/method/*`),
чтобы уйти от флуд-банов (`error 9`) и лимитов официального API.

## Ключевые факты (доказано, 2026-10-08)
- Современный `m.vk.ru` НЕ использует `al_feed.php`/`al_im.php` (404/редиректы).
- Рабочий канал:
  1. Куки сессии WebView (`app_webview/Default/Cookies`);
  2. `POST https://login.vk.ru/?act=web_token` (body: `version=5.289&app_id=7879029&access_token=`,
     UA/Origin/Referer/Cookie) → `{"data":{"access_token":"vk1.a....","expires":<ts>,"user_id":"..."}}`;
  3. `POST/GET https://web.api.vk.ru/method/<метод>?client_id=7879029` с `access_token` → `{"response":{...}}`.
- Web_token переиспользуемый (~1ч, поле `expires`).
- Для web-канала Клиентский id: **7879029** (сайтовый клиент), версия API **5.289**.
- Набор методов web-канала ≠ старому API: нет `notifications.get` (`Unknown method passed`,
  error 3), но есть `notifications.getRedesign` (+`getCategories`/`getUnreadCounters`/`getSettings`).
  Такие расхождения закрываем тонкими конвертерами в родные модели (см. `patches/f14_*`).

## Рабочая структура (эта папка — ИСТОЧНИК ПРАВДЫ, НЕ /tmp)
```
orig/            — оригинальная Kate_133_11.apk (эталон, не трогать)
decode/          — декомпилированное рабочее дерево (apktool d)
patches/         — текстовые патчи правок (применяются скриптом, см. scripts/apply.sh)
scripts/         — вспомогательные скрипты (probe/grab/build/apply/install)
tools/           — apktool.jar и прочие инструменты
keys/            — debug.keystore (подпись артефактов)
dist/            — собранные и подписанные APK (бинарные артефакты)
docs/            — документация (планы, журнал, примеры ответов API)
README.md        — этот файл
PLAN.md          — живой план работ (обновлять по ходу)
HISTORY.md       — журнал: сделано / потеряно / восстановлено
```
ВАЖНО: `decode/`, `patches/`, `scripts/` и `dist/` защищены от потери:
- вся работа коммитится в git этой папки (см. `git log`);
- ничего важного НЕ хранится только в `/tmp`.
`/tmp` использовать лишь для разовых операций, сразу перенося результат в `decode/`/`dist/`.

## Зависимости окружения (восстановимо при переустановке)
- `tools/apktool.jar` (2.12.1), JDK 17+ (`java/javac/keytool/jarsigner`),
- `adb` — PATH `/tmp/platform-tools` (скачан когда-то; можно переустановить платформенной тулзой),
- устройство: Oppo Reno5 Lite (Android 13), `adb devices` — id `8L65GUJB85QO7D6S`.

## Как собрать с чистого листа (repro)
1. `scripts/decode.sh` — apktool d orig → decode/
2. `scripts/apply.sh` — применить все патчи из patches/ к decode/
3. `scripts/build.sh` — собрать + подписать → dist/kate_web-<дата>.apk
4. `scripts/install.sh` — установка на устройство

## Критичные для работы веб-канала условия
- В аккаунте приложения должна быть живая сессия WebView (логин через форму m.vk.ru).
  Удаление данных приложения стирает куки → нужен повторный вход.
- Если подпись APK сменилась → `adb install -r` не пройдёт (sig mismatch);
  требуется `adb uninstall` (теряет куки/аккаунт) и повторный логин.
  Потому debug.keystore сохранён здесь и НЕ пересоздаётся.