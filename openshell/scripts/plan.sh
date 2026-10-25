#!/usr/bin/env bash
# Decide which OpenShell images to publish.
#
# GitHub cron cannot express "every 3 days". The schedule runs daily. It
# publishes a calver release when there is no openshell-YYYY.MM.DD.NN tag
# yet, when the newest tag is at least OPENSHELL_FORCE_AGE_DAYS old (30),
# or when that tag is at least OPENSHELL_MIN_AGE_DAYS old (3) and a release
# input has changed since the tag. Release inputs are files under
# openshell/, the root justfile, and the workflows that build the images.
# workflow_dispatch release does not use those gates.
#
# stdout is key=value lines for $GITHUB_OUTPUT. Diagnostics go to stderr.
set -euo pipefail

event=
publish_input=
sha=
files_path=
all_files=false

usage() {
  printf 'usage: plan.sh --event push|schedule|workflow_dispatch --sha SHA [--files PATH | --all-files] [--publish edge|release]\n' >&2
  exit 2
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --event)
      event=$2
      shift 2
      ;;
    --publish)
      publish_input=$2
      shift 2
      ;;
    --sha)
      sha=$2
      shift 2
      ;;
    --files)
      files_path=$2
      shift 2
      ;;
    --all-files)
      all_files=true
      shift
      ;;
    *)
      usage
      ;;
  esac
done

if [[ -z "$event" || -z "$sha" ]]; then
  usage
fi
if [[ ! "$sha" =~ ^[0-9a-f]{40}$ ]]; then
  printf 'sha must be 40 lowercase hex characters\n' >&2
  exit 2
fi

case "$event" in
  push | schedule | workflow_dispatch) ;;
  *)
    usage
    ;;
esac

now=${OPENSHELL_NOW:-$(date -u +%Y-%m-%d)}
if [[ ! "$now" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]]; then
  printf 'OPENSHELL_NOW must be YYYY-MM-DD\n' >&2
  exit 2
fi

read_tags() {
  if [[ -n "${OPENSHELL_TAGS_FILE:-}" ]]; then
    grep -E '^openshell-[0-9]{4}\.[0-9]{2}\.[0-9]{2}\.[0-9]{2}$' "$OPENSHELL_TAGS_FILE" || true
  else
    git tag -l 'openshell-[0-9][0-9][0-9][0-9].[0-9][0-9].[0-9][0-9].[0-9][0-9]' || true
  fi
}

