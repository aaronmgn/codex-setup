#!/bin/bash
# Black-box tests for the portable Bash installer.  They deliberately use only
# Bash 3.2 features and standard macOS/Linux command-line utilities.

set -u

REPO=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
INSTALLER="$REPO/install.sh"
TEMPLATE_AGENTS="$REPO/codex/AGENTS.md"
TEST_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/codex-setup-tests.XXXXXX") || exit 1
PASS_COUNT=0
FAIL_COUNT=0

cleanup() {
    if [ "${KEEP_TEST_ROOT:-0}" = 1 ]; then
        printf 'Preserved test files: %s\n' "$TEST_ROOT" >&2
    else
        rm -rf "$TEST_ROOT"
    fi
}
trap cleanup EXIT HUP INT TERM

fail() {
    printf 'FAIL: %s\n' "$*" >&2
    return 1
}

pass() {
    printf 'PASS: %s\n' "$1"
    PASS_COUNT=$((PASS_COUNT + 1))
}

assert_file() {
    [ -f "$1" ] || fail "expected regular file: $1"
}

assert_missing() {
    [ ! -e "$1" ] && [ ! -L "$1" ] || fail "expected missing path: $1"
}

assert_contains() {
    grep -F -- "$2" "$1" >/dev/null 2>&1 || fail "expected $1 to contain: $2"
}

assert_not_contains() {
    if grep -F -- "$2" "$1" >/dev/null 2>&1; then
        fail "did not expect $1 to contain: $2"
        return 1
    fi
    return 0
}

assert_count() {
    count=$(grep -F -c -- "$2" "$1" 2>/dev/null || true)
    [ "$count" = "$3" ] || fail "expected $1 to contain $3 copies of $2, found $count"
}

assert_assignment() {
    # Values can be reformatted by the installer; check the setting's meaning,
    # while anchoring the match so comments and TOML strings are not accepted.
    grep -E "^[[:space:]]*\"?$2\"?[[:space:]]*=[[:space:]]*$3[[:space:]]*(#.*)?$" "$1" >/dev/null 2>&1 || \
        fail "expected assignment $2 = $3 in $1"
}

assert_mode() {
    # The first ten characters of ls -ld are portable across BSD and GNU ls.
    listing=$(LC_ALL=C ls -ld "$1") || return 1
    actual=${listing%% *}
    actual=${actual:0:10}
    [ "$actual" = "$2" ] || fail "expected mode $2 for $1, found $actual"
}

snapshot() {
    source=$1
    destination=$2
    mkdir -p "$destination" || return 1
    cp -R "$source" "$destination/home"
}

assert_snapshot() {
    diff -r "$1" "$2/home" >/dev/null 2>&1 || fail "unexpected changes under $1"
}

run_install() {
    target=$1
    shift
    /bin/bash "$INSTALLER" --codex-home "$target" "$@" >"$target.output" 2>"$target.error"
}

new_home() {
    name=$1
    printf '%s/%s' "$TEST_ROOT" "$name"
}

test_fresh_install() {
    home=$(new_home fresh)
    run_install "$home" || return 1

    assert_file "$home/config.toml" || return 1
    assert_assignment "$home/config.toml" model '"gpt-6-astra"' || return 1
    assert_assignment "$home/config.toml" model_context_window 1000000 || return 1
    assert_assignment "$home/config.toml" model_auto_compact_token_limit 900000 || return 1
    assert_assignment "$home/config.toml" max_concurrent_threads_per_session 10 || return 1
    assert_file "$home/AGENTS.md" || return 1
    assert_count "$home/AGENTS.md" '<!-- codex-setup:managed:start -->' 1 || return 1
    assert_count "$home/AGENTS.md" '<!-- codex-setup:managed:end -->' 1 || return 1
    assert_file "$home/agents/explorer.toml" || return 1
    assert_file "$home/agents/worker.toml" || return 1
    assert_file "$home/agents/reviewer.toml" || return 1
    assert_missing "$home/backups" || return 1
}

