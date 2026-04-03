#! /usr/bin/env nix
#! nix shell nixpkgs#nushell --command nu

# Lists all indexed worktrees with their jj workspace names and running status.
#
# Usage:
#   list.sh              # default output
#   list.sh --resolve    # also print the physical path (symlink target)

def main [--resolve (-r)] {

let index_root = $"($env.HOME)/.claude/workspaces"

if not ($index_root | path exists) {
    print -e "No indexed workspaces."
    exit 0
}

# Active Claude sessions: session file exists = session is running
let active_cwds = (
    glob $"($env.HOME)/.claude/sessions/*.json"
    | each { |f| open $f | get cwd }
)

# Find all symlinks with their targets, skip dead ones
let links = (
    glob $"($index_root)/**/*"
    | each { ls --long --directory $in }
    | flatten
    | where type == symlink and ($it.target | path exists)
    | sort-by name
    | each { |link|
        let label = ($link.name | str replace $"($index_root)/" "")
        { label: $label, target: $link.target }
    }
)

if ($links | is-empty) {
    print -e "No indexed workspaces."
    exit 0
}

# Find unique jj repo roots for all targets
def find_jj_root [path: string] {
    mut dir = ($path | str replace -r '/.claude/worktrees/.*' '')
    loop {
        if ($"($dir)/.jj" | path exists) { return $dir }
        let parent = ($dir | path dirname)
        if $parent == $dir { return null }
        $dir = $parent
    }
}

# Build a flat table of workspace name -> path across all jj roots
let jj_roots = (
    $links
    | each { |l| find_jj_root $l.target }
    | compact
    | uniq
)

let ws_map = (
    $jj_roots
    | each { |root|
        do { jj -R $root workspace list --template 'name ++ "\n"' } | complete | get stdout
        | lines
        | where { $in != "" }
        | each { |ws|
            let result = (do { jj -R $root workspace root --name $ws } | complete)
            if $result.exit_code == 0 {
                { name: $ws, path: ($result.stdout | str trim) }
            }
        }
        | compact
    }
    | flatten
)

# Format output
let max_label = ($links | each { $in.label | str length } | math max)
let label_width = [($max_label + 2) 40] | math max

$links | each { |entry|
    let ws_match = ($ws_map | where path == $entry.target)
    let ws = if ($ws_match | is-not-empty) { $"  \(($ws_match.0.name))" } else { "" }
    let state = if $entry.target in $active_cwds { "running" } else { "paused" }

    if $resolve {
        $"($entry.label | fill -a left -w $label_width)($ws | fill -a left -w 28)  [($state)]  ($entry.target)"
    } else {
        $"($entry.label | fill -a left -w $label_width)($ws | fill -a left -w 28)  [($state)]"
    }
} | str join "\n" | print

} # end main
