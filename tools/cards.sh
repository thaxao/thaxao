#!/usr/bin/env bash
# Builds the profile cards (assets/pin-*.svg, assets/stats.svg,
# assets/langs.svg) from the GitHub API, so the README needs no third-party
# card service.  Needs gh (authenticated, GH_TOKEN in Actions) and jq.
#
#   tools/cards.sh [user] [repo...]
set -euo pipefail

user="${1:-thaxao}"; shift || true
pins=("$@"); [ ${#pins[@]} -gt 0 ] || pins=(Sunbringer-Astral Sunbringer-Meter)
out="$(dirname "$0")/../assets"
mkdir -p "$out"

# tokyonight
bg='#1a1b27' title='#70a5fd' text='#a9b1d6' icon='#bf91f3' muted='#565f89'
font="font-family:'Segoe UI',Ubuntu,'Helvetica Neue',sans-serif"

esc() { sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g' -e 's/"/\&quot;/g'; }

# Languages that say little about the work (notebooks, build glue).
hide_langs='^(Jupyter Notebook|Batchfile|Makefile|Dockerfile|Nix)$'

# Own, non-fork repositories, private ones included; fails unless the token
# is the user's (local runs, or CARDS_TOKEN in Actions).
own_repos() {
  gh api --paginate "user/repos?affiliation=owner&per_page=100" -q '.[] | select(.fork|not) | .full_name' 2>/dev/null
}

# Language colours for the common ones; anything else is grey.
lang_color() {
  case "$1" in
    Zig) echo '#ec915c' ;; C) echo '#555555' ;; 'C++') echo '#f34b7d' ;;
    Rust) echo '#dea584' ;; JavaScript) echo '#f1e05a' ;; TypeScript) echo '#3178c6' ;;
    Python) echo '#3572A5' ;; Shell) echo '#89e051' ;; PowerShell) echo '#5391fe' ;;
    HTML) echo '#e34c26' ;; CSS) echo '#563d7c' ;; Java) echo '#b07219' ;;
    Go) echo '#00ADD8' ;; Lua) echo '#000080' ;; 'C#') echo '#178600' ;;
    *) echo '#8b949e' ;;
  esac
}

# Breaks a description into at most two lines of about 50 characters.
wrap2() {
  local all; all="$(fold -s -w 50)"
  if [ "$(wc -l <<<"$all")" -gt 2 ]; then printf '%s\n' "$(sed -n 1p <<<"$all")" "$(sed -n 2p <<<"$all" | sed -E 's/ *$//')…"; else printf '%s\n' "$all"; fi
}