test_dry_run_never_writes() {
    missing=$(new_home dry-missing)
    run_install "$missing" --dry-run || return 1
    assert_missing "$missing" || return 1

    home=$(new_home dry-existing)
    mkdir -p "$home/agents"
    printf '%s\n' 'model = "old"' >"$home/config.toml"
    printf '%s\n' 'local instruction' >"$home/AGENTS.md"
    printf '%s\n' 'name = "local"' >"$home/agents/explorer.toml"
    snap=$(new_home dry-snapshot)
    snapshot "$home" "$snap" || return 1
    run_install "$home" --dry-run || return 1
    assert_snapshot "$home" "$snap" || return 1

    outside=$(new_home dry-outside)
    mkdir -p "$outside"
    ln -s "$outside" "$home/backups"
    if run_install "$home" --dry-run; then
        fail "dry run accepted symlinked backup directory"
        return 1
    fi
    assert_missing "$outside/config.toml" || return 1
}

test_merge_tricky_toml_preserves_user_text() {
    home=$(new_home tricky)
    mkdir -p "$home"
    printf '%s\n' \
        '# root comment must survive' \
        'provider = "personal-provider"' \
        'quoted."literal.key" = "keep this dotted key"' \
        'multiline_basic = """' \
        'model = "fake-model"' \
        '[agents]' \
        '"""' \
        "multiline_literal = '''" \
        'model_context_window = 7' \
        '[plugins.fake]' \
        "'''" \
        'items = [' \
        '  "array entry", # keep array comment' \
        '  "[agents]",' \
        ']' \
        'agents = { custom = "keep-inline", max_concurrent_threads_per_session = 1 }' \
        '[mcp_servers.local]' \
        'command = "local-tool"' \
        '[plugins."personal@market"]' \
        'enabled = true' >"$home/config.toml"
    sentinel="$TEST_ROOT/expanded-from-toml"
    printf 'shell_text = "$(touch %s)"\n' "$sentinel" >>"$home/config.toml"
    printf 'shell_ticks = "`touch %s`"\n' "$sentinel" >>"$home/config.toml"
    printf '%s\n' '# local instructions' 'preserve this sentence' "literal \$(touch $sentinel)" >"$home/AGENTS.md"
    mkdir -p "$home/agents"
    printf '%s\n' 'name = "personal"' 'model = "keep-me"' >"$home/agents/personal.toml"
    cp "$home/agents/personal.toml" "$TEST_ROOT/personal-agent-before"
    run_install "$home" || return 1

    assert_contains "$home/config.toml" '# root comment must survive' || return 1
    assert_contains "$home/config.toml" 'provider = "personal-provider"' || return 1
    assert_contains "$home/config.toml" 'quoted."literal.key" = "keep this dotted key"' || return 1
    assert_contains "$home/config.toml" 'model = "fake-model"' || return 1
    assert_contains "$home/config.toml" 'model_context_window = 7' || return 1
    assert_contains "$home/config.toml" 'command = "local-tool"' || return 1
    assert_contains "$home/config.toml" '[plugins."personal@market"]' || return 1
    assert_contains "$home/config.toml" 'custom = "keep-inline"' || return 1
    assert_missing "$sentinel" || return 1
    cmp -s "$TEST_ROOT/personal-agent-before" "$home/agents/personal.toml" || \
        { fail 'installer changed an unrelated agent preset'; return 1; }
    assert_assignment "$home/config.toml" model '"gpt-6-astra"' || return 1
    assert_assignment "$home/config.toml" model_context_window 1000000 || return 1
    assert_assignment "$home/config.toml" model_auto_compact_token_limit 900000 || return 1
    grep -E 'max_concurrent_threads_per_session[[:space:]]*=[[:space:]]*10' "$home/config.toml" >/dev/null 2>&1 || \
        { fail 'expected inline agents concurrency value to be updated'; return 1; }
}

test_agents_preserves_boundaries_and_normalizes_template() {
    home=$(new_home agents)
    mkdir -p "$home"
    printf '%s\n' 'prefix stays' '<!-- codex-setup:managed:start -->' 'old managed content' \
        '<!-- codex-setup:managed:end -->' 'suffix stays' >"$home/AGENTS.md"
    run_install "$home" || return 1
    assert_contains "$home/AGENTS.md" 'prefix stays' || return 1
    assert_contains "$home/AGENTS.md" 'suffix stays' || return 1
    assert_contains "$home/AGENTS.md" '# Global Codex instructions' || return 1
    assert_not_contains "$home/AGENTS.md" 'old managed content' || return 1
    assert_count "$home/AGENTS.md" '<!-- codex-setup:managed:start -->' 1 || return 1

    template_home=$(new_home agents-template)
    mkdir -p "$template_home"
    cp "$TEMPLATE_AGENTS" "$template_home/AGENTS.md"
    run_install "$template_home" || return 1
    assert_count "$template_home/AGENTS.md" '# Global Codex instructions' 1 || return 1
    assert_count "$template_home/AGENTS.md" '<!-- codex-setup:managed:start -->' 1 || return 1
}

