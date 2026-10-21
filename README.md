# kate-web

Kate Mobile 133.11 с патчами web-канала VK.

## Состав

- `orig/Kate_133_11.apk` — исходный APK, не изменять.
- `patches/f*` — патчи, применяются по порядку.
- `scripts/decode.sh`, `scripts/apply.sh`, `scripts/build.sh` — сборка.
- `tools/apktool_2.12.1.jar` — apktool.
- `keys/debug.keystore` — ключ подписи; не пересоздавать, иначе обновления не установятся.
- `.github/workflows/release.yml` — сборка и публикация релизов по тегу `v*`.

## Сборка

Нужны JDK 17, `apktool`, `jarsigner`.

```sh
sh scripts/decode.sh
sh scripts/apply.sh
sh scripts/build.sh
```

Результат: `dist/kate_web-YYYY-MM-DD.apk`.

## Релиз

```sh
git tag v133.xx
git push origin v133.xx
```

GitHub Actions соберёт APK и опубликует `Kate.apk` и `version.json` в Release.
Подпись должна оставаться прежней, иначе APK не установится поверх предыдущей версии.

## Проверка приватности

`.github/workflows/privacy.yml` запускает `scripts/check_privacy.sh` на каждый push и PR.
