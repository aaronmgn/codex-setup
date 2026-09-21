#!/usr/bin/env bash
# Install the bundled Codex defaults while retaining local customisation.
# This intentionally uses only Bash 3.2 and standard macOS/Linux utilities.

set -eu
set -f
LC_ALL=C
export LC_ALL

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd -P) || exit 1
TEMPLATES=$SCRIPT_DIR/codex
PRESETS=(explorer worker reviewer)
MANAGED_START='<!-- codex-setup:managed:start -->'
MANAGED_END='<!-- codex-setup:managed:end -->'
WORK_DIR=''

die() { printf '%s\n' "codex-setup: $*" >&2; exit 1; }
cleanup() { [ -z "$WORK_DIR" ] || rm -rf "$WORK_DIR"; }
trap cleanup EXIT
trap 'exit 1' HUP INT TERM

usage() {
  printf '%s\n' 'Usage: install.sh [--dry-run] [--codex-home PATH]'
  printf '%s\n' 'Install the shareable Codex setup without replacing unrelated settings.'
}

# Make an absolute, lexical path.  Do not resolve ancestors: /var is a symlink
# on macOS and is a valid ancestor for a chosen Codex home.
absolute_path() {
  case $1 in
    '~') input_path=$HOME ;;
    '~/'*) input_path=$HOME/${1#\~/} ;;
    /*) input_path=$1 ;;
    *) input_path=$PWD/$1 ;;
  esac
  path_parts=()
  old_ifs=$IFS; IFS=/
  set -- $input_path
  IFS=$old_ifs
  for part in "$@"; do
    case $part in ''|.) ;; ..) [ ${#path_parts[@]} -eq 0 ] || unset 'path_parts[${#path_parts[@]}-1]' ;; *) path_parts[${#path_parts[@]}]=$part ;; esac
  done
  result_path=/
  for part in "${path_parts[@]}"; do result_path=$result_path$part/; done
  result_path=${result_path%/}
  [ -n "$result_path" ] || result_path=/
  printf '%s\n' "$result_path"
}

regular_file() {
  # $1 path, $2 label.  The output is only a status; callers retain file bytes
  # in files, which avoids Bash's inability to store NUL bytes.
  if [ -L "$1" ]; then die "Unsafe $2: $1 is a symlink."; fi
  if [ -e "$1" ]; then
    [ -f "$1" ] || die "Unsafe $2: $1 is not a regular file."
    if IFS= read -r -d '' nul_probe < "$1"; then die "Cannot read $2: NUL bytes are not supported."; fi
    return 0
  fi
  return 1
}

parent_path() { case $1 in /) printf '/\n' ;; *) printf '%s\n' "${1%/*}" ;; esac; }

safe_directory() {
  safe_path=$1; safe_home=$2
  if [ -e "$safe_home" ] || [ -L "$safe_home" ]; then
    [ -L "$safe_home" ] && die "Unsafe target path: $safe_home is a symlink."
    [ -d "$safe_home" ] || die "Unsafe target path: $safe_home is not a directory."
    cursor=$safe_path
    while [ "$cursor" != "$safe_home" ]; do
      if [ -e "$cursor" ] || [ -L "$cursor" ]; then
        [ -L "$cursor" ] && die "Unsafe target path: $cursor is a symlink."
        [ -d "$cursor" ] || die "Unsafe target path: $cursor is not a directory."
      fi
      next_cursor=$(parent_path "$cursor")
      [ "$next_cursor" != "$cursor" ] || die "Unsafe target path: $safe_path is outside $safe_home."
      cursor=$next_cursor
    done
  else
    # Only inspect up to the first existing ancestor.  It is outside the
    # chosen home, so an OS alias such as /var must remain acceptable.
    cursor=$safe_home
    while ! { [ -e "$cursor" ] || [ -L "$cursor" ]; }; do
      next_cursor=$(parent_path "$cursor")
      [ "$next_cursor" != "$cursor" ] || die "Unsafe target path: $cursor does not have a directory ancestor."
      cursor=$next_cursor
    done
    [ -d "$cursor" ] || die "Unsafe target path: $cursor is not a directory."
  fi
}

new_temp() {
  temp_parent=${TMPDIR:-/tmp}
  WORK_DIR=$(mktemp -d "$temp_parent/codex-setup.XXXXXX") || die 'Cannot create temporary working directory.'
  chmod 700 "$WORK_DIR" || die "Cannot secure temporary directory: $WORK_DIR"
}

# Scanner output describes a single physical line.  Strings become spaces in
# SCAN_CODE, so punctuation inside them cannot look like TOML syntax.
SCAN_STATE=none SCAN_SQUARE=0 SCAN_CURLY=0
scan_line() {
  scan_input=$1; SCAN_CODE=''; SCAN_COMMENT_INDEX=-1
  SCAN_START_STATE=$SCAN_STATE; SCAN_START_SQUARE=$SCAN_SQUARE; SCAN_START_CURLY=$SCAN_CURLY
  scan_i=0; scan_len=${#scan_input}
  while [ "$scan_i" -lt "$scan_len" ]; do
    scan_ch=${scan_input:$scan_i:1}
    case $SCAN_STATE in
      basic)
        SCAN_CODE="$SCAN_CODE "
        if [ "$scan_ch" = '\' ]; then
          scan_i=$((scan_i + 1)); [ "$scan_i" -lt "$scan_len" ] && SCAN_CODE="$SCAN_CODE "
        elif [ "$scan_ch" = '"' ]; then SCAN_STATE=none; fi
        ;;
      literal)
        SCAN_CODE="$SCAN_CODE "
        [ "$scan_ch" = "'" ] && SCAN_STATE=none
        ;;
      mbasic)
        if [ "$scan_ch" = '\' ]; then
          SCAN_CODE="$SCAN_CODE "; scan_i=$((scan_i + 1)); [ "$scan_i" -lt "$scan_len" ] && SCAN_CODE="$SCAN_CODE "
        elif [ "${scan_input:$scan_i:3}" = '"""' ]; then
          # TOML permits up to two quotes immediately before a multiline
          # basic-string delimiter.  They are string content, not openers.
          scan_run=3
          while [ "${scan_input:$((scan_i + scan_run)):1}" = '"' ]; do scan_run=$((scan_run + 1)); done
          [ "$scan_run" -le 5 ] || die 'Cannot parse config.toml: invalid multiline basic-string quote run.'
          scan_j=0; while [ "$scan_j" -lt "$scan_run" ]; do SCAN_CODE="$SCAN_CODE "; scan_j=$((scan_j + 1)); done
          scan_i=$((scan_i + scan_run - 1)); SCAN_STATE=none
        else SCAN_CODE="$SCAN_CODE "; fi
        ;;
      mliteral)
        if [ "${scan_input:$scan_i:3}" = "'''" ]; then
          # The literal-string form has the same three-to-five quote rule.
          scan_run=3
          while [ "${scan_input:$((scan_i + scan_run)):1}" = "'" ]; do scan_run=$((scan_run + 1)); done
          [ "$scan_run" -le 5 ] || die 'Cannot parse config.toml: invalid multiline literal-string quote run.'
          scan_j=0; while [ "$scan_j" -lt "$scan_run" ]; do SCAN_CODE="$SCAN_CODE "; scan_j=$((scan_j + 1)); done
          scan_i=$((scan_i + scan_run - 1)); SCAN_STATE=none
        else SCAN_CODE="$SCAN_CODE "; fi
        ;;
      none)
        case $scan_ch in
          '#') SCAN_COMMENT_INDEX=$scan_i; break ;;
          '"')
            if [ "${scan_input:$scan_i:3}" = '"""' ]; then SCAN_CODE="$SCAN_CODE   "; scan_i=$((scan_i + 2)); SCAN_STATE=mbasic
            else SCAN_CODE="$SCAN_CODE "; SCAN_STATE=basic; fi
            ;;
          "'")
            if [ "${scan_input:$scan_i:3}" = "'''" ]; then SCAN_CODE="$SCAN_CODE   "; scan_i=$((scan_i + 2)); SCAN_STATE=mliteral
            else SCAN_CODE="$SCAN_CODE "; SCAN_STATE=literal; fi
            ;;
          '[') SCAN_SQUARE=$((SCAN_SQUARE + 1)); SCAN_CODE="$SCAN_CODE$scan_ch" ;;
          ']') SCAN_SQUARE=$((SCAN_SQUARE - 1)); [ "$SCAN_SQUARE" -ge 0 ] || die 'Cannot parse config.toml: unexpected ].'; SCAN_CODE="$SCAN_CODE$scan_ch" ;;
          '{') SCAN_CURLY=$((SCAN_CURLY + 1)); SCAN_CODE="$SCAN_CODE$scan_ch" ;;
          '}') SCAN_CURLY=$((SCAN_CURLY - 1)); [ "$SCAN_CURLY" -ge 0 ] || die 'Cannot parse config.toml: unexpected }.'; SCAN_CODE="$SCAN_CODE$scan_ch" ;;
          *) SCAN_CODE="$SCAN_CODE$scan_ch" ;;
        esac
        ;;
    esac
    scan_i=$((scan_i + 1))
  done
  SCAN_END_STATE=$SCAN_STATE; SCAN_END_SQUARE=$SCAN_SQUARE; SCAN_END_CURLY=$SCAN_CURLY
  if [ "$SCAN_STATE" = basic ] || [ "$SCAN_STATE" = literal ]; then die 'Cannot parse config.toml: unterminated basic or literal string.'; fi
}

trim() {
  trim_value=$1
  trim_value=${trim_value#"${trim_value%%[!$' \t\r']*}"}
  trim_value=${trim_value%"${trim_value##*[!$' \t\r']}"}
  printf '%s' "$trim_value"
}

key_path() {
  # Normalise a TOML key path into segments separated by ASCII unit separator.
  # Escaped quoted keys are deliberately rejected when they could be managed:
  # preserving a config is safer than guessing its semantic key.
  key_input=$(trim "$1"); key_result=''; key_piece=''; key_quote=none; key_i=0; key_len=${#key_input}; key_expect=1; key_bare=0
  while [ "$key_i" -lt "$key_len" ]; do
    key_ch=${key_input:$key_i:1}
    case $key_quote in
      basic)
        [ "$key_ch" = '\' ] && return 1
        if [ "$key_ch" = '"' ]; then key_quote=none; key_expect=0; key_bare=0; else key_piece=$key_piece$key_ch; fi
        ;;
      literal)
        if [ "$key_ch" = "'" ]; then key_quote=none; key_expect=0; key_bare=0; else key_piece=$key_piece$key_ch; fi
        ;;
      none)
        case $key_ch in
          ' '|$'\t') [ "$key_expect" -eq 1 ] || key_bare=0 ;;
          '"') [ "$key_expect" -eq 1 ] || return 1; key_quote=basic ;;
          "'") [ "$key_expect" -eq 1 ] || return 1; key_quote=literal ;;
          .) [ "$key_expect" -eq 0 ] || return 1; [ -n "$key_piece" ] || return 1; key_result=${key_result:+$key_result$'\037'}$key_piece; key_piece=''; key_expect=1; key_bare=0 ;;
          [A-Za-z0-9_-])
            if [ "$key_expect" -eq 1 ]; then key_piece=$key_piece$key_ch; key_expect=0; key_bare=1
            elif [ "$key_bare" -eq 1 ]; then key_piece=$key_piece$key_ch
            else return 1; fi
            ;;
          *) return 1 ;;
        esac
        ;;
    esac
    key_i=$((key_i + 1))
  done
  [ "$key_quote" = none ] && [ "$key_expect" -eq 0 ] && [ -n "$key_piece" ] || return 1
  printf '%s' "${key_result:+$key_result$'\037'}$key_piece"
}

top_eq() {
  eq_input=$1; eq_square=0; eq_curly=0; eq_i=0; eq_len=${#eq_input}
  while [ "$eq_i" -lt "$eq_len" ]; do
    eq_ch=${eq_input:$eq_i:1}
    case $eq_ch in '[') eq_square=$((eq_square + 1));; ']') eq_square=$((eq_square - 1));; '{') eq_curly=$((eq_curly + 1));; '}') eq_curly=$((eq_curly - 1));; '=') if [ "$eq_square" -eq 0 ] && [ "$eq_curly" -eq 0 ]; then printf '%s\n' "$eq_i"; return 0; fi;; esac
    eq_i=$((eq_i + 1))
  done
  return 1
}

table_header() {
  # Prints a type marker and normalised table path: a|path or t|path.
  header_code=$(trim "$1")
  TABLE_IS_ARRAY=0
  case $header_code in
    '[['*']]') TABLE_IS_ARRAY=1; header_inner=${header_code#\[\[}; header_inner=${header_inner%\]\]} ;;
    '['*']') header_inner=${header_code#\[}; header_inner=${header_inner%\]} ;;
    *) return 1 ;;
  esac
  header_path=$(key_path "$header_inner") || return 1
  if [ "$TABLE_IS_ARRAY" -eq 1 ]; then printf 'a|%s' "$header_path"; else printf 't|%s' "$header_path"; fi
}

simple_statement() {
  [ "$SCAN_START_STATE" = none ] && [ "$SCAN_END_STATE" = none ] && [ "$SCAN_START_SQUARE" -eq 0 ] && [ "$SCAN_END_SQUARE" -eq 0 ] && [ "$SCAN_START_CURLY" -eq 0 ] && [ "$SCAN_END_CURLY" -eq 0 ]
}

desired_model='' desired_reasoning='' desired_context='' desired_compact='' desired_threads=''
read_template_values() {
  template_file=$1; current_table=''; got_model=0; got_reasoning=0; got_context=0; got_compact=0; got_threads=0
  SCAN_STATE=none; SCAN_SQUARE=0; SCAN_CURLY=0
  while IFS= read -r template_line || [ -n "$template_line" ]; do
    template_parse=$template_line; template_parse=${template_parse%$'\r'}
    scan_line "$template_parse"
    if simple_statement; then
      raw_end=${#template_parse}; [ "$SCAN_COMMENT_INDEX" -ge 0 ] && raw_end=$SCAN_COMMENT_INDEX
      if header=$(table_header "${template_parse:0:$raw_end}"); then current_table=${header#*|}; continue; fi
      if eq_at=$(top_eq "$SCAN_CODE"); then
        key=$(key_path "${template_parse:0:$eq_at}") || die 'Cannot parse bundled config.toml: invalid key.'
        value=$(trim "${template_parse:$((eq_at + 1)):$((raw_end - eq_at - 1))}")
        [ -n "$value" ] || die 'Cannot parse bundled config.toml: empty managed value.'
        case "$current_table:$key" in
          :model) desired_model=$value; got_model=$((got_model + 1));;
          :model_reasoning_effort) desired_reasoning=$value; got_reasoning=$((got_reasoning + 1));;
          :model_context_window) desired_context=$value; got_context=$((got_context + 1));;
          :model_auto_compact_token_limit) desired_compact=$value; got_compact=$((got_compact + 1));;
          agents:max_concurrent_threads_per_session) desired_threads=$value; got_threads=$((got_threads + 1));;
        esac
      fi
    fi
  done < "$template_file"
  [ "$SCAN_STATE" = none ] && [ "$SCAN_SQUARE" -eq 0 ] && [ "$SCAN_CURLY" -eq 0 ] || die 'Cannot parse bundled config.toml: unterminated multiline value.'
  [ "$got_model" -eq 1 ] && [ "$got_reasoning" -eq 1 ] && [ "$got_context" -eq 1 ] && [ "$got_compact" -eq 1 ] && [ "$got_threads" -eq 1 ] || die 'Bundled config.toml must define each managed setting exactly once.'
}

emit_missing_root() {
  [ "$seen_model" -gt 0 ] || printf 'model = %s\n' "$desired_model" >> "$config_out"
  [ "$seen_reasoning" -gt 0 ] || printf 'model_reasoning_effort = %s\n' "$desired_reasoning" >> "$config_out"
  [ "$seen_context" -gt 0 ] || printf 'model_context_window = %s\n' "$desired_context" >> "$config_out"
  [ "$seen_compact" -gt 0 ] || printf 'model_auto_compact_token_limit = %s\n' "$desired_compact" >> "$config_out"
  if [ "$seen_threads" -eq 0 ] && [ "$agents_dotted_seen" -eq 1 ]; then
    printf 'agents.max_concurrent_threads_per_session = %s\n' "$desired_threads" >> "$config_out"
    seen_threads=1
  fi
}

reject_managed_shape_conflict() {
  # A dotted subpath beneath a scalar that this installer owns would become
  # invalid TOML when the scalar is updated.  Do not guess how to reshape it.
  case $1 in
    model$'\037'*|model_reasoning_effort$'\037'*|model_context_window$'\037'*|model_auto_compact_token_limit$'\037'*|agents$'\037max_concurrent_threads_per_session\037'*) die "Cannot parse destination config.toml: managed scalar $1 is used as a table or subpath.";;
  esac
}

emit_missing_agents() {
  if [ "$seen_threads" -eq 0 ]; then
    printf 'max_concurrent_threads_per_session = %s\n' "$desired_threads" >> "$config_out"
    seen_threads=1
  fi
}

rewrite_assignment() {
  # Preserve the spelling and indentation of the key plus any trailing comment.
  rewrite_line=$1; rewrite_eq=$2; rewrite_value=$3
  rewrite_before=${rewrite_line:0:$rewrite_eq}
  rewrite_after_start=$((rewrite_eq + 1))
  if [ "$SCAN_COMMENT_INDEX" -ge 0 ]; then rewrite_tail=${rewrite_line:$SCAN_COMMENT_INDEX}; else rewrite_tail=''; fi
  printf '%s= %s%s%s\n' "$rewrite_before" "$rewrite_value" "$rewrite_tail" "$LINE_CR" >> "$config_out"
}

split_inline_fields() {
  inline_input=$1; INLINE_FIELDS=(); inline_piece=''; inline_state=none; inline_sq=0; inline_cu=0; inline_i=0; inline_len=${#inline_input}
  while [ "$inline_i" -lt "$inline_len" ]; do
    inline_ch=${inline_input:$inline_i:1}
    case $inline_state in
      basic) inline_piece=$inline_piece$inline_ch; if [ "$inline_ch" = '\' ]; then inline_i=$((inline_i + 1)); [ "$inline_i" -lt "$inline_len" ] && inline_piece=$inline_piece${inline_input:$inline_i:1}; elif [ "$inline_ch" = '"' ]; then inline_state=none; fi ;;
      literal) inline_piece=$inline_piece$inline_ch; [ "$inline_ch" = "'" ] && inline_state=none ;;
      none)
        case $inline_ch in '"') inline_piece=$inline_piece$inline_ch; inline_state=basic;; "'") inline_piece=$inline_piece$inline_ch; inline_state=literal;; '[') inline_piece=$inline_piece$inline_ch; inline_sq=$((inline_sq + 1));; ']') inline_piece=$inline_piece$inline_ch; inline_sq=$((inline_sq - 1));; '{') inline_piece=$inline_piece$inline_ch; inline_cu=$((inline_cu + 1));; '}') inline_piece=$inline_piece$inline_ch; inline_cu=$((inline_cu - 1));; ',') if [ "$inline_sq" -eq 0 ] && [ "$inline_cu" -eq 0 ]; then INLINE_FIELDS[${#INLINE_FIELDS[@]}]=$inline_piece; inline_piece=''; else inline_piece=$inline_piece$inline_ch; fi;; *) inline_piece=$inline_piece$inline_ch;; esac ;;
    esac
    inline_i=$((inline_i + 1))
  done
  [ "$inline_state" = none ] && [ "$inline_sq" -eq 0 ] && [ "$inline_cu" -eq 0 ] || return 1
  [ -z "$(trim "$inline_piece")" ] || INLINE_FIELDS[${#INLINE_FIELDS[@]}]=$inline_piece
}

rewrite_inline_agents() {
  inline_line=$1; inline_eq=$2; inline_code=$3
  # An inline table must begin and end on this physical line.  The scanner has
  # already removed comments/strings, which makes these bounds unambiguous.
  inline_open=-1; inline_close=-1; inline_i=$((inline_eq + 1)); inline_len=${#inline_code}
  while [ "$inline_i" -lt "$inline_len" ]; do
    inline_ch=${inline_code:$inline_i:1}
    [ "$inline_ch" = '{' ] && { inline_open=$inline_i; break; }
    case $inline_ch in ' '|$'\t') ;; *) die 'Cannot parse destination config.toml: agents must be an inline table.';; esac
    inline_i=$((inline_i + 1))
  done
  [ "$inline_open" -ge 0 ] || die 'Cannot parse destination config.toml: agents must be an inline table.'
  inline_i=$((inline_open + 1)); inline_depth=1
  while [ "$inline_i" -lt "$inline_len" ]; do
    inline_ch=${inline_code:$inline_i:1}
    [ "$inline_ch" = '{' ] && inline_depth=$((inline_depth + 1))
    [ "$inline_ch" = '}' ] && inline_depth=$((inline_depth - 1))
    if [ "$inline_depth" -eq 0 ]; then inline_close=$inline_i; break; fi
    inline_i=$((inline_i + 1))
  done
  [ "$inline_close" -ge 0 ] || die 'Cannot parse destination config.toml: unterminated inline agents table.'
  inline_rest=$(trim "${inline_code:$((inline_close + 1))}")
  [ -z "$inline_rest" ] || die 'Cannot parse destination config.toml: ambiguous inline agents table.'
  inline_body=${inline_line:$((inline_open + 1)):$((inline_close - inline_open - 1))}
  split_inline_fields "$inline_body" || die 'Cannot parse destination config.toml: malformed inline agents table.'
  inline_seen=0; inline_new=''; inline_index=0
  while [ "$inline_index" -lt "${#INLINE_FIELDS[@]}" ]; do
    inline_field=${INLINE_FIELDS[$inline_index]}; scan_line "$inline_field"
    inline_field_eq=$(top_eq "$SCAN_CODE") || die 'Cannot parse destination config.toml: malformed inline agents field.'
    inline_key=$(key_path "${inline_field:0:$inline_field_eq}") || die 'Cannot parse destination config.toml: invalid inline agents key.'
    case $inline_key in max_concurrent_threads_per_session$'\037'*) die 'Cannot parse destination config.toml: managed agents setting is used as a table or subpath.';; esac
    if [ "$inline_key" = max_concurrent_threads_per_session ]; then
      inline_seen=$((inline_seen + 1)); [ "$inline_seen" -eq 1 ] || die 'Cannot parse destination config.toml: duplicate managed agents setting.'
      inline_field_before=${inline_field:0:$inline_field_eq}
      inline_field=$inline_field_before'= '$desired_threads
    fi
    if [ "$inline_index" -gt 0 ]; then inline_new=$inline_new,; fi
    inline_new=$inline_new$inline_field
    inline_index=$((inline_index + 1))
  done
  if [ "$inline_seen" -eq 0 ]; then
    if [ -n "$(trim "$inline_new")" ]; then inline_new=$inline_new', max_concurrent_threads_per_session = '$desired_threads
    else inline_new='max_concurrent_threads_per_session = '$desired_threads; fi
  fi
  seen_threads=$((seen_threads + 1)); [ "$seen_threads" -eq 1 ] || die 'Cannot parse destination config.toml: duplicate managed agents setting.'
  printf '%s{%s}%s%s\n' "${inline_line:0:$inline_open}" "$inline_new" "${inline_line:$((inline_close + 1))}" "$LINE_CR" >> "$config_out"
}

process_config() {
  config_source=$1; config_out=$2
  : > "$config_out" || die "Cannot prepare config update."
  current_table=''; root_inserted=0; agents_inserted=0; agents_table_seen=0; agents_dotted_seen=0; agents_inline_seen=0
  seen_model=0; seen_reasoning=0; seen_context=0; seen_compact=0; seen_threads=0
  SCAN_STATE=none; SCAN_SQUARE=0; SCAN_CURLY=0
  while IFS= read -r config_line || [ -n "$config_line" ]; do
    config_parse=$config_line; LINE_CR=''
    case $config_parse in *$'\r') config_parse=${config_parse%$'\r'}; LINE_CR=$'\r';; esac
    scan_line "$config_parse"
    raw_end=${#config_parse}; [ "$SCAN_COMMENT_INDEX" -ge 0 ] && raw_end=$SCAN_COMMENT_INDEX
    header_candidate=$(trim "${config_parse:0:$raw_end}")
    if simple_statement && header=$(table_header "$header_candidate"); then
      header_kind=${header%%|*}; header=${header#*|}
      if [ "$header_kind" = a ] && [ "$header" = agents ]; then die 'Cannot parse destination config.toml: agents cannot be an array table.'; fi
      [ "$header" != agents$'\037max_concurrent_threads_per_session' ] || die 'Cannot parse destination config.toml: managed agents scalar is used as a table.'
      reject_managed_shape_conflict "$header"
      case $header in model|model_reasoning_effort|model_context_window|model_auto_compact_token_limit) die "Cannot parse destination config.toml: managed scalar $header is used as a table.";; esac
      if [ "$root_inserted" -eq 0 ]; then emit_missing_root; root_inserted=1; fi
      if [ "$current_table" = agents ] && [ "$agents_inserted" -eq 0 ]; then emit_missing_agents; agents_inserted=1; fi
      current_table=$header
      [ "$current_table" = agents ] && agents_table_seen=1
      printf '%s\n' "$config_line" >> "$config_out"
      continue
    fi
    if simple_statement; then case $header_candidate in \[* ) die 'Cannot parse destination config.toml: invalid table header.';; esac; fi
    if eq_at=$(top_eq "$SCAN_CODE"); then
      key=$(key_path "${config_parse:0:$eq_at}") || die 'Cannot parse destination config.toml: invalid key.'
      [ -n "$current_table" ] || reject_managed_shape_conflict "$key"
      if [ "$current_table" = agents ]; then
        case $key in max_concurrent_threads_per_session$'\037'*) die 'Cannot parse destination config.toml: managed agents scalar is used as a subpath.';; esac
      fi
      case "$current_table:$key" in :agents$'\037'*) agents_dotted_seen=1; [ "$agents_inline_seen" -eq 0 ] || die 'Cannot parse destination config.toml: ambiguous agents table shape.';; esac
      if ! simple_statement; then
        case "$current_table:$key" in
          :model|:model_reasoning_effort|:model_context_window|:model_auto_compact_token_limit|agents:max_concurrent_threads_per_session|:$'agents\037max_concurrent_threads_per_session') die "Cannot parse destination config.toml: managed setting $key must use a single-line value.";;
        esac
        printf '%s\n' "$config_line" >> "$config_out"; continue
      fi
      case "$current_table:$key" in
        :model) seen_model=$((seen_model + 1)); [ "$seen_model" -eq 1 ] || die 'Cannot parse destination config.toml: duplicate managed setting model.'; rewrite_assignment "$config_parse" "$eq_at" "$desired_model"; continue;;
        :model_reasoning_effort) seen_reasoning=$((seen_reasoning + 1)); [ "$seen_reasoning" -eq 1 ] || die 'Cannot parse destination config.toml: duplicate managed setting model_reasoning_effort.'; rewrite_assignment "$config_parse" "$eq_at" "$desired_reasoning"; continue;;
        :model_context_window) seen_context=$((seen_context + 1)); [ "$seen_context" -eq 1 ] || die 'Cannot parse destination config.toml: duplicate managed setting model_context_window.'; rewrite_assignment "$config_parse" "$eq_at" "$desired_context"; continue;;
        :model_auto_compact_token_limit) seen_compact=$((seen_compact + 1)); [ "$seen_compact" -eq 1 ] || die 'Cannot parse destination config.toml: duplicate managed setting model_auto_compact_token_limit.'; rewrite_assignment "$config_parse" "$eq_at" "$desired_compact"; continue;;
        agents:max_concurrent_threads_per_session) seen_threads=$((seen_threads + 1)); [ "$seen_threads" -eq 1 ] || die 'Cannot parse destination config.toml: duplicate managed agents setting.'; rewrite_assignment "$config_parse" "$eq_at" "$desired_threads"; continue;;
        :$'agents\037max_concurrent_threads_per_session') seen_threads=$((seen_threads + 1)); [ "$seen_threads" -eq 1 ] || die 'Cannot parse destination config.toml: duplicate managed agents setting.'; rewrite_assignment "$config_parse" "$eq_at" "$desired_threads"; continue;;
        :agents) [ "$agents_dotted_seen" -eq 0 ] || die 'Cannot parse destination config.toml: ambiguous agents table shape.'; agents_inline_seen=1; rewrite_inline_agents "$config_parse" "$eq_at" "$SCAN_CODE"; continue;;
      esac
    fi
    printf '%s\n' "$config_line" >> "$config_out"
  done < "$config_source"
  [ "$SCAN_STATE" = none ] && [ "$SCAN_SQUARE" -eq 0 ] && [ "$SCAN_CURLY" -eq 0 ] || die 'Cannot parse destination config.toml: unterminated multiline value.'
  if [ "$root_inserted" -eq 0 ]; then emit_missing_root; fi
  if [ "$current_table" = agents ] && [ "$agents_inserted" -eq 0 ]; then emit_missing_agents
  elif [ "$seen_threads" -eq 0 ]; then
    [ -s "$config_out" ] && printf '\n' >> "$config_out"
    printf '[agents]\n' >> "$config_out"
    emit_missing_agents
  fi
}

managed_agents() {
  agents_existing=$1; agents_out=$2; agents_template=$3
  agents_block=$(mktemp "$WORK_DIR/agents-block.XXXXXX") || die 'Cannot create temporary instructions file.'
  agent_template_lines=(); agent_last=-1; agent_i=0
  while IFS= read -r agent_template_line || [ -n "$agent_template_line" ]; do
    agent_template_lines[${#agent_template_lines[@]}]=$agent_template_line
    [ -z "$agent_template_line" ] || agent_last=$agent_i
    agent_i=$((agent_i + 1))
  done < "$agents_template"
  {
    printf '%s\n' "$MANAGED_START"
    agent_i=0; while [ "$agent_i" -le "$agent_last" ]; do printf '%s\n' "${agent_template_lines[$agent_i]}"; agent_i=$((agent_i + 1)); done
    printf '%s\n' "$MANAGED_END"
  } > "$agents_block"
  if [ ! -e "$agents_existing" ] && [ ! -L "$agents_existing" ]; then cp "$agents_block" "$agents_out"; return; fi
  if cmp -s "$agents_existing" "$agents_template"; then cp "$agents_block" "$agents_out"; return; fi
  agents_starts=0; agents_ends=0; agents_in=0
  : > "$agents_out"
  while IFS= read -r agents_line || [ -n "$agents_line" ]; do
    case $agents_line in
      *"$MANAGED_START"*) [ "$(trim "$agents_line")" = "$MANAGED_START" ] || die 'AGENTS.md has malformed codex-setup managed markers.'; agents_starts=$((agents_starts + 1));;
    esac
    case $agents_line in
      *"$MANAGED_END"*) [ "$(trim "$agents_line")" = "$MANAGED_END" ] || die 'AGENTS.md has malformed codex-setup managed markers.'; agents_ends=$((agents_ends + 1));;
    esac
  done < "$agents_existing"
  [ "$agents_starts" -eq "$agents_ends" ] && [ "$agents_starts" -le 1 ] || die 'AGENTS.md has malformed codex-setup managed markers.'
  if [ "$agents_starts" -eq 0 ]; then
    cp "$agents_existing" "$agents_out"
    [ -s "$agents_out" ] && printf '\n\n' >> "$agents_out"
    cat "$agents_block" >> "$agents_out"
    return
  fi
  while IFS= read -r agents_line || [ -n "$agents_line" ]; do
    case $agents_line in
      *"$MANAGED_START"*)
        [ "$agents_in" -eq 0 ] || die 'AGENTS.md has malformed codex-setup managed markers.'
        cat "$agents_block" >> "$agents_out"; agents_in=1;;
      *"$MANAGED_END"*)
        [ "$agents_in" -eq 1 ] || die 'AGENTS.md has malformed codex-setup managed markers.'
        agents_in=0;;
      *) [ "$agents_in" -eq 0 ] && printf '%s\n' "$agents_line" >> "$agents_out";;
    esac
  done < "$agents_existing"
  [ "$agents_in" -eq 0 ] || die 'AGENTS.md has malformed codex-setup managed markers.'
}

ensure_directory() {
  ensure_dir=$1; ensure_home=$2
  safe_directory "$ensure_dir" "$ensure_home"
  ( umask 077; mkdir -p "$ensure_dir" ) || die "Cannot create directory: $ensure_dir"
  safe_directory "$ensure_dir" "$ensure_home"
}

atomic_write() {
  write_path=$1; write_source=$2; write_home=$3
  write_parent=$(parent_path "$write_path")
  ensure_directory "$write_parent" "$write_home"
  regular_file "$write_path" 'destination' || true
  write_tmp=$(mktemp "$write_parent/.${write_path##*/}.XXXXXX") || die "Cannot create temporary file in $write_parent"
  chmod 600 "$write_tmp" || { rm -f "$write_tmp"; die "Cannot secure temporary file: $write_tmp"; }
  if ! cp "$write_source" "$write_tmp"; then rm -f "$write_tmp"; die "Cannot write $write_path"; fi
  chmod 600 "$write_tmp" || { rm -f "$write_tmp"; die "Cannot secure temporary file: $write_tmp"; }
  if [ -L "$write_path" ] || { [ -e "$write_path" ] && [ ! -f "$write_path" ]; }; then rm -f "$write_tmp"; die "Unsafe destination: $write_path is not a regular file."; fi
  mv -f "$write_tmp" "$write_path" || { rm -f "$write_tmp"; die "Cannot replace $write_path"; }
}

