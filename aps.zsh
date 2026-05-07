# aps — package list manager
# Add to ~/.zshrc. File lives at ~/.config/pkglist.
# Usage: aps [subcommand] [args]

aps() {
    local _APF="${XDG_CONFIG_HOME:-$HOME/.config}/pkglist"
    [[ ! -f "$_APF" ]] && touch "$_APF"

    # ── Helpers ──────────────────────────────────────────────────────────────

    # All non-comment, non-blank lines
    _aps_pkglines() {
        grep -Ev '^[[:space:]]*(#|$)' "$_APF"
    }

    # Parse raw package lines from stdin → TSV: name, desc, comment, temp_reason
    _aps_parse() {
        awk '{
            line = $0
            temp_reason = ""
            if (match(line, /@temp\([^)]+\)/)) {
                ts = substr(line, RSTART, RLENGTH)
                p  = index(ts, "(")
                temp_reason = substr(ts, p+1, length(ts)-p-1)
                sub(/ *@temp\([^)]+\)/, "", line)
            }
            n = split(line, f, / \| /)
            for (i=1; i<=3; i++) gsub(/^ +| +$/, "", f[i])
            print f[1] "\t" f[2] "\t" f[3] "\t" temp_reason
        }'
    }

    # Display parsed TSV lines as aligned columns
    # $1: "2col" (name+desc) | "3col" (name+desc+comment, default)
    _aps_display() {
        local mode="${1:-3col}"
        awk -F'\t' -v mode="$mode" '
        {
            col1 = ($4 != "") ? "~" $1 " (" $4 ")" : $1
            c1[NR]=col1; c2[NR]=$2; c3[NR]=$3
            if (length(col1) > w1) w1 = length(col1)
            if (length($2)   > w2) w2 = length($2)
        }
        END {
            w1 += 2; w2 += 2
            for (i=1; i<=NR; i++) {
                if (mode == "2col") {
                    printf "%-*s  %s\n", w1, c1[i], c2[i]
                } else {
                    if (c3[i] != "")
                        printf "%-*s  %-*s  %s\n", w1, c1[i], w2, c2[i], c3[i]
                    else
                        printf "%-*s  %s\n", w1, c1[i], c2[i]
                }
            }
        }'
    }

    # Convert parsed TSV lines back to raw file format
    _aps_format_raw() {
        awk -F'\t' '{
            out = $1 " | " $2
            if ($3 != "") out = out " | " $3
            if ($4 != "") out = out " @temp(" $4 ")"
            print out
        }'
    }

    # Write raw package lines (stdin) to file: preserve headers, sort, overwrite
    _aps_write() {
        local tmp
        tmp=$(mktemp)
        grep -E '^[[:space:]]*#' "$_APF" > "$tmp" 2>/dev/null || true
        sort -f >> "$tmp"
        mv "$tmp" "$_APF"
    }

    # True if package name already exists in file (case-insensitive)
    _aps_exists() {
        _aps_pkglines | _aps_parse | \
            awk -F'\t' -v n="${(L)1}" 'BEGIN{r=1} tolower($1)==n{r=0;exit} END{exit r}'
    }

    # Detect available package manager; prints "pacman" or "paru"
    _aps_pkgmgr() {
        if   command -v pacman &>/dev/null; then echo "pacman"
        elif command -v paru   &>/dev/null; then echo "paru"
        else echo "error: no supported package manager found" >&2; return 1
        fi
    }

    # Install a package via the detected package manager
    _aps_do_install() {
        local name="$1" mgr
        mgr=$(_aps_pkgmgr) || return 1
        if [[ "$mgr" == "pacman" ]]; then
            sudo pacman -S "$name"
        else
            paru "$name"
        fi
    }

    # Append a single raw line to the file and re-sort
    _aps_append() {
        { _aps_pkglines; echo "$1"; } | _aps_write
    }

    # Remove a package by name from the file
    _aps_drop() {
        _aps_pkglines | _aps_parse | \
            awk -F'\t' -v n="${(L)1}" 'tolower($1) != n' | \
            _aps_format_raw | _aps_write
    }

    # ── Dispatch ─────────────────────────────────────────────────────────────

    local cmd="${1:-}"
    shift 2>/dev/null

    case "$cmd" in

    # ── Display ──────────────────────────────────────────────────────────────

    "")
        _aps_pkglines | _aps_parse | _aps_display "2col"
        ;;

    list)
        _aps_pkglines | _aps_parse | _aps_display "3col"
        ;;

    names)
        _aps_pkglines | _aps_parse | awk -F'\t' '{print $1}' | sort -f
        ;;

    search)
        local pat="${1:-}"
        [[ -z "$pat" ]] && { echo "usage: aps search <pattern>" >&2; return 1; }
        _aps_pkglines | _aps_parse | \
            awk -F'\t' -v p="${(L)pat}" 'tolower($1)~p || tolower($2)~p' | \
            _aps_display "3col"
        ;;

    # ── Add (list only) ──────────────────────────────────────────────────────

    add)
        local name="${1:-}" desc="${2:-}" comment="${3:-}"
        [[ -z "$name" || -z "$desc" ]] && \
            { echo "usage: aps add <name> \"<desc>\" [\"<comment>\"]" >&2; return 1; }
        _aps_exists "$name" && { echo "error: '$name' already in list" >&2; return 1; }
        local raw="$name | $desc"
        [[ -n "$comment" ]] && raw+=" | $comment"
        _aps_append "$raw"
        echo "added to list: $name"
        ;;

    add-temp)
        local name="${1:-}" desc="${2:-}" reason="${3:-}" comment="${4:-}"
        [[ -z "$name" || -z "$desc" || -z "$reason" ]] && \
            { echo "usage: aps add-temp <name> \"<desc>\" \"<reason>\" [\"<comment>\"]" >&2; return 1; }
        _aps_exists "$name" && { echo "error: '$name' already in list" >&2; return 1; }
        reason="${reason// /-}"
        local raw="$name | $desc"
        [[ -n "$comment" ]] && raw+=" | $comment"
        raw+=" @temp($reason)"
        _aps_append "$raw"
        echo "added to list (temp): $name  reason: $reason"
        ;;

    # ── Install + add ────────────────────────────────────────────────────────

    install)
        local name="${1:-}" desc="${2:-}" comment="${3:-}"
        [[ -z "$name" || -z "$desc" ]] && \
            { echo "usage: aps install <name> \"<desc>\" [\"<comment>\"]" >&2; return 1; }
        _aps_exists "$name" && { echo "error: '$name' already in list" >&2; return 1; }
        _aps_do_install "$name" || \
            { echo "warning: install failed, not adding to list" >&2; return 1; }
        local raw="$name | $desc"
        [[ -n "$comment" ]] && raw+=" | $comment"
        _aps_append "$raw"
        echo "installed and added to list: $name"
        ;;

    install-temp)
        local name="${1:-}" desc="${2:-}" reason="${3:-}" comment="${4:-}"
        [[ -z "$name" || -z "$desc" || -z "$reason" ]] && \
            { echo "usage: aps install-temp <name> \"<desc>\" \"<reason>\" [\"<comment>\"]" >&2; return 1; }
        _aps_exists "$name" && { echo "error: '$name' already in list" >&2; return 1; }
        _aps_do_install "$name" || \
            { echo "warning: install failed, not adding to list" >&2; return 1; }
        reason="${reason// /-}"
        local raw="$name | $desc"
        [[ -n "$comment" ]] && raw+=" | $comment"
        raw+=" @temp($reason)"
        _aps_append "$raw"
        echo "installed and added to list (temp): $name  reason: $reason"
        ;;

    # ── Remove ───────────────────────────────────────────────────────────────

    remove)
        local name="${1:-}"
        [[ -z "$name" ]] && { echo "usage: aps remove <name>" >&2; return 1; }
        _aps_exists "$name" || { echo "error: '$name' not found in list" >&2; return 1; }
        printf "Remove %s from system with pacman -Rns? [y/N] " "$name"
        IFS= read -r ans < /dev/tty
        if [[ "${ans:l}" == "y" ]]; then
            sudo pacman -Rns "$name"
            _aps_drop "$name"
            echo "removed from list and system: $name"
        fi
        ;;

    remove-list)
        local name="${1:-}"
        [[ -z "$name" ]] && { echo "usage: aps remove-list <name>" >&2; return 1; }
        _aps_exists "$name" || { echo "error: '$name' not found in list" >&2; return 1; }
        _aps_drop "$name"
        echo "removed from list: $name"
        ;;

    # ── Temp ─────────────────────────────────────────────────────────────────

    temp)
        local sub="${1:-}"
        shift 2>/dev/null

        case "$sub" in

        "")
            _aps_pkglines | _aps_parse | awk -F'\t' '$4 != ""' | _aps_display "3col"
            ;;

        clean|clean-list)
            local reason="${1:-}"
            local filter
            if [[ -n "$reason" ]]; then
                reason="${reason// /-}"
                filter='$4 == r'
            else
                filter='$4 != ""'
            fi

            local matched
            matched=$(_aps_pkglines | _aps_parse | awk -F'\t' -v r="$reason" "$filter")

            if [[ -z "$matched" ]]; then
                echo "no matching temp packages"; return 0
            fi

            local count
            count=$(echo "$matched" | wc -l | tr -d ' ')
            echo "$matched" | _aps_display "3col"

            if [[ "$sub" == "clean" ]]; then
                printf "\nRemove %d packages from list and system? [y/N] " "$count"
            else
                printf "\nRemove %d packages from list? [y/N] " "$count"
            fi
            IFS= read -r ans < /dev/tty
            [[ "${ans:l}" != "y" ]] && return 0

            local pkg_names
            pkg_names=(${(f)"$(echo "$matched" | awk -F'\t' '{print $1}')"})

            if [[ "$sub" == "clean" ]]; then
                sudo pacman -Rns "${pkg_names[@]}" || \
                    { echo "warning: pacman failed, list not modified" >&2; return 1; }
            fi

            # Remove matched names from file
            local names_lc="${(j:,:)${(L)pkg_names[@]}}"
            _aps_pkglines | _aps_parse | awk -F'\t' -v names="$names_lc" '
                BEGIN { n=split(names,a,","); for(i=1;i<=n;i++) rm[a[i]]=1 }
                !(tolower($1) in rm)
            ' | _aps_format_raw | _aps_write

            echo "removed $count packages"
            ;;

        remove|remove-list)
            local name="${1:-}"
            [[ -z "$name" ]] && { echo "usage: aps temp $sub <name>" >&2; return 1; }

            local entry
            entry=$(_aps_pkglines | _aps_parse | \
                awk -F'\t' -v n="${(L)name}" 'tolower($1)==n')

            if [[ -z "$entry" ]]; then
                echo "error: '$name' not found in list" >&2; return 1
            fi

            local is_temp
            is_temp=$(echo "$entry" | awk -F'\t' '$4 != "" {print "yes"}')
            if [[ "$is_temp" != "yes" ]]; then
                echo "error: '$name' is not a temp package" >&2; return 1
            fi

            if [[ "$sub" == "remove" ]]; then
                printf "Remove %s from system with pacman -Rns? [y/N] " "$name"
                IFS= read -r ans < /dev/tty
                [[ "${ans:l}" != "y" ]] && return 0
                sudo pacman -Rns "$name"
                _aps_drop "$name"
                echo "removed from list and system: $name"
            else
                _aps_drop "$name"
                echo "removed from list: $name"
            fi
            ;;

        *)
            echo "error: unknown subcommand 'aps temp $sub'" >&2; return 1
            ;;
        esac
        ;;

    # ── Help ─────────────────────────────────────────────────────────────────

    help)
        cat <<'EOF'
aps — package list manager  (~/.config/pkglist)

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
  aps temp clean      [<reason>]                        remove temp + uninstall
  aps temp clean-list [<reason>]                        remove temp from list only
  aps temp remove      <name>                           remove single temp + uninstall
  aps temp remove-list <name>                           remove single temp from list only

  aps help                                              show this message
EOF
        ;;

    *)
        echo "error: unknown subcommand '$cmd'" >&2
        aps help >&2
        return 1
        ;;
    esac
}
