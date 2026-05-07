# aps

A Zsh function for tracking installed packages in a plain-text file. Useful for keeping a human-readable record of what you've installed and why, so you can reproduce your setup on a new machine or clean up packages you no longer need.

## Overview

`aps` manages a file at `~/.config/pkglist`. Each entry stores a package name, a short description, an optional comment, and an optional temporary marker. The file stays sorted alphabetically and is easy to read, diff, and version-control.

```
# my packages

bat            | file viewer      | like cat but better
btop           | system monitor                          @temp(try-out)
dust           | disk usage       | better than du, tree view
eza            | file lister      | replaces ls            @temp(ml-course)
mpv            | media player     | minimal, scriptable
ripgrep        | search tool
zoxide         | directory jump   | learns frequent paths
```

## Installation

Copy the function into your `.zshrc`, then reload:

```zsh
source ~/.zshrc
```

The file `~/.config/pkglist` is created automatically on first use.

## Usage

```
aps                                                   list all (name + description)
aps list                                              list all (name + description + comment)
aps names                                             package names only, one per line
aps search <pattern>                                  filter by name or description

aps add         <name> "<desc>" ["<comment>"]         add to list only
aps add-temp    <name> "<desc>" "<reason>" ["<cmt>"]  add as temp to list only
aps install     <name> "<desc>" ["<comment>"]         install + add to list
aps install-temp <name> "<desc>" "<reason>" ["<cmt>"] install + add as temp

aps remove      <name>                                remove from list + uninstall
aps remove-list <name>                                remove from list only

aps temp                                              list temp packages
aps temp clean      [<reason>]                        remove all temp + uninstall
aps temp clean-list [<reason>]                        remove all temp from list only
aps temp remove      <name>                           remove single temp + uninstall
aps temp remove-list <name>                           remove single temp from list only

aps help                                              show this message
```

## Examples

**Tracking packages you already have installed:**

```zsh
aps add bat "file viewer" "like cat but better"
aps add ripgrep "search tool"
```

**Installing a new package and recording it at the same time:**

```zsh
aps install zoxide "directory jump" "learns frequent paths"
```

**Trying something out temporarily:**

```zsh
aps install-temp btop "system monitor" "try-out"
```

Temp packages are displayed with a `~` prefix and their reason:

```
~btop (try-out)   system monitor
```

**Searching by name or description:**

```zsh
aps search mon     # matches btop via "system monitor"
aps search ed      # matches bat, eza, zoxide, ...
```

**Cleaning up temp packages after a course or project:**

```zsh
aps temp clean ml-course     # uninstall + remove from list
aps temp clean               # clean all temp packages
```

**Removing from list only (package stays installed):**

```zsh
aps remove-list eza
```

## File Format

```
<name>  |  <description>  [|  <comment>]  [@temp(<reason>)]
```

- Fields are separated by ` | ` (space-pipe-space)
- `@temp(<reason>)` is always the last token on the line
- Spaces in reasons are stored as dashes (`ml course` → `ml-course`)
- Lines starting with `#` are treated as headers — preserved at the top, never sorted
- The file is re-sorted alphabetically (case-insensitive) on every write

## Temporary packages

The `@temp` marker is useful for anything you install for a limited purpose — a tool for a specific project, a course, or just to try out. When you're done, `aps temp clean <reason>` uninstalls all packages with that tag in one shot.

```zsh
# Add several packages for a course
aps install-temp python-pytorch "ml framework" "dl-course"
aps install-temp jupyter "notebook interface" "dl-course"
aps install-temp tensorboard "training visualizer" "dl-course"

# Course is done — clean everything up
aps temp clean dl-course
```

## Package manager support

`aps` detects the available package manager at runtime:

1. `sudo pacman -S <name>` if pacman is available
2. `paru <name>` otherwise

If neither is found, the install subcommand exits with an error. `add` and `add-temp` never call a package manager — they only write to the list.

## Requirements

- Zsh
- `pacman` or `paru`
- Standard POSIX tools: `awk`, `grep`, `sort`
