# schultetable.koplugin

A customizable Schulte Table and visual search training plugin for [KOReader](https://github.com/koreader/koreader), designed with e-ink displays in mind.

schultetable.koplugin provides several randomized visual search exercises, configurable difficulty and timing options, and per-game statistics.

## Features

- Four training layouts: Classic Schulte, Mosaic, Irregular Rectangles, and Free Scatter
- Table sizes: 9, 16, 25, 36, and 49 numbers
- Normal and Hard difficulty modes
- Auto-start timer or start timer on the first click
- Optional highlighting of number `1`
- Configurable Mosaic boundaries
- Multiple number font options
- Best-time tracking
- Game history with configuration details
- Randomized layouts for every game
- Designed for touch-based e-ink devices

## Training Modes

### Classic Schulte

The traditional Schulte Table. Numbers are randomly distributed in a regular square grid and must be found in ascending order.

| Numbers | Grid  |
|:--------|:------|
| 9       | 3 × 3 |
| 16      | 4 × 4 |
| 25      | 5 × 5 |
| 36      | 6 × 6 |
| 49      | 7 × 7 |

### Mosaic

Numbers are placed inside irregular polygonal cells. The layout changes every game.

Two outer boundary styles are available:

- **Irregular**: The outer edge of the mosaic is irregular.
- **Circle**: The mosaic is constrained to a circular area.

Number placement takes the shape of each cell into account to maintain spacing between the text and cell boundaries.

### Irregular Rectangles

The training area is divided into rectangles of different sizes, retaining some structure while removing the predictable regular grid.

### Free Scatter

Numbers are distributed freely across the training area without visible cells. Minimum spacing prevents numbers from overlapping or becoming excessively crowded.

## Difficulty

### Normal

After a number is found, it is replaced by a small marker.

### Hard

Found numbers remain visible and unchanged. You must keep track of your current position without relying on visual removal of completed numbers.

Normal and Hard results are tracked separately when calculating best times.

## Timer

### Auto Start

The timer begins as soon as the game starts, including the time required to locate `1`.

### Start on 1

The timer begins when `1` is correctly tapped.

Best times for the two timer modes are tracked separately.

## Highlight 1

The starting number can optionally be highlighted. When enabled, `1` is marked with an underline.

## Number Fonts

Available options include:

- KOReader UI font
- Sans-serif
- Serif
- Monospace

The selected font is also recorded in game history.

## Statistics

Open **Statistics: History** to review previous games.

Each completed game records the date and time, training mode, number count, completion time, mistakes, difficulty, timer mode, number font, Highlight 1 setting, and Mosaic boundary when applicable.

Best times are separated by relevant game configuration.

## Installation

Download or clone this repository.

The plugin directory should be named:

``` text
schultetable.koplugin
```

Copy it into KOReader's `plugins` directory:

``` text
koreader/
└── plugins/
    └── schultetable.koplugin/
```

Restart KOReader completely after installation. **Schulte Table** will appear in KOReader's Tools menu.

## Updating

Replace the existing `schultetable.koplugin` directory with the files from the newer version, then restart KOReader.

If you previously used an older version named `numbersearch.koplugin`, remove the old plugin directory to prevent duplicate menu entries.

## Usage

Open:

``` text
Tools → Schulte Table
```

Choose a training mode and number count, then find the numbers in ascending order:

``` text
1 → 2 → 3 → 4 → ... → N
```

A new randomized layout is generated for each game.

## Settings

Settings include difficulty, timer behavior, Highlight 1, number font, and Mosaic boundary style. Settings are remembered between sessions.

## E-Ink Design

Schulte Table is designed specifically for KOReader and e-ink displays. The interface avoids unnecessary animation and continuous timer redraws. Game timing is measured internally while minimizing screen refreshes during training.

## About Schulte Tables

A traditional Schulte Table consists of randomly arranged numbers placed in a regular grid. The user finds the numbers sequentially as quickly as possible.

Schulte Table for KOReader also includes several non-standard layouts intended to provide variations on the same sequential visual-search task.

Performance improvements in these exercises should primarily be interpreted as improvements on the task itself. Claims that Schulte Table practice broadly improves attention, reading speed, peripheral vision, or general cognitive performance should be treated cautiously.
