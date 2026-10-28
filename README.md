# Tanks — каркас проекта на pvsneslib

Заготовка репозитория для игры «Танки» на SNES: структура каталогов и сборка
на `pvsneslib` 4.6. Игровой код и ассеты добавляются отдельно — здесь описано,
куда именно их класть и как они превращаются в ROM.

```
make          # собрать tanks.sfc
make run      # собрать и запустить в эмуляторе
make help     # дерево проекта и список целей
```

## Требования

* `PVSNESLIB_HOME` указывает на распакованный pvsneslib:

  ```sh
  export PVSNESLIB_HOME=/path/to/pvsneslib
  ```

  Проверка: `echo $PVSNESLIB_HOME` и наличие
  `$PVSNESLIB_HOME/devkitsnes/snes_rules`.
* GNU Make. Всё остальное (компилятор `816-tcc`, `wlalink`, `gfx4snes`,
  `smconv`) берётся из `PVSNESLIB_HOME` — в PATH их добавлять не нужно.
* Эмулятор для `make run` (`mednafen`, `snes9x`, `bsnes`, `mesen`,
  `retroarch` — ищется в PATH), либо `make run EMULATOR=/путь/к/эмулятору`.

## Дерево проекта

```
Prototype/
├── Makefile               сборка: арт -> звук -> код -> ROM
├── README.md              этот файл
├── .gitignore             build/, ROM, объектники
│
├── src/                   ВЕСЬ ручной код (только .c/.h/.asm)
│   ├── main.c             точка входа: инициализация, главный цикл
│   ├── game/              логика: танк, снаряды, уровень, состояние матча
│   ├── engine/            обёртки над pvsneslib: ввод, OAM, звук, HUD
│   └── data/
│       └── assets.asm     один .incbin-манифест на все ассеты
│
├── res/                   ИСХОДНЫЕ ассеты (то, что вы редактируете)
│   ├── gfx/
│   │   ├── backgrounds/   *.png -> тайлы + карта + палитра
│   │   ├── sprites/       *.png -> тайлы спрайтов (16x16 кадры)
│   │   └── fonts/         *.png -> свой шрифт (опционально)
│   └── audio/
│       ├── sfx/           *.it — эффекты (конвертируются ПЕРВЫМИ)
│       └── music/         *.it — музыка
│
└── build/                 всё сгенерированное, можно удалять целиком
    ├── gfx/{backgrounds,sprites,fonts}/   .pic .map .pal .inc
    ├── soundbank.asm/.bnk/.h
    └── ...
```

Сейчас все каталоги пусты (в них лежит только `.gitkeep`): файлы из дерева
создаёте вы. Правила pvsneslib ищут `.c` и `.asm` только в `src/`, `src/*/`
и `src/*/*/` (три уровня) — глубже файл молча не соберётся.

## Как идёт сборка

```
res/gfx/*.png ──gfx4snes──> build/gfx/**  (.pic/.map/.pal/.inc)
res/audio/**/*.it ──smconv──> build/soundbank (.asm/.bnk/.h)
src/**/*.c ──816-tcc──> .ps ──816-opt──> .asm ──wla-65816──> .obj
src/**/*.asm ───────────────────────────────────────────> .obj
все .obj + lib/*.obj ──wlalink──> tanks.sfc (+ .sym, .symfull)
```

Объектники и промежуточные `.asm/.ps` появляются рядом с исходниками —
так устроен `snes_rules`, они перечислены в `.gitignore`.

## Первый запуск

Создайте `src/main.c` — минимальный рабочий пример:

```c
#include <snes.h>

int main(void)
{
    /* Встроенный шрифт: тайлы в 0x3000, карта в 0x6800, палитра 0 */
    consoleInitDefaultText(0);

    bgSetGfxPtr(0, 0x3000);
    bgSetMapPtr(0, 0x6800, SC_32x32);
    setMode(BG_MODE1, 0);
    bgSetDisable(1);
    bgSetDisable(2);

    consoleDrawText(9, 10, "TANKS PROTOTYPE");
    setScreenOn();

    while (1)
        WaitForVBlank();

    return 0;
}
```

Затем:

```sh
make            # tanks.sfc в корне проекта
make run        # или открыть tanks.sfc эмулятором вручную
```

## Графика

Требования к PNG:

* индексированный (palette) PNG, 256 цветов в файле;
* первые 16 записей палитры — ваши цвета (gfx4snes читает индекс пикселя как
  номер цвета SNES);
