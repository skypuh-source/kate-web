#!/bin/sh
# патч f32 (производительность/ускорение): ранняя отмена загрузки картинок.
#
# Проблема: ImageLoader$PhotosLoader.run() для каждой PhotoToLoad вызывал load()
# (сеть + декод), и ТОЛЬКО ПОСЛЕ этого проверял imageViewReused() — нужен ли ещё
# результат какому-то ImageView. При быстром скролле ListView агрессивно переиспользует
# вьюхи: 5 потоков-загрузчиков тратили время на скачивание/декод картинок для уже
# уехавших вьюх, из-за чего видимые изображения грузились позже.
#
# Фикс: вызвать imageViewReused() ДО load(). Если вьюха уже переиспользована
# (перепривязана к другому url или ушла со экрана) — не качаем/не декодируем, сразу
# к следующей задаче. Освобождаем потоки для актуальных картинок.
#
# Безопасность: imageViews — synchronizedMap(WeakHashMap); все пути постановки в очередь
# (DisplayImage L849, список L1080, displayImage L1969) кладут imageViews[view]=key
# ПЕРЕД queuePhoto(), а photo.key == значению в map, поэтому ранняя проверка даёт тот же
# результат, что и отложенная. Раньше (отложенная) проверка остаётся как страховка.
K="$(dirname "$0")/../"
cd "$K" || exit 1
F=decode/smali/com/perm/kate/ImageLoader\$PhotosLoader.smali
python3 - "$F" <<'EOF'
import sys
f = sys.argv[1]
s = open(f).read()

old = """    .line 939
    invoke-virtual {v1}, Lcom/perm/kate/ImageLoader$PhotoToLoad;->load()V
"""

new = """    .line 939
    iget-object v0, p0, Lcom/perm/kate/ImageLoader$PhotosLoader;->this$0:Lcom/perm/kate/ImageLoader;

    invoke-virtual {v0, v1}, Lcom/perm/kate/ImageLoader;->imageViewReused(Lcom/perm/kate/ImageLoader$PhotoToLoad;)Z

    move-result v0

    if-nez v0, :cond_f32_skipload

    invoke-virtual {v1}, Lcom/perm/kate/ImageLoader$PhotoToLoad;->load()V

    :cond_f32_skipload
"""

if "cond_f32_skipload" in s:
    print("f32 PhotosLoader: уже применён")
    sys.exit(0)

assert old in s, "f32: якорь load() не найден"
assert s.count(old) == 1, "f32: якорь load() не уникален"

s = s.replace(old, new, 1)
open(f, "w").write(s)
print("f32 PhotosLoader.smali OK (imageViewReused проверяется ДО load — ранняя отмена)")
EOF
