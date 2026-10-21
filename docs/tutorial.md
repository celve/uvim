# uvim tutorial

This tutorial takes you from installing uvim to editing with it, in about twenty minutes. You need a Mac with
macOS 14 or later, and no Vim experience. Each lesson teaches a few keys and has you try them in TextEdit; they
work the same way in the text fields of most Mac apps. If you know Vim already, read
[If you know Vim](#if-you-know-vim) first and skip the lessons you know.

## 1. Install uvim

1. Install it with [Homebrew](https://brew.sh):

   ```sh
   brew install --cask celve/tap/uvim
   ```

   Or download the [latest release](https://github.com/celve/uvim/releases/latest), unzip it, and move
   `uvim.app` to `/Applications` before you open it for the first time: uvim cannot update a copy run from
   Downloads.
2. Open uvim. It has no window: it lives in the menu bar as a square with a letter in it, and its menu is the
   whole app.
3. macOS asks to let uvim control this computer using accessibility features: choose **Open System Settings**
   and switch uvim on under **Accessibility**. That is the one permission uvim needs, to read and edit the
   field you type in. If the prompt is gone, **Accessibility: not granted** in uvim's menu opens the same list.
4. Within a few seconds the **!** leaves uvim's icon, and its menu reads `Input tap: running` and
   `Accessibility: granted`.

If macOS asks for **Input Monitoring** instead, as uvim 1.1.1 does, allow it. Then choose **Accessibility: not
granted** in uvim's menu, switch uvim on there, and choose **Quit uvim** and open uvim again.

**Start at Login** in the menu opens uvim whenever you log in. On its second launch uvim asks whether to check
for updates once a day.

## 2. Insert mode and Normal mode

Open TextEdit and make a new document (**New Document**, or ⌘N). uvim's icon shows the mode you are in:

| Icon | Mode |
|---|---|
| Outlined **i** | Insert mode: keys type, as they always have |
| Filled **n** | Normal mode: keys are commands |
| Filled **v** | Visual mode: keys are commands, and act on what is selected |
| Dashed square | uvim is not working where you are typing |
| Slashed square | **Vim Mode** is off in uvim's menu |

1. Click in the document. A text field starts in Insert mode, so the icon shows the outlined **i**. Type:

   ```text
   Hello from uvim
   ```

2. Press **Esc**. The icon shows the filled **n**, and a block cursor covers the last letter: you are in Normal
   mode, where letters are commands and type nothing.
3. Press `b` to move back to the start of the word: the cursor is on the u of `uvim`.
4. Press `x` to delete the letter under the cursor. The line reads `Hello from vim`.
5. Press `i` to go back to Insert mode, before the cursor, and type `u`. The line reads `Hello from uvim` again.
6. Press **Esc** to return to Normal mode.

In Normal mode a key uvim does not know beeps instead of typing, so a stray key never lands in your text.
**Esc** with no command half-typed goes on to the app, so a second Esc still closes a dialog or a popup.

## 3. Move around

From here on, each lesson starts from a short text. Copy it (on GitHub, the button at the top right of the box
copies it), click in your TextEdit document, and press ⌘A and then ⌘V to put it in place of what is there:
⌘ keys always go to the app, in any mode. If the icon shows **i**, press Esc.

```text
Pack the bags on Friday night.
Call the bank about the card.
Book the flights and the hotel.
```

1. Press `gg` to go to the first line. The cursor is on its first letter.
2. Press `w` twice to move two words on: the cursor is on `bags`. Press `e` to go to the end of the word, and
   `b` to go back to its start.
3. Press `j` to move down a line, onto `bank`, and `k` to move back up. `h` and `l` move left and right, and
   the arrow keys work too.
4. Press `0` to go to the start of the line, and `fF` to jump to the next F on it, the one in `Friday`.
5. Press `G` to go to the last line, and `2w` to move two words on, to `flights`.
6. Press `gg`, and then `2j` to move two lines down, to the last line again.

`$` goes to the end of the line. A number before a motion repeats it, and `f` takes any character: `f,` goes
to the next comma.

## 4. Delete

```text
Pack the the bags on Friday night.
This line is a mistake.
Calll the bank about the card.
```

1. Press `gg`, then `w` to move to the first `the`, and `dw` to delete it. The first line reads `Pack the bags
   on Friday night.`
2. Press `j` to move to the second line, and `dd` to delete the whole line.
3. The cursor is now on `Calll`. Press `fl` to jump to its first l, and `x` to delete it.

The text reads:

```text
Pack the bags on Friday night.
Call the bank about the card.
```

`d` is an operator: it waits for a motion and deletes what the motion moves over. `dw` deletes to the next
word, `de` to the end of this one, `d$` or `D` to the end of the line, and `dd` the whole line. A number
repeats it: `2dd` deletes two lines, `d2w` two words, and `3x` three characters.

## 5. Change

```text
Lunch is at noon on Tuesday.
The repurt is almost done.
```

1. Press `gg`, then `3w` to move to `noon`.
2. Press `ciw`, "change inner word": it deletes the word under the cursor, wherever the cursor is in it, and
   puts you in Insert mode. Type `one` and press Esc.
3. Press `fT` to jump to `Tuesday`, and `cw` to change it up to the end of the word. Type `Friday` and press
   Esc.
4. Press `j` and `0` to go to the start of the second line, `fu` to jump to the u of `repurt`, and `ro` to
   replace it with an o.
5. Press `fa` to jump to `almost`, and `C` to change everything to the end of the line. Type `ready.` and
   press Esc.

The text reads:

```text
Lunch is at one on Friday.
The report is ready.
```

`c` is an operator like `d` that leaves you in Insert mode: `cw`, `c$` or `C`, and `cc` for the whole line.
`ciw` and `diw` act on the word the cursor is in, and `caw` and `daw` take the space after it too.

## 6. Undo, redo and repeat

```text
This is is is a test.
```

1. Press `gg`, then `w` to move to the first `is`, and `dw` to delete it.
2. Press `.` to do it again: `.` repeats the last command that changed the text. The line reads
   `This is a test.`
3. Press `u` to undo the last change: the line reads `This is is a test.` Press ⌃R to redo it.

`u` and ⌃R press the app's own ⌘Z and ⇧⌘Z, so they undo and redo as the app's Edit menu does.

## 7. Insert text

```text
Shopping list
Milk
Bread
```

1. Press `gg`, then `A` to type at the end of the line. Type `:` and press Esc.
2. Press `G` to go to the last line, and `o` to open a new line below it. Type `Eggs` and press Esc.
3. Press `gg`, then `j` to move to `Milk`, and `O` to open a new line above it. Type `Apples` and press Esc.

The text reads:

```text
Shopping list:
Apples
Milk
Bread
Eggs
```

`i` types before the cursor and `a` after it, `I` at the start of the line and `A` at its end, and `o` and `O`
open a new line below or above.

## 8. Copy and paste

```text
Feed the cat.
Water the plants.
Lock the door.
```

1. Press `gg`, then `dd` to delete the first line, and `p` to put it back below the line the cursor is on:
   the first two lines have swapped. What you delete is kept for `p`, like what you copy.
2. Press `gg`, then `yy` to copy ("yank") the first line, `G` to go to the last line, and `p` to put the
   copy below it.

The text reads:

```text
Water the plants.
Feed the cat.
Lock the door.
Water the plants.
```

`y` is an operator too: `yw`, `yiw`, `y$`, and `yy` for the line. `p` puts after the cursor and `P` before it.
In a field like this one, uvim keeps what you yank to itself until it quits, so ⌘V still pastes what you last
copied with ⌘C, and so does `"+p`.

## 9. Search

```text
We met teh team at teh office,
and teh plan is ready.
```

1. Press `gg`, then type `/teh` and press ⏎. Nothing shows the search as you type it; at ⏎ the cursor jumps
   to the first `teh`.
2. Press `ciw`, type `the`, and press Esc.
3. Press `n` to jump to the next `teh`, and `.` to fix it the same way. Press `n` and `.` once more.

The text reads:

```text
We met the team at the office,
and the plan is ready.
```

`?` searches backward. `n` repeats the last search in its direction, and `N` in the other. A search matches
the case you type, and wraps around the end of the text.

## 10. Visual mode

```text
Send the final report to the whole team.
```

1. Press `gg`, then `2w` to move to `final`.
2. Press `vaw` to select the word and the space after it: the icon shows **v**. Press `d` to delete the
   selection.
3. Press `fw` to jump to `whole`, `viw` to select the word, and `c` to change it. Type `entire` and press Esc.

The text reads:

```text
Send the report to the entire team.
```

`v` starts a selection at the cursor and a motion moves its end; `d`, `c` or `y` then act on it, and Esc leaves
Visual mode. With a motion other than `iw` or `aw`, a selection can end one character short of Vim's, and `V`
selects characters, not lines.

## 11. Beyond TextEdit

What you have learned works in the text fields of most native Mac apps, where uvim reads and edits the text
directly. Elsewhere:

- **Chromium browsers and Electron apps**, such as Chrome, Dia and Linear, show uvim a page's fields only once
  their accessibility support is on, which an assistive app can switch on. In Chrome on a Mac where nothing
  has, a page's fields show the dashed square, and **Force** (below) is what works there. Where uvim does see
  a field but the field takes no edits, uvim runs the same commands by pressing keys, with no block cursor,
  and checks the field after each step. When the field does not answer as planned, it beeps and stops rather
  than edit the wrong text, and it learns what each kind of field supports. `o` and `O` paste their new line
  there, because ⏎ could send a message. See
  [Browsers and Electron apps](../README.md#browsers-and-electron-apps).
- **Terminals and code editors**, such as Terminal, Visual Studio Code and Xcode, start Off, and **password
  fields** are never uvim's.

The menu sets where uvim works:

- **Vim in _App_** chooses, for the app in front: **Auto**, where uvim works in its text fields; **Off**, where
  it leaves the app alone; or **Force**, for an app that shows uvim no text field: uvim then drives its front
  window by keys, without reading it.
- **Vim Mode** turns uvim off everywhere until you turn it back on, or uvim starts again.
- **Normal Mode Key** chooses ⌃[ instead of Esc, which leaves Esc to the apps. ⌃[ enters Normal mode
  whichever key you choose.

## 12. When uvim beeps

- **You typed a command uvim does not have.** It beeps and does nothing. After `:` or `q` it beeps, and the
  keys you type next run as Normal-mode commands.
- **The field did not answer as planned.** uvim stops the command there. In a browser or an Electron app, when
  something keeps failing in one kind of field, uvim switches it off for fields like that one and works
  another way; **Capabilities in _App_** shows what it switched off, and **Try Again** forgets it.
- **Nothing shows a half-typed command.** If keys seem to do the wrong thing, press Esc: it cancels a
  half-typed command, and so does a click.
- **The icon shows a dashed square in a text field**: click in the field. If the square stays dashed, check
  **Vim in _App_**. A Chromium browser or an Electron app may be keeping its pages from uvim
  ([Beyond TextEdit](#11-beyond-textedit)), and **Force** works there.

If something goes wrong that you can repeat, [report a bug](../README.md#reporting-a-bug).

## Where to go next

The README has the rest: [What works](../README.md#what-works) lists every command uvim has,
[Using it](../README.md#using-it) every menu row and which keys stay with the apps, and
[Privacy](../README.md#privacy) what uvim reads and records.

## If you know Vim

uvim is a Vim mode for the whole Mac, so a few things work differently from Vim:

- A field starts in Insert mode when you move into it, so typing works as on any Mac. Moving between the
  blocks of one document, as in Notion, keeps the mode.
- Esc in Normal mode, with nothing half-typed, goes to the app. If you press Esc out of habit, use ⌃[: uvim
  keeps it in Normal mode too.
- In Normal mode, apps keep every ⌘ and ⌥ combination and most ⌃ ones, so ⌃A, ⌃E and ⌃K work as in any Mac
  text field.
- `u` and ⌃R are the app's own undo and redo.
- Registers last until uvim quits, and a yank does not copy to the Mac clipboard; `"+p` pastes it.
- Nothing shows a half-typed command or a search as you type it.
- There are no `:` commands, macros or folds: `:` and `q` beep, and the keys after them run as Normal-mode
  commands.
- An operator does not take `gg`, `g_` or a search as its motion yet, and text objects other than words beep.
- A Visual selection can end one character short of Vim's, and `V` and ⌃V select characters.

[What works](../README.md#what-works) has the full list.