test_merges_quoted_and_dotted_managed_keys() {
    home=$(new_home quoted-dotted)
    mkdir -p "$home"
    printf '%s\n' \
        '"model" = "old-model"' \
        '"model_reasoning_effort" = "low"' \
        '"model_context_window" = 42' \
        '"model_auto_compact_token_limit" = 43' \
        'agents.max_concurrent_threads_per_session = 1' \
        'agents.extra = "preserve-dotted-sibling"' >"$home/config.toml"
    run_install "$home" || return 1
    assert_not_contains "$home/config.toml" '"model" = "old-model"' || return 1
    assert_not_contains "$home/config.toml" '"model_context_window" = 42' || return 1
    assert_assignment "$home/config.toml" model '"gpt-6-astra"' || return 1
    assert_assignment "$home/config.toml" model_context_window 1000000 || return 1
    assert_assignment "$home/config.toml" model_auto_compact_token_limit 900000 || return 1
    assert_contains "$home/config.toml" 'agents.extra = "preserve-dotted-sibling"' || return 1
    grep -E '^[[:space:]]*agents[.]max_concurrent_threads_per_session[[:space:]]*=[[:space:]]*10' "$home/config.toml" >/dev/null 2>&1 || \
        { fail 'expected dotted agents concurrency value to be updated in place'; return 1; }
}

test_array_of_tables_does_not_capture_agents_setting() {
    home=$(new_home array-of-tables)
    mkdir -p "$home"
    printf '%s\n' \
        'model = "old"' \
        '[agents]' \
        'extra = true' \
        '[[mcp_servers.demo.env]]' \
        'name = "TOKEN"' \
        'value = "x"' >"$home/config.toml"
    snap=$(new_home array-of-tables-snapshot)
    snapshot "$home" "$snap" || return 1

    if run_install "$home"; then
        assert_contains "$home/config.toml" 'extra = true' || return 1
        assert_contains "$home/config.toml" '[[mcp_servers.demo.env]]' || return 1
        assert_contains "$home/config.toml" 'name = "TOKEN"' || return 1
        agents_section=$(sed -n '/^[[:space:]]*\[agents\][[:space:]]*$/,/^[[:space:]]*\[\[/p' "$home/config.toml")
        printf '%s\n' "$agents_section" | grep -E '^[[:space:]]*max_concurrent_threads_per_session[[:space:]]*=[[:space:]]*10' >/dev/null 2>&1 || \
            { fail 'agents concurrency setting was not kept in [agents] before the array table'; return 1; }
    else
        # A deliberately limited scanner may decline arrays of tables, but must
        # do so before creating backups or changing another target.
        assert_snapshot "$home" "$snap" || return 1
    fi
}

test_crlf_agents_header_keeps_root_and_agents_scopes() {
    home=$(new_home crlf-agents)
    mkdir -p "$home"
    printf 'model = "old"\r\n[agents]\r\nextra = "keep"\r\nmax_concurrent_threads_per_session = 2\r\n' >"$home/config.toml"
    run_install "$home" || return 1
    normalized=$(tr -d '\r' <"$home/config.toml")
    header_count=$(printf '%s\n' "$normalized" | grep -F -c '[agents]' || true)
    [ "$header_count" = 1 ] || { fail "expected one [agents] header after CRLF merge, found $header_count"; return 1; }
    before_agents=$(printf '%s\n' "$normalized" | sed -n '1,/^\[agents\]$/p')
    printf '%s\n' "$before_agents" | grep -E '^[[:space:]]*model[[:space:]]*=[[:space:]]*"gpt-6-astra"' >/dev/null 2>&1 || \
        { fail 'root model setting was placed under CRLF [agents] table'; return 1; }
    agents_section=$(printf '%s\n' "$normalized" | sed -n '/^\[agents\]$/,$p')
    printf '%s\n' "$agents_section" | grep -E '^[[:space:]]*max_concurrent_threads_per_session[[:space:]]*=[[:space:]]*10' >/dev/null 2>&1 || \
        { fail 'CRLF [agents] concurrency setting was not updated in the agents table'; return 1; }
    max_count=$(printf '%s\n' "$normalized" | grep -E -c '^[[:space:]]*max_concurrent_threads_per_session[[:space:]]*=' || true)
    [ "$max_count" = 1 ] || { fail "expected one CRLF concurrency setting, found $max_count"; return 1; }
    printf '%s\n' "$agents_section" | grep -F 'extra = "keep"' >/dev/null 2>&1 || \
        { fail 'CRLF agents sibling setting was not preserved'; return 1; }
}

