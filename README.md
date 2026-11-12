# Multiplayer Minesweeper

I just want to do something with zig, and this seemed like a good project for it. 

### Game Idea

The idea is to make a multiplayer minesweeper game where many many players can play on the same board (up to 1000 teams), and you get points based on the "value" of the cells that you uncover. So something like a 0 might be worth 1 point, 1 is 2 points, etc and 8 is 1000 or something like that. There is only a finite number of points availble, so the game is zero sum and players have to rush to get the largest sum of points they can before the board is completely cleared out.

And of course you instantly loose if you hit a mine.

That is the long term goal, but we are still far from that.

### Implementation

Currently, I am working on the core game model. This consists of two main data structures. The first one is the model of the minesweeper board itself, usually called [`GameBoard`](src/game_board.zig) in the code. This holds the grid of cells, and a single method for revealing a cell. Note that the `GameBoard` model does not know anything about flags or users flagging. In my opinion, flagging is a purely cosmetic aid for the player, the only time it interacts with the `GameBoard` is during `revealCell` information about the flagged cells for the clicking player is passed in so that players cannot reveal cells that they have flagged.

Thus the flagged cells for each player (or team) are tracked in a seperate data structure, usually called [`FlagBitset`](src/flag_bitset.zig) in the code. This holds a bitset representing if the cell at the bit index is flagged or not, for that specific team. With this seperation, the core logic is not cluttlered with flag updates from multiple players, and for hundreeds of teams the bitset can hold all of their flags in very little memory.

The full game loop holds both of these variables, calling methods as it receives input from a [`GameIo`](src/game_io_interface.zig) implementation. The interface constraints of 'GameIo' are validated by the caller at compile time. Currently, there is only a [`TerminalGameIo`](src/terminal_game_io.zig) implementation, but there will soon be networked and hopefully gui ones as well.

### Build steps

Clone the repo, then run
```
zig build
```
in the root directory. You can also optionally pass the width, height, and number of mines for a board at compile time with the `-Dwidth`, `-Dheight`, and `-Dnum_mines` options.