pin() {
  local repo="$1" json desc lang stars forks y=0 lines=()
  json="$(gh api "repos/$user/$repo")"
  desc="$(jq -r '.description // "No description."' <<<"$json")"
  lang="$(jq -r '.language // ""' <<<"$json")"
  stars="$(jq -r '.stargazers_count' <<<"$json")"
  forks="$(jq -r '.forks_count' <<<"$json")"
  mapfile -t lines < <(printf '%s\n' "$desc" | wrap2)
  {
    cat <<EOF
<svg xmlns="http://www.w3.org/2000/svg" width="400" height="120" viewBox="0 0 400 120" role="img" aria-label="$repo">
<rect x="0.5" y="0.5" width="399" height="119" rx="10" fill="$bg"/>
<g style="$font">
<path transform="translate(25,25)" fill="$icon" d="M2 2.5A2.5 2.5 0 014.5 0h8.75a.75.75 0 01.75.75v12.5a.75.75 0 01-.75.75h-2.5a.75.75 0 110-1.5h1.75v-2h-8a1 1 0 00-.714 1.7.75.75 0 01-1.072 1.05A2.495 2.495 0 012 11.5v-9zm10.5-1V9h-8c-.356 0-.694.074-1 .208V2.5a1 1 0 011-1h8z"/>
<text x="50" y="38" fill="$title" font-size="16" font-weight="600">$(printf '%s' "$repo" | esc)</text>
EOF
    for line in "${lines[@]}"; do
      printf '<text x="25" y="%d" fill="%s" font-size="13">%s</text>\n' $((64 + y * 18)) "$text" "$(printf '%s' "$line" | esc)"
      y=$((y + 1))
    done
    local x=25
    if [ -n "$lang" ]; then
      printf '<circle cx="%d" cy="101" r="6" fill="%s"/><text x="%d" y="105" fill="%s" font-size="12">%s</text>\n' $((x + 6)) "$(lang_color "$lang")" $((x + 18)) "$text" "$(printf '%s' "$lang" | esc)"
      x=$((x + 30 + ${#lang} * 7))
    fi
    printf '<text x="%d" y="105" fill="%s" font-size="12">&#9733; %s</text>\n' "$x" "$text" "$stars"
    printf '<text x="%d" y="105" fill="%s" font-size="12">&#10697; %s</text>\n' $((x + 50)) "$text" "$forks"
    printf '</g>\n</svg>\n'
  } > "$out/pin-$repo.svg"
}

stats() {
  local repos stars followers commits prs issues
  repos="$(gh api "users/$user" -q '.public_repos')"
  followers="$(gh api "users/$user" -q '.followers')"
  stars="$(gh api --paginate "users/$user/repos?per_page=100&type=owner" -q '.[] | select(.fork|not) | .stargazers_count' | awk '{s+=$1} END{print s+0}')"
  read -r commits prs issues < <(gh api graphql -f query='query($u:String!){user(login:$u){contributionsCollection{totalCommitContributions totalPullRequestContributions totalIssueContributions}}}' -F u="$user" \
    -q '.data.user.contributionsCollection | "\(.totalCommitContributions) \(.totalPullRequestContributions) \(.totalIssueContributions)"')
  local rows=("Commits (past year)|$commits" "Public repositories|$repos" "Stars earned|$stars" "Pull requests|$prs" "Issues|$issues" "Followers|$followers")
  {
    printf '<svg xmlns="http://www.w3.org/2000/svg" width="400" height="165" viewBox="0 0 400 165" role="img" aria-label="GitHub stats">\n'
    printf '<rect x="0.5" y="0.5" width="399" height="164" rx="10" fill="%s"/>\n<g style="%s">\n' "$bg" "$font"
    printf '<text x="25" y="35" fill="%s" font-size="18" font-weight="600">%s on GitHub</text>\n' "$title" "$(printf '%s' "$user" | esc)"
    local i=0
    for row in "${rows[@]}"; do
      printf '<circle cx="31" cy="%d" r="4" fill="%s"/><text x="45" y="%d" fill="%s" font-size="13">%s</text><text x="375" y="%d" fill="%s" font-size="13" font-weight="700" text-anchor="end">%s</text>\n' \
        $((56 + i * 19)) "$icon" $((60 + i * 19)) "$text" "${row%%|*}" $((60 + i * 19)) "$text" "${row#*|}"
      i=$((i + 1))
    done
    printf '</g>\n</svg>\n'
  } > "$out/stats.svg"
}

langs() {
  # Bytes per language over the user's own, non-fork repositories: one
  # request per repository, summed once.
  local totals list
  # Public repositories alone (the Actions token) misstate the mix; keep the
  # card from the last run that could see every repository.
  if ! list="$(own_repos)"; then
    [ -s "$out/langs.svg" ] && return
    list="$(gh api --paginate "users/$user/repos?per_page=100&type=owner" -q '.[] | select(.fork|not) | .full_name')"
  fi
  totals="$(printf '%s\n' "$list" | grep -v '^$' |
    while read -r full; do gh api "repos/$full/languages"; done |
    jq -s --arg hide "$hide_langs" 'map(to_entries) | add // [] | map(select(.key | test($hide) | not)) | group_by(.key) | map({k: .[0].key, v: (map(.value) | add)}) | sort_by(-.v) | .[:6]')"
  local sum; sum="$(jq '[.[].v] | add // 0' <<<"$totals")"
  {
    printf '<svg xmlns="http://www.w3.org/2000/svg" width="400" height="165" viewBox="0 0 400 165" role="img" aria-label="Top languages">\n'
    printf '<rect x="0.5" y="0.5" width="399" height="164" rx="10" fill="%s"/>\n<g style="%s">\n' "$bg" "$font"
    printf '<text x="25" y="35" fill="%s" font-size="18" font-weight="600">Most used languages</text>\n' "$title"
    if [ "$sum" -gt 0 ]; then
      # Stacked bar, then a two-column legend.
      local x=25 i=0
      printf '<clipPath id="bar"><rect x="25" y="50" width="350" height="8" rx="4"/></clipPath><g clip-path="url(#bar)">\n'
      while IFS=$'\t' read -r name bytes; do
        local w=$(( bytes * 350 / sum )); [ $w -lt 2 ] && w=2
        printf '<rect x="%d" y="50" width="%d" height="8" fill="%s"/>\n' "$x" "$w" "$(lang_color "$name")"
        x=$((x + w))
      done < <(jq -r '.[] | "\(.k)\t\(.v)"' <<<"$totals")
      printf '</g>\n'
      while IFS=$'\t' read -r name bytes; do
        local cx=$(( 25 + (i % 2) * 180 )) cy=$(( 82 + (i / 2) * 25 ))
        local pct; pct="$(awk -v b="$bytes" -v s="$sum" 'BEGIN{printf "%.1f", b*100/s}')"
        printf '<circle cx="%d" cy="%d" r="5" fill="%s"/><text x="%d" y="%d" fill="%s" font-size="12">%s %s%%</text>\n' \
          $((cx + 5)) "$cy" "$(lang_color "$name")" $((cx + 16)) $((cy + 4)) "$text" "$(printf '%s' "$name" | esc)" "$pct"
        i=$((i + 1))
      done < <(jq -r '.[] | "\(.k)\t\(.v)"' <<<"$totals")
    else
      printf '<text x="25" y="80" fill="%s" font-size="13">No language data yet.</text>\n' "$muted"
    fi
    printf '</g>\n</svg>\n'
  } > "$out/langs.svg"
}

for repo in "${pins[@]}"; do pin "$repo"; done
stats
langs