test_agents_scope_variants() {
    home=$(new_home nonterminal-agents)
    mkdir -p "$home"
    printf '%s\n' \
        'model = "old"' \
        '[agents]' \
        'extra = true' \
        '[mcp_servers.demo]' \
        'command = "keep"' >"$home/config.toml"
    run_install "$home" || return 1
    header_count=$(grep -F -c '[agents]' "$home/config.toml" || true)
    [ "$header_count" = 1 ] || { fail "expected one nonterminal [agents] header, found $header_count"; return 1; }
    agents_section=$(sed -n '/^[[:space:]]*\[agents\][[:space:]]*$/,/^[[:space:]]*\[/p' "$home/config.toml")
    printf '%s\n' "$agents_section" | grep -E '^[[:space:]]*max_concurrent_threads_per_session[[:space:]]*=[[:space:]]*10' >/dev/null 2>&1 || \
        { fail 'nonterminal [agents] did not receive concurrency setting'; return 1; }
    assert_contains "$home/config.toml" 'command = "keep"' || return 1

    dotted_home=$(new_home dotted-only-agents)
    mkdir -p "$dotted_home"
    printf '%s\n' 'agents.extra = "keep-root-dotted"' >"$dotted_home/config.toml"
    run_install "$dotted_home" || return 1
    assert_contains "$dotted_home/config.toml" 'agents.extra = "keep-root-dotted"' || return 1
    header_count=$(grep -F -c '[agents]' "$dotted_home/config.toml" || true)
    [ "$header_count" = 0 ] || { fail 'dotted agents root gained an invalid [agents] header'; return 1; }
    grep -E '^[[:space:]]*agents[.]max_concurrent_threads_per_session[[:space:]]*=[[:space:]]*10' "$dotted_home/config.toml" >/dev/null 2>&1 || \
        { fail 'dotted agents root did not receive dotted concurrency setting'; return 1; }
}

test_rejects_managed_prefix_conflicts_and_escaped_headers() {
    for case_name in agents-scalar model-prefix context-prefix agents-thread-table agents-thread-subpath escaped-header; do
        home=$(new_home "conflict-$case_name")
        mkdir -p "$home"
        case "$case_name" in
            agents-scalar) printf '%s\n' 'agents = "not a table"' >"$home/config.toml" ;;
            model-prefix) printf '%s\n' 'model.child = "not a scalar"' >"$home/config.toml" ;;
            context-prefix) printf '%s\n' 'model_context_window.child = 1' >"$home/config.toml" ;;
            agents-thread-table) printf '%s\n' '[agents.max_concurrent_threads_per_session]' 'note = "custom"' >"$home/config.toml" ;;
            agents-thread-subpath) printf '%s\n' '[agents]' 'max_concurrent_threads_per_session.extra = 1' >"$home/config.toml" ;;
            escaped-header) printf '%s\n' 'model = "old"' '["un\u006bnown"]' 'item = "keep"' >"$home/config.toml" ;;
        esac
        printf '%s\n' 'instructions untouched' >"$home/AGENTS.md"
        snap=$(new_home "conflict-snapshot-$case_name")
        snapshot "$home" "$snap" || return 1
        if run_install "$home"; then
            fail "accepted unsafe config case $case_name"
            return 1
        fi
        assert_snapshot "$home" "$snap" || return 1
    done
}

test_preserves_multiline_quote_runs() {
    for case_name in basic literal; do
        home=$(new_home "quote-run-$case_name")
        mkdir -p "$home"
        case "$case_name" in
            basic) original='notes = """value""""' ;;
            literal) original="notes = '''value''''" ;;
        esac
        printf '%s\n' "$original" >"$home/config.toml"
        run_install "$home" || return 1
        assert_contains "$home/config.toml" "$original" || \
            { fail "did not preserve $case_name multiline quote run"; return 1; }
        assert_assignment "$home/config.toml" model '"gpt-6-astra"' || return 1
    done
}