* фон — размеры кратны 8, спрайты — кратны 16.

| Каталог | Флаги gfx4snes | Что получится |
|---|---|---|
| `res/gfx/backgrounds/` | `-s 8 -o 16 -u 16 -e 0 -p -m` | тайлы, карта 32x32, палитра |
| `res/gfx/sprites/` | `-s 16 -o 16 -u 16 -p` | тайлы 16x16, палитра |
| `res/gfx/fonts/` | `-s 8 -o 2 -u 16 -e 1 -p -m -R` | шрифт 2 цвета, карта без склейки тайлов |

Флаги вынесены в переменные `GFX_BG_FLAGS`, `GFX_SPR_FLAGS`,
`GFX_FONT_FLAGS` — их можно переопределить в командной строке
(`make GFX_SPR_FLAGS="-s 32 ..."`).

Результат кладётся в `build/gfx/<каталог>/`: `.pic` — тайлы, `.map` — карта,
`.pal` — палитра, `.inc` — `extern`-объявления для C (каталог `build/` уже
добавлен в include path, так что работает `#include "gfx/backgrounds/arena.inc"`).
Учтите: в `.inc` карта объявлена как `unsigned short`, поэтому
`&arena_mapend - &arena_map` даст число тайлов, а не байт. Если нужен размер
в байтах для `bgInitMapSet`, объявляйте метки как `char` — как в примере ниже.

### Манифест ассетов

`src/data/assets.asm` — единственное место, где ассеты попадают в ROM:

```asm
.include "hdr.asm"

.section ".rodata1" superfree
arena_tiles:      .incbin "build/gfx/backgrounds/arena.pic"
arena_tiles_end:
arena_map:        .incbin "build/gfx/backgrounds/arena.map"
arena_map_end:
arena_pal:        .incbin "build/gfx/backgrounds/arena.pal"
arena_pal_end:
player_tiles:     .incbin "build/gfx/sprites/player.pic"
player_tiles_end:
player_pal:       .incbin "build/gfx/sprites/player.pal"
player_pal_end:
.ends
```

Пути в `.incbin` считаются от корня проекта (там запускается `make`), поэтому
префикс `build/gfx/...` обязателен.

В C-файле объявляйте метки и грузите данные:

```c
extern char arena_tiles, arena_tiles_end;
extern char arena_map, arena_map_end;
extern char arena_pal, arena_pal_end;

bgInitTileSet(0, &arena_tiles, &arena_pal, 0,
              &arena_tiles_end - &arena_tiles,
              &arena_pal_end - &arena_pal,
              BG_16COLORS, 0x0000);
bgInitMapSet(0, &arena_map, &arena_map_end - &arena_map, SC_32x32, 0x4000);
```

Адреса VRAM подбирайте под свой бюджет (см. ниже) — они должны совпадать с
`bgSetGfxPtr()` / `bgSetMapPtr()`.

Спрайты: кадры укладываются столбцом по 16x16 в одном PNG; в коде —
`oamInitGfxSet(&player_tiles, ..., &player_pal, ..., 0, 0x6000, OBJ_SIZE16_L32)`
и дальше `oamSet(...)` с номером кадра.

Шрифт можно не рисовать: `consoleInitDefaultText(0)` даёт встроенный.
Свой нужен только для нестандартного вида.

## Музыка и звуки

* Формат — `.it` (Impulse Tracker / OpenMPT), до 8 каналов (ограничение snesmod).
* `res/audio/sfx/` конвертируются **до** музыки: snesmod требует, чтобы эффекты
  шли первыми в банке. Makefile собирает их в таком порядке автоматически и
  включает режим `-f`, как только в `sfx/` есть хотя бы один файл.
* Один банк — примерно до 57 КиБ суммарно (вместе с драйвером), банк кладётся
  в ROM-банк 5 (`-b 5`).
* Результат: `build/soundbank.asm`, `build/soundbank.bnk`,
  `build/soundbank.h` с константами `MOD_<ИМЯ_ФАЙЛА>`.
* Линкер запускается с `-d` (выбрасывать неиспользуемые секции), поэтому банк
  попадёт в ROM только если на `SOUNDBANK__` действительно ссылаются — то есть
  если в коде есть `spcSetBank(&SOUNDBANK__)`.

Использование:

```c
#include "soundbank.h"          /* build/ уже в include path */

extern char SOUNDBANK__;

spcBoot();                       /* один раз при старте */
spcSetBank(&SOUNDBANK__);
spcLoad(MOD_BATTLE);             /* music/battle.it -> MOD_BATTLE */
spcPlay(0);

/* в главном цикле, каждый кадр: */
spcProcess();
```

Эффект: `spcLoadEffect(0)` для загрузки и `spcEffect(pitch, index, volpan)`
для воспроизведения.

Имена констант — имя файла в верхнем регистре: `battle.it` → `MOD_BATTLE`,
`shot.it` → `MOD_SHOT`.

## Картридж и отладка

| Переменная | По умолчанию | Смысл |
|---|---|---|
| `ROMNAME` | `tanks` | имя ROM-файла |
| `ROMTITLE` | `TANKS PROTOTYPE` | заголовок в SNES-хэдере (до 21 символа) |
| `ROMBANKS` | `8` | число банков: 8 = 256 КиБ (LoROM) |
| `HIROM` | `0` | `1` — HiROM (64 КиБ банки) |
| `FASTROM` | `0` | `1` — FastROM |
| `PVSNESLIB_DEBUG` | — | `1` — отладочная сборка с `.dbg` |

`ROMSIZE` в хэдере вычисляется из `ROMBANKS` автоматически, поэтому при
увеличении проекта достаточно поднять `ROMBANKS`:

```sh
make ROMBANKS=16            # 512 КиБ
make HIROM=1 FASTROM=1      # другой маппинг
```

## Цели Makefile

| Цель | Что делает |
|---|---|
| `all` (по умолчанию) | конвертирует арт и звук, компилирует, линкует ROM |
| `run` | `all`, затем запуск в эмуляторе |
| `verbose` | сборка без лог-обёртки, с полным выводом компилятора |
| `gfx` | только конвертация графики |
| `audio` | только сборка саундбанка |
| `clean` | удаляет `build/`, объектники, ROM, `hdr.asm`, `linkfile` |

Обычная сборка идёт через лог-обёртку из `snes_rules`: вывод пишется в
`tanks.log`, а в консоль попадает сводка предупреждений и ошибок. Если нужно
увидеть всё целиком — `make verbose`.

## VRAM: ориентиры

Стандартные адреса встроенного текста pvsneslib:

```
0x3000  тайлы шрифта (3 КиБ)
0x6800  карта текста 32x32 (2 КиБ)
```

Типовое распределение для этой игры (проверяйте под свои объёмы):

```
0x0000..0x2FFF  тайлы фона (16 цветов, 32 байта/тайл)
0x3000..0x3BFF  шрифт
0x4000..0x47FF  карта фона 32x32
0x6000..        тайлы спрайтов (окно OBJ)
0x6800..0x6FFF  карта текста
```

Окна не должны пересекаться: `bgInitTileSet/bgInitMapSet` и `oamInitGfxSet`
пишут по указанным адресам без проверок.

## Частые проблемы

| Симптом | Причина / решение |
|---|---|
| `PVSNESLIB_HOME is not set` | не экспортирована переменная окружения |
| `no C sources found under src/` | нет ни одного `.c`; начните с `src/main.c` |
| `gfx4snes: ... palette` | PNG не индексированный или цветов больше, чем `-u` |
| фон «рассыпается» | адреса VRAM в коде не совпадают с `bgSetGfxPtr`/`bgSetMapPtr` |
| `More than 8 channels` | в `.it` больше 8 каналов — сократите в трекере |
| `soundbank too big` | уменьшите модули или перейдите на HiROM/больше банков |
| музыка не играет | не вызван `spcProcess()` каждый кадр |
| музыка есть, ROM не вырос | нет ссылки на `SOUNDBANK__`, линкер выбросил секцию |
| изменил PNG — ROM не обновился | `make clean && make` (сброс stamp-файлов) |

## Соглашения

* `src/game` — правила игры (движение, стрельба, попадания, счёт).
* `src/engine` — тонкий слой над pvsneslib (ввод с фронтами, OAM, звук, HUD):
  игровая логика не должна знать про регистры SNES.
* `src/data` — только `.asm` с данными; никакой логики.
* Заголовки — рядом с `.c`, имена файлов в нижнем регистре.
* Не кладите `.asm` в корень: `snes_rules` собирает все `*.asm` из корня.
