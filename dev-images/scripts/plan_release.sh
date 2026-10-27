#!/usr/bin/env bash
# Decide whether to publish dev-base.
#
# GitHub cron cannot express "every 3 days". The schedule runs daily. It
# publishes a calver release when there is no dev-images-YYYY.MM.DD.NN tag
# yet, when the newest tag is at least DEV_IMAGES_FORCE_AGE_DAYS old (30),
# or when that tag is at least DEV_IMAGES_MINIMUM_AGE_DAYS old (3) and a
# release input has changed since the tag. Release inputs are files under
# dev-images/, the root justfile, and the workflows that build the images.
# workflow_dispatch release does not use those gates.
#
# stdout is key=value lines for $GITHUB_OUTPUT. Diagnostics go to stderr.
# build_base publishes dev-base first. The language images depend on that job.
set -euo pipefail

event=
publish_input=
sha=
files_path=
all_files=false

usage() {
  printf 'usage: plan_release.sh --event push|schedule|workflow_dispatch --sha SHA [--files PATH | --all-files] [--publish edge|release]\n' >&2
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

now=${DEV_IMAGES_NOW:-$(date -u +%Y-%m-%d)}
if [[ ! "$now" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]]; then
  printf 'DEV_IMAGES_NOW must be YYYY-MM-DD\n' >&2
  exit 2
fi

read_tags() {
  if [[ -n "${DEV_IMAGES_TAGS_FILE:-}" ]]; then
    grep -E '^dev-images-[0-9]{4}\.[0-9]{2}\.[0-9]{2}\.[0-9]{2}$' "$DEV_IMAGES_TAGS_FILE" || true
  else
    git tag -l 'dev-images-[0-9][0-9][0-9][0-9].[0-9][0-9].[0-9][0-9].[0-9][0-9]' || true
  fi
}

release_input() {
  case "$1" in
    dev-images/* | .github/workflows/dev-images-publish.yml | .github/workflows/dev-images-build-single-image.yml | justfile)
      return 0
      ;;
  esac
  return 1
}

release_inputs_changed() {
  local latest=$1 line source temporary="" result=false
  if [[ -n "${DEV_IMAGES_CHANGES_FILE:-}" ]]; then
    source=$DEV_IMAGES_CHANGES_FILE
  elif [[ -n "${DEV_IMAGES_TAGS_FILE:-}" ]]; then
    printf 'false\n'
    return 0
  elif [[ -z "$latest" ]]; then
    printf 'true\n'
    return 0
  else
    temporary=$(mktemp)
    if ! git diff --name-only "${latest}^{}" HEAD >"$temporary"; then
      rm -f "$temporary"
      printf 'git diff against %s failed\n' "$latest" >&2
      exit 1
    fi
    source=$temporary
  fi
  while IFS= read -r line || [[ -n "$line" ]]; do
    line=${line%$'\r'}
    if release_input "$line"; then
      result=true
      break
    fi
  done <"$source"
  if [[ -n "$temporary" ]]; then
    rm -f "$temporary"
  fi
  printf '%s\n' "$result"
}

next_release() {
  local tags latest datestr last_epoch now_epoch age_days today today_re count sequence sequence_text
  local minimum_age force_age changed
  minimum_age=${DEV_IMAGES_MINIMUM_AGE_DAYS:-3}
  force_age=${DEV_IMAGES_FORCE_AGE_DAYS:-30}
  if [[ ! "$minimum_age" =~ ^[0-9]+$ || ! "$force_age" =~ ^[0-9]+$ ]]; then
    printf 'age gates must be non-negative integers\n' >&2
    exit 2
  fi
  tags=$(read_tags)
  latest=$(printf '%s\n' "$tags" | sed '/^$/d' | sort -V | tail -n 1)
  if [[ -z "$latest" ]]; then
    printf 'no dev-images calver tag yet\n' >&2
    echo true
  else
    datestr=$(printf '%s\n' "$latest" | sed -E 's/^dev-images-([0-9]{4})\.([0-9]{2})\.([0-9]{2})\.[0-9]{2}$/\1-\2-\3/')
    last_epoch=$(date -u -d "$datestr" +%s)
    now_epoch=$(date -u -d "$now" +%s)
    age_days=$(((now_epoch - last_epoch) / 86400))
    printf 'latest calver %s is %s day(s) before %s\n' "$latest" "$age_days" "$now" >&2
    if ((age_days >= force_age)); then
      printf 'forced rebuild: age %s >= %s\n' "$age_days" "$force_age" >&2
      echo true
    elif ((age_days >= minimum_age)); then
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
  count=$(printf '%s\n' "$tags" | grep -c -E "^dev-images-${today_re}\\.[0-9]{2}$" || true)
  sequence=$((count + 1))
  if ((sequence > 99)); then
    printf 'too many dev-images releases on %s\n' "$today" >&2
    exit 1
  fi
  printf -v sequence_text '%02d' "$sequence"
  printf '%s\n' "${today}.${sequence_text}"
}

build_base=false

consider_file() {
  local path=$1
  case "$path" in
    .github/workflows/dev-images-publish.yml | .github/workflows/dev-images-build-single-image.yml)
      build_base=true
      ;;
    justfile | dev-images/*)
      build_base=true
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
      git_tag=dev-images-${image_version}
      no_cache=true
      build_base=true
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
        build_base=true
        ;;
      release)
        mapfile -t release_lines < <(next_release)
        image_version=${release_lines[1]}
        publish=release
        git_tag=dev-images-${image_version}
        no_cache=true
        build_base=true
        printf 'manual release %s\n' "$git_tag" >&2
        ;;
      *)
        usage
        ;;
    esac
    ;;
  push)
    if [[ "$all_files" == true ]]; then
      build_base=true
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

if [[ -z "$publish" ]]; then
  if [[ "$build_base" == true ]]; then
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
emit build_base "$build_base"