# true when a scheduled release should notice this path.
release_input() {
  case "$1" in
    openshell/* | .github/workflows/openshell-images.yml | .github/workflows/openshell-build-image.yml | justfile)
      return 0
      ;;
  esac
  return 1
}

# stdout is true or false. $1 is the latest calver tag, or empty.
release_inputs_changed() {
  local latest=$1 line source tmp="" result=false
  if [[ -n "${OPENSHELL_CHANGES_FILE:-}" ]]; then
    source=$OPENSHELL_CHANGES_FILE
  elif [[ -n "${OPENSHELL_TAGS_FILE:-}" ]]; then
    printf 'false\n'
    return 0
  elif [[ -z "$latest" ]]; then
    printf 'true\n'
    return 0
  else
    tmp=$(mktemp)
    if ! git diff --name-only "${latest}^{}" HEAD >"$tmp"; then
      rm -f "$tmp"
      printf 'git diff against %s failed\n' "$latest" >&2
      exit 1
    fi
    source=$tmp
  fi
  while IFS= read -r line || [[ -n "$line" ]]; do
    line=${line%$'\r'}
    if release_input "$line"; then
      result=true
      break
    fi
  done <"$source"
  if [[ -n "$tmp" ]]; then
    rm -f "$tmp"
  fi
  printf '%s\n' "$result"
}

next_release() {
  local tags latest datestr last_epoch now_epoch age_days today today_re count n nn
  local min_age force_age changed
  min_age=${OPENSHELL_MIN_AGE_DAYS:-3}
  force_age=${OPENSHELL_FORCE_AGE_DAYS:-30}
  if [[ ! "$min_age" =~ ^[0-9]+$ || ! "$force_age" =~ ^[0-9]+$ ]]; then
    printf 'age gates must be non-negative integers\n' >&2
    exit 2
  fi
  tags=$(read_tags)
  latest=$(printf '%s\n' "$tags" | sed '/^$/d' | sort -V | tail -n 1)
  if [[ -z "$latest" ]]; then
    printf 'no openshell calver tag yet\n' >&2
    echo true
  else
    datestr=$(printf '%s\n' "$latest" | sed -E 's/^openshell-([0-9]{4})\.([0-9]{2})\.([0-9]{2})\.[0-9]{2}$/\1-\2-\3/')
    last_epoch=$(date -u -d "$datestr" +%s)
    now_epoch=$(date -u -d "$now" +%s)
    age_days=$(((now_epoch - last_epoch) / 86400))
    printf 'latest calver %s is %s day(s) before %s\n' "$latest" "$age_days" "$now" >&2
    if ((age_days >= force_age)); then
      printf 'forced rebuild: age %s >= %s\n' "$age_days" "$force_age" >&2
      echo true
    elif ((age_days >= min_age)); then
      changed=$(release_inputs_changed "$latest")
      if [[ "$changed" == true ]]; then
        printf 'release inputs changed since %s\n' "$latest" >&2
        echo true
      else
        printf 'no release inputs changed since %s\n' "$latest" >&2
        echo false
      fi
    else
      echo false
    fi
  fi
  today=$(date -u -d "$now" +%Y.%m.%d)
  today_re=${today//./\\.}
  count=$(printf '%s\n' "$tags" | grep -c -E "^openshell-${today_re}\\.[0-9]{2}$" || true)
  n=$((count + 1))
  if ((n > 99)); then
    printf 'too many openshell releases on %s\n' "$today" >&2
    exit 1
  fi
  printf -v nn '%02d' "$n"
  printf '%s\n' "${today}.${nn}"
}

agent=false
python=false
rust=false
go=false
pi=false
codex=false
claude=false
all=false

consider_file() {
  local f=$1
  case "$f" in
    .github/workflows/openshell-images.yml | .github/workflows/openshell-build-image.yml)
      all=true
      ;;
    justfile | openshell/justfile | openshell/build.sh | openshell/scripts/docker-build.sh)
      all=true
      ;;
    openshell/versions/base.env | openshell/versions/tools.env)
      agent=true
      ;;
    openshell/versions/python.env)
      python=true
      ;;
    openshell/versions/rust.env)
      rust=true
      ;;
    openshell/versions/go.env)
      go=true
      ;;
    openshell/versions/pi.env)
      pi=true
      ;;
    openshell/versions/codex.env)
      codex=true
      ;;
    openshell/versions/claude.env)
      claude=true
      ;;
    openshell/versions/*)
      all=true
      ;;
    openshell/common/* | openshell/agent-cli/*)
      agent=true
      ;;
    openshell/python/*)
      python=true
      ;;
    openshell/rust/*)
      rust=true
      ;;
    openshell/go/*)
      go=true
      ;;
    openshell/pi/*)
      pi=true
      ;;
    openshell/codex/*)
      codex=true
      ;;
    openshell/claude/*)
      claude=true
      ;;
  esac
}

publish=
image_version=
git_tag=
no_cache=false

case "$event" in
  schedule)
    mapfile -t release_lines < <(next_release)
    due=${release_lines[0]}
    image_version=${release_lines[1]}
    if [[ "$due" == true ]]; then
      publish=release
      git_tag=openshell-${image_version}
      no_cache=true
      all=true
      printf 'scheduled release %s\n' "$git_tag" >&2
    else
      publish=skip
      image_version=
      printf 'scheduled rebuild skipped\n' >&2
    fi
    ;;
  workflow_dispatch)
    case "$publish_input" in
      edge)
        publish=edge
        image_version=edge
        all=true
        ;;
      release)
        mapfile -t release_lines < <(next_release)
        image_version=${release_lines[1]}
        publish=release
        git_tag=openshell-${image_version}
        no_cache=true
        all=true
        printf 'manual release %s\n' "$git_tag" >&2
        ;;
      *)
        usage
        ;;
    esac
    ;;
  push)
    if [[ "$all_files" == true ]]; then
      all=true
    elif [[ -n "$files_path" ]]; then
      while IFS= read -r line || [[ -n "$line" ]]; do
        line=${line%$'\r'}
        [[ -z "$line" ]] && continue
        consider_file "$line"
      done <"$files_path"
    else
      usage
    fi
    ;;
esac

if [[ "$all" == true ]]; then
  agent=true
fi
if [[ "$agent" == true ]]; then
  python=true
  rust=true
  go=true
  pi=true
  codex=true
  claude=true
fi

if [[ -z "$publish" ]]; then
  if [[ "$agent" == true || "$python" == true || "$rust" == true || "$go" == true || "$pi" == true || "$codex" == true || "$claude" == true ]]; then
    publish=edge
    image_version=edge
  else
    publish=skip
  fi
fi

short_sha=$(printf '%s' "$sha" | cut -c1-7)

emit() {
  printf '%s=%s\n' "$1" "$2"
}

emit publish "$publish"
emit image_version "$image_version"
emit git_tag "$git_tag"
emit short_sha "$short_sha"
emit git_sha "$sha"
emit no_cache "$no_cache"
emit build_agent_cli "$agent"
emit build_python "$python"
emit build_rust "$rust"
emit build_go "$go"
emit build_pi "$pi"
emit build_codex "$codex"
emit build_claude "$claude"