test_multiline_managed_value_is_replaced_or_rejected_without_writes() {
    home=$(new_home multiline-managed)
    mkdir -p "$home"
    printf '%s\n' 'model = """' 'old multiline model value' '"""' >"$home/config.toml"
    snap=$(new_home multiline-managed-snapshot)
    snapshot "$home" "$snap" || return 1
    if run_install "$home"; then
        assert_assignment "$home/config.toml" model '"gpt-6-astra"' || return 1
        assert_not_contains "$home/config.toml" 'old multiline model value' || return 1
    else
        assert_snapshot "$home" "$snap" || return 1
    fi
}

test_rejects_bad_agents_markers_before_writes() {
    for case_name in start-only duplicate-start reversed; do
        home=$(new_home "markers-$case_name")
        mkdir -p "$home"
        case "$case_name" in
            start-only) printf '%s\n' 'before' '<!-- codex-setup:managed:start -->' 'unfinished' >"$home/AGENTS.md" ;;
            duplicate-start) printf '%s\n' '<!-- codex-setup:managed:start -->' '<!-- codex-setup:managed:start -->' '<!-- codex-setup:managed:end -->' >"$home/AGENTS.md" ;;
            reversed) printf '%s\n' '<!-- codex-setup:managed:end -->' '<!-- codex-setup:managed:start -->' >"$home/AGENTS.md" ;;
        esac
        printf '%s\n' 'model = "old"' >"$home/config.toml"
        snap=$(new_home "markers-snapshot-$case_name")
        snapshot "$home" "$snap" || return 1
        if run_install "$home"; then
            fail "accepted malformed marker case $case_name"
            return 1
        fi
        assert_snapshot "$home" "$snap" || return 1
    done
}

test_rejects_malformed_config_before_writes() {
    for case_name in unterminated-string unterminated-multiline unterminated-array; do
        home=$(new_home "malformed-$case_name")
        mkdir -p "$home"
        case "$case_name" in
            unterminated-string) printf '%s\n' 'model = "unterminated' >"$home/config.toml" ;;
            unterminated-multiline) printf '%s\n' 'notes = """' 'still open' >"$home/config.toml" ;;
            unterminated-array) printf '%s\n' 'items = [' '  "open"' >"$home/config.toml" ;;
        esac
        printf '%s\n' 'untouched instructions' >"$home/AGENTS.md"
        snap=$(new_home "malformed-snapshot-$case_name")
        snapshot "$home" "$snap" || return 1
        if run_install "$home"; then
            fail "accepted malformed config case $case_name"
            return 1
        fi
        assert_snapshot "$home" "$snap" || return 1
    done
}

