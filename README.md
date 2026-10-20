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
- `tools/adsdk/` — локальный резерв Android SDK (~480 МБ), в git **не хранится** и для сборки не требуется,
- `adb` — PATH `/tmp/platform-tools` (скачан когда-то; можно переустановить платформенной тулзой),
- устройство: Oppo Reno5 Lite (Android 13), `adb devices` — id `8L65GUJB85QO7D6S`.

## Как собрать с чистого листа (repro)
1. `scripts/decode.sh` — apktool d orig → decode/
2. `scripts/apply.sh` — применить все патчи из patches/ к decode/
3. `scripts/build.sh` — собрать + подписать → dist/kate_web-<дата>.apk
4. `scripts/install.sh` — установка на устройство

## Обновления через GitHub
- Релиз: `git tag v133.12 && git push origin v133.12` → GitHub Actions собирает APK,
  поднимает `versionCode` (627 + номер запуска), подписывает и публикует Release
  с `Kate.apk` и `version.json`.
- В приложении штатный `UpdateChecker` раз в ~2 дня (и по кнопке «Проверить обновления»
  в настройках) читает `releases/latest/download/version.json`; если `code` больше
  установленного — показывает уведомление, скачивает `Kate.apk` и предлагает установить.
- Android требует подтверждения установки; подпись должна остаться прежней, иначе
  обновление поверх установленного приложения не встанет.
- Первый переход на f43-сборку — вручную (сборки до неё ещё смотрят на `katemobile.ru`);
  начиная с неё обновления приходят штатно.

## Критичные для работы веб-канала условия
- В аккаунте приложения должна быть живая сессия WebView (логин через форму m.vk.ru).
  Удаление данных приложения стирает куки → нужен повторный вход.
- Если подпись APK сменилась → `adb install -r` не пройдёт (sig mismatch);
  требуется `adb uninstall` (теряет куки/аккаунт) и повторный логин.
  Потому debug.keystore сохранён здесь и НЕ пересоздаётся.

## Уведомления при закрытом приложении
Push-каналы VK для нас закрыты: web push (self-hosted endpoint) VK не доставляет,
нативный FCM — только в свои/известные проекты, а `account.registerDevice` режется флудом.
Поэтому уведомления держатся на **foreground-сервисе-якоре** `KeepAliveService` (патч
`f41_keepalive.sh`): пока он в foreground, система не убивает процесс, и родной LongPoll
Kate продолжает приносить сообщения (в т.ч. после свайпа из «недавних»).
Детали — `ARCHITECTURE.md` §6.1, `HISTORY.md` (2026-10-17), `patches/README.md` (f41).