main() {
  dry_run=0; codex_home=''
  while [ $# -gt 0 ]; do
    case $1 in
      --dry-run) dry_run=1;;
      --codex-home) shift; [ $# -gt 0 ] || die '--codex-home needs a path.'; codex_home=$1;;
      --help|-h) usage; exit 0;;
      *) die "Unknown option: $1";;
    esac
    shift
  done
  [ -n "$codex_home" ] || codex_home=${CODEX_HOME:-$HOME/.codex}
  target=$(absolute_path "$codex_home")
  [ "$target" != / ] || die 'Refusing to use filesystem root as Codex home.'
  new_temp

  regular_file "$TEMPLATES/config.toml" 'bundled config' || die 'Missing bundled config.toml.'
  regular_file "$TEMPLATES/AGENTS.md" 'bundled AGENTS.md' || die 'Missing bundled AGENTS.md.'
  read_template_values "$TEMPLATES/config.toml"
  preset_index=0
  while [ "$preset_index" -lt "${#PRESETS[@]}" ]; do
    preset=${PRESETS[$preset_index]}
    regular_file "$TEMPLATES/agents/$preset.toml" "bundled $preset preset" || die "Missing bundled preset: $preset"
    preset_index=$((preset_index + 1))
  done

  # Full validation and planning occur before creating any part of the target.
  safe_directory "$target" "$target"
  for destination in "$target/config.toml" "$target/AGENTS.md" "$target/agents/explorer.toml" "$target/agents/worker.toml" "$target/agents/reviewer.toml"; do
    safe_directory "$(parent_path "$destination")" "$target"
    regular_file "$destination" 'destination' || true
  done
  config_old=$target/config.toml; config_new=$WORK_DIR/config.toml
  if [ -e "$config_old" ] || [ -L "$config_old" ]; then process_config "$config_old" "$config_new"; else process_config /dev/null "$config_new"; fi
  agents_old=$target/AGENTS.md; agents_new=$WORK_DIR/AGENTS.md
  managed_agents "$agents_old" "$agents_new" "$TEMPLATES/AGENTS.md"

  plan_paths=("$target/config.toml" "$target/AGENTS.md")
  plan_sources=("$config_new" "$agents_new")
  plan_old=("$config_old" "$agents_old")
  preset_index=0
  while [ "$preset_index" -lt "${#PRESETS[@]}" ]; do
    preset=${PRESETS[$preset_index]}; plan_paths[${#plan_paths[@]}]=$target/agents/$preset.toml; plan_sources[${#plan_sources[@]}]=$TEMPLATES/agents/$preset.toml; plan_old[${#plan_old[@]}]=$target/agents/$preset.toml
    preset_index=$((preset_index + 1))
  done
  changed_paths=(); changed_sources=(); changed_old=(); backup_needed=0
  plan_index=0
  while [ "$plan_index" -lt "${#plan_paths[@]}" ]; do
    p=${plan_paths[$plan_index]}; s=${plan_sources[$plan_index]}; o=${plan_old[$plan_index]}
    if ! { [ -e "$o" ] && cmp -s "$s" "$o"; }; then
      changed_paths[${#changed_paths[@]}]=$p; changed_sources[${#changed_sources[@]}]=$s; changed_old[${#changed_old[@]}]=$o
      [ -e "$o" ] && backup_needed=1
    fi
    plan_index=$((plan_index + 1))
  done
  if [ ${#changed_paths[@]} -eq 0 ]; then printf '%s\n' 'Codex setup is already up to date; no changes made.'; return; fi
  if [ "$backup_needed" -eq 1 ]; then
    backup_stamp=$(date -u +%Y%m%dT%H%M%SZ) || die 'Cannot generate backup timestamp.'
    backup=$target/backups/codex-setup/$backup_stamp; backup_number=1
    while [ -e "$backup" ] || [ -L "$backup" ]; do backup=$target/backups/codex-setup/$backup_stamp-$backup_number; backup_number=$((backup_number + 1)); done
    safe_directory "$(parent_path "$backup")" "$target"
  else backup=''; fi
  if [ "$dry_run" -eq 1 ]; then
    plan_index=0; while [ "$plan_index" -lt "${#changed_paths[@]}" ]; do [ -e "${changed_old[$plan_index]}" ] && action=update || action=create; printf 'Would %s %s\n' "$action" "${changed_paths[$plan_index]}"; plan_index=$((plan_index + 1)); done
    [ -z "$backup" ] || printf 'Would back up existing files to %s\n' "$backup"
    printf '%s\n' 'Dry run: no files were changed.'; return
  fi
  ensure_directory "$target" "$target"
  if [ -n "$backup" ]; then
    plan_index=0
    while [ "$plan_index" -lt "${#changed_paths[@]}" ]; do
      old=${changed_old[$plan_index]}
      if [ -e "$old" ]; then relative=${changed_paths[$plan_index]#"$target/"}; atomic_write "$backup/$relative" "$old" "$target"; fi
      plan_index=$((plan_index + 1))
    done
    printf 'Backed up existing files to %s\n' "$backup"
  fi
  plan_index=0
  while [ "$plan_index" -lt "${#changed_paths[@]}" ]; do
    old=${changed_old[$plan_index]}; atomic_write "${changed_paths[$plan_index]}" "${changed_sources[$plan_index]}" "$target"; [ -e "$old" ] && action=Updated || action=Created; printf '%s %s\n' "$action" "${changed_paths[$plan_index]}"; plan_index=$((plan_index + 1))
  done
}

main "$@"