test_backups_are_exact_private_and_idempotent() {
    home=$(new_home backups)
    mkdir -p "$home/agents"
    printf '# old comment\r\nmodel = "old"\r\n' >"$home/config.toml"
    printf '# old instructions\r\n' >"$home/AGENTS.md"
    printf 'name = "explorer"\r\nmodel = "old"\r\n' >"$home/agents/explorer.toml"
    cp "$home/config.toml" "$TEST_ROOT/old-config"
    cp "$home/AGENTS.md" "$TEST_ROOT/old-agents"
    cp "$home/agents/explorer.toml" "$TEST_ROOT/old-explorer"
    run_install "$home" || return 1

    backup_root="$home/backups/codex-setup"
    set -- "$backup_root"/*
    if ! { [ "$#" -eq 1 ] && [ -d "$1" ]; }; then
        fail 'expected exactly one backup directory'
        return 1
    fi
    backup=$1
    cmp -s "$TEST_ROOT/old-config" "$backup/config.toml" || { fail 'config backup differs from source bytes'; return 1; }
    cmp -s "$TEST_ROOT/old-agents" "$backup/AGENTS.md" || { fail 'AGENTS backup differs from source bytes'; return 1; }
    cmp -s "$TEST_ROOT/old-explorer" "$backup/agents/explorer.toml" || { fail 'agent backup differs from source bytes'; return 1; }
    assert_mode "$backup" 'drwx------' || return 1
    assert_mode "$backup/config.toml" '-rw-------' || return 1

    snap=$(new_home backup-snapshot)
    snapshot "$home" "$snap" || return 1
    run_install "$home" || return 1
    assert_snapshot "$home" "$snap" || return 1
}

test_rejects_symlinks_and_nonregular_paths_without_escape() {
    home=$(new_home unsafe)
    outside=$(new_home outside)
    mkdir -p "$home" "$outside"
    printf '%s\n' 'outside stays' >"$outside/config.toml"
    printf '%s\n' 'local instructions stay' >"$home/AGENTS.md"
    ln -s "$outside/config.toml" "$home/config.toml"
    snap=$(new_home unsafe-snapshot)
    snapshot "$home" "$snap" || return 1
    if run_install "$home"; then
        fail 'accepted a symlink target'
        return 1
    fi
    assert_snapshot "$home" "$snap" || return 1
    assert_contains "$outside/config.toml" 'outside stays' || return 1

    rm "$home/config.toml"
    printf '%s\n' 'model = "old"' >"$home/config.toml"
    mkdir "$home/agents"
    mkdir "$home/agents/worker.toml"
    snap=$(new_home nonregular-snapshot)
    snapshot "$home" "$snap" || return 1
    if run_install "$home"; then
        fail 'accepted non-regular agent target'
        return 1
    fi
    assert_snapshot "$home" "$snap" || return 1

    rmdir "$home/agents/worker.toml"
    rmdir "$home/agents"
    mkdir -p "$home/agents"
    ln -s "$outside" "$home/backups"
    snap=$(new_home backup-link-snapshot)
    snapshot "$home" "$snap" || return 1
    if run_install "$home"; then
        fail 'accepted a symlink backup path'
        return 1
    fi
    assert_snapshot "$home" "$snap" || return 1
    assert_missing "$outside/AGENTS.md" || return 1

    rm "$home/backups"
    mkdir "$home/backups"
    printf '%s\n' 'not a directory' >"$home/backups/codex-setup"
    snap=$(new_home backup-file-snapshot)
    snapshot "$home" "$snap" || return 1
    if run_install "$home"; then
        fail 'accepted a non-directory backup path'
        return 1
    fi
    assert_snapshot "$home" "$snap" || return 1
}

test_environment_spaces_and_option_errors() {
    environment_home="$TEST_ROOT/env home"
    explicit_home="$TEST_ROOT/explicit home"
    CODEX_HOME="$environment_home" /bin/bash "$INSTALLER" >"$TEST_ROOT/env.out" 2>"$TEST_ROOT/env.err" || return 1
    assert_file "$environment_home/config.toml" || return 1
    CODEX_HOME="$environment_home" /bin/bash "$INSTALLER" --codex-home "$explicit_home" >"$TEST_ROOT/explicit.out" 2>"$TEST_ROOT/explicit.err" || return 1
    assert_file "$explicit_home/config.toml" || return 1

    option_home=$(new_home missing-option)
    CODEX_HOME="$option_home" /bin/bash "$INSTALLER" --codex-home >"$TEST_ROOT/missing.out" 2>"$TEST_ROOT/missing.err" && {
        fail 'missing --codex-home value succeeded'
        return 1
    }
    assert_missing "$option_home" || return 1
}

run_test() {
    name=$1
    if "$name"; then
        pass "$name"
    else
        printf 'FAIL: %s returned nonzero\n' "$name" >&2
        FAIL_COUNT=$((FAIL_COUNT + 1))
        printf '  stdout/stderr may be under %s\n' "$TEST_ROOT" >&2
    fi
}

[ -f "$INSTALLER" ] || { printf 'missing installer: %s\n' "$INSTALLER" >&2; exit 1; }

run_test test_fresh_install
run_test test_dry_run_never_writes
run_test test_merge_tricky_toml_preserves_user_text
run_test test_agents_preserves_boundaries_and_normalizes_template
run_test test_merges_quoted_and_dotted_managed_keys
run_test test_array_of_tables_does_not_capture_agents_setting
run_test test_crlf_agents_header_keeps_root_and_agents_scopes
run_test test_agents_scope_variants
run_test test_rejects_managed_prefix_conflicts_and_escaped_headers
run_test test_preserves_multiline_quote_runs
run_test test_multiline_managed_value_is_replaced_or_rejected_without_writes
run_test test_rejects_bad_agents_markers_before_writes
run_test test_rejects_malformed_config_before_writes
run_test test_backups_are_exact_private_and_idempotent
run_test test_rejects_symlinks_and_nonregular_paths_without_escape
run_test test_environment_spaces_and_option_errors

printf '%s passed; %s failed\n' "$PASS_COUNT" "$FAIL_COUNT"
[ "$FAIL_COUNT" -eq 0 ]
