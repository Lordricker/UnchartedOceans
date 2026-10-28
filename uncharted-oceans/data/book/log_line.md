---
book: mechanics
chapter: log_line
title: Of the Log and Line
---

# Of the Log and Line

*How a master learns the speed of his ship.*

A ship has no milestones. The wind can be strong and the ship slow, or the wind fair and gentle and the ship quick, and a man cannot tell by looking at the sea. The only honest way is to measure the ship against the water, and this is done with the log.

## What you will need

- **The line**: a coil of rope lies on the poop deck by the stern rail. It runs up and over the rail and down the outside of the stern, to the log chip in the water. First comes a length of plain line, called the *stray line*. Then a **red block**, the mark. After the mark, a plain **wooden block** is seized to the line at every fixed distance.
- **The glass**: the sand glass that stands on the stern rail beside the line. It runs for **twenty-eight seconds**.

## How it is done

1. **Heave the log.** Take hold of the coil, and the line pays out over the rail. The chip stays where it is in the water while the ship sails on, so the line runs out at the speed of the ship. Heave it with the ship under way. A ship standing still pulls out no line at all.
2. **Let the stray line run.** The plain line goes first. It carries the chip clear of the ship's wake, where the water is still. Do not start counting yet.
3. **Watch for the red block.** When it goes over the rail, **turn the glass**, and no sooner or later.
4. **Count the wooden blocks** as they go over the rail, until the glass is out.
5. When the last sand falls the line is **held fast**. The blocks you counted are all the ship has made.

If you walk away from the coil, or take hold of it again, the line is hauled in. To take another reading, heave it again.

## What it tells you

The blocks are spaced to fit the glass, so **every block that goes over the rail is one knot of speed.** Count five, and the ship is making five knots. A faster ship runs out more line in the same twenty-eight seconds.

A knot is a measure of speed, and it is the one the whole trade is reckoned in. One knot is one nautical mile in the hour, which is **1.852 kilometres in the hour**. Once you know your speed, set it against the time you have sailed and you have the distance you have made. With your heading, that puts you on the chart.

## Knots into kilometres

The log gives knots, and the chart is in kilometres. **Kilometres in the hour = knots × 1.852.** To go back, divide by 1.852.

- 1 knot: 1.9 kilometres in the hour
- 2 knots: 3.7
- 3 knots: 5.6
- 4 knots: 7.4
- 5 knots: 9.3
- 6 knots: 11.1
- 7 knots: 13.0
- 8 knots: 14.8
- 9 knots: 16.7
- 10 knots: 18.5, about the most a brig will make

A ship making 5 knots goes 9.3 kilometres in an hour, and about 222 kilometres in a day and a night. The chart book (*Of the Chart and of Sleep*) shows how to turn this into hours for a given distance.

## Cautions

- **Turn the glass at the red block, not before it and not after.** A glass turned early gives too many blocks, and one turned late gives too few.
- A hasty count, a slack line, or a chip that drags along with the ship will all tell you a speed that is not true. Heave the log once more and compare the two.
- The log gives the ship's speed **through the water**. It will not tell you of a current that carries ship and water together. For that you want the stars, the coast, or a lead line.

---

### Notes for development (not shown to the player)

- The game never states a speed number for the log line; it is read off the blocks (see `scripts/ship_log_line.gd`).
- Real figures kept: block spacing 14.4 m (47 ft 3 in), glass 28 s, stray line about 12 fathoms (about 22 m) before the mark.
- The line is drawn running out slowly (0.3 m of model line per real 14.4 m) so a block goes over the rail in the same time it would at sea. The player counts timing, not the speed of the rope.
- Count rule: blocks sit half a spacing off the mark, so a count equals the speed rounded to the nearest knot.
- Controls: click the coil to heave the log (click again, or walk away, to haul it in); click the glass to turn it. The rope's path is the LogLine_P0 to P4 markers in the brig.
