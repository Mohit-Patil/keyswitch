#!/bin/bash

set -euo pipefail

usage() {
    cat <<'EOF'
Usage: Scripts/publish_update_feed.sh <release-zip> <version>

Generates the signed Sparkle appcast on a temporary branch, opens or updates a
pull request, explicitly dispatches CI for the bot-authored commit, and merges
the PR only after the required Test check passes on an up-to-date branch.
EOF
}

if [[ $# -ne 2 ]]; then
    usage >&2
    exit 64
fi

archive_path="$1"
version="$2"
repository_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
github_repository="${GITHUB_REPOSITORY:?GITHUB_REPOSITORY is required}"
sparkle_account="${SPARKLE_ACCOUNT:?SPARKLE_ACCOUNT is required}"
runner_temporary_root="${RUNNER_TEMP:-/tmp}"
temporary_directory="$(mktemp -d "$runner_temporary_root/keyswitch-feed.XXXXXX")"
feed_worktree="$temporary_directory/worktree"
published_feed="$temporary_directory/published-appcast.xml"
feed_branch="automation/update-feed-v${version}"
worktree_added=false

cleanup() {
    if [[ "$worktree_added" == true ]]; then
        git -C "$repository_root" worktree remove --force \
            "$feed_worktree" >/dev/null 2>&1 || true
    fi
    case "$temporary_directory" in
        */keyswitch-feed.*)
            find "$temporary_directory" -depth -delete 2>/dev/null || true
            ;;
    esac
}
trap cleanup EXIT

if [[ ! -f "$archive_path" ]]; then
    echo "error: update archive not found: $archive_path" >&2
    exit 66
fi

if [[ ! "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+([-.][A-Za-z0-9.]+)?$ ]]; then
    echo "error: version must look like 1.2.3" >&2
    exit 64
fi

archive_path="$(cd "$(dirname "$archive_path")" && pwd -P)/$(basename "$archive_path")"

fetch_main() {
    git -C "$repository_root" fetch origin \
        refs/heads/main:refs/remotes/origin/main
}

push_feed_branch() {
    local remote_head
    remote_head="$(
        git -C "$repository_root" ls-remote --heads origin \
            "refs/heads/$feed_branch" |
            awk 'NR == 1 { print $1 }'
    )"

    if [[ -n "$remote_head" ]]; then
        git -C "$feed_worktree" push origin \
            --force-with-lease="refs/heads/$feed_branch:$remote_head" \
            "HEAD:refs/heads/$feed_branch"
    else
        git -C "$feed_worktree" push origin \
            "HEAD:refs/heads/$feed_branch"
    fi
}

test_check_state() {
    local commit_sha="$1"
    gh api \
        -H "Accept: application/vnd.github+json" \
        "repos/$github_repository/commits/$commit_sha/check-runs?per_page=100" \
        --jq '(([.check_runs[] | select(.name == "Test")] | sort_by(.started_at) | last) // {}) | [(.status // ""), (.conclusion // "")] | @tsv'
}

wait_for_test_check() {
    local commit_sha="$1"
    local check_state
    local check_status
    local check_conclusion
    local wait_attempt

    check_state="$(test_check_state "$commit_sha")"
    IFS=$'\t' read -r check_status check_conclusion <<< "$check_state"
    if [[ "$check_status" == completed && "$check_conclusion" == success ]]; then
        echo "Required Test check already passed for $commit_sha."
        return
    fi
    if [[ -z "$check_status" ]]; then
        gh workflow run ci.yml \
            --repo "$github_repository" \
            --ref "$feed_branch"
    fi

    for wait_attempt in {1..120}; do
        check_state="$(test_check_state "$commit_sha")"
        IFS=$'\t' read -r check_status check_conclusion <<< "$check_state"
        if [[ "$check_status" == completed ]]; then
            if [[ "$check_conclusion" == success ]]; then
                echo "Required Test check passed for $commit_sha."
                return
            fi
            echo "error: Test check concluded with $check_conclusion" >&2
            exit 1
        fi
        sleep 10
    done

    echo "error: timed out waiting for the Test check" >&2
    exit 1
}

verify_published_feed() {
    local sparkle_tools
    local publish_attempt

    for publish_attempt in {1..12}; do
        fetch_main
        git -C "$repository_root" show origin/main:docs/appcast.xml > \
            "$published_feed"
        if grep -Fq \
            "<sparkle:shortVersionString>${version}</sparkle:shortVersionString>" \
            "$published_feed"; then
            sparkle_tools="$("$repository_root/Scripts/fetch_sparkle_tools.sh")"
            "$sparkle_tools/bin/sign_update" \
                --account "$sparkle_account" \
                --verify \
                "$published_feed"
            return
        fi
        sleep 5
    done

    echo "error: merged update feed did not appear on main" >&2
    exit 1
}

fetch_main
git -C "$repository_root" worktree add --detach \
    "$feed_worktree" origin/main
worktree_added=true

feed="$feed_worktree/docs/appcast.xml"
if grep -Fq \
    "<sparkle:shortVersionString>${version}</sparkle:shortVersionString>" \
    "$feed"; then
    verify_published_feed
    echo "Sparkle feed already contains $version."
    exit 0
fi

(
    cd "$feed_worktree"
    Scripts/generate_update_appcast.sh "$archive_path" "$version"
    git config user.name "github-actions[bot]"
    git config user.email \
        "41898282+github-actions[bot]@users.noreply.github.com"
    git add docs/appcast.xml
    git commit -m "Publish $version update feed"
)

push_feed_branch
pull_request_number="$(
    gh pr list \
        --repo "$github_repository" \
        --base main \
        --head "$feed_branch" \
        --state open \
        --json number \
        --jq '.[0].number // empty'
)"
if [[ -z "$pull_request_number" ]]; then
    gh pr create \
        --repo "$github_repository" \
        --base main \
        --head "$feed_branch" \
        --title "Publish $version update feed" \
        --body "Automated signed Sparkle feed update for KeySwitch $version. The release workflow will merge this PR after its required CI check passes."
    pull_request_number="$(
        gh pr list \
            --repo "$github_repository" \
            --base main \
            --head "$feed_branch" \
            --state open \
            --json number \
            --jq '.[0].number // empty'
    )"
fi
if [[ -z "$pull_request_number" ]]; then
    echo "error: unable to resolve update-feed pull request" >&2
    exit 1
fi

merged=false
for integration_attempt in {1..3}; do
    feed_commit="$(git -C "$feed_worktree" rev-parse HEAD)"
    wait_for_test_check "$feed_commit"

    fetch_main
    if ! git -C "$repository_root" merge-base --is-ancestor \
        origin/main "$feed_commit"; then
        echo "main advanced; rebasing the feed PR before merging."
        git -C "$feed_worktree" rebase origin/main
        push_feed_branch
        continue
    fi

    merge_state=UNKNOWN
    for readiness_attempt in {1..12}; do
        merge_state="$(
            gh pr view "$pull_request_number" \
                --repo "$github_repository" \
                --json mergeStateStatus \
                --jq .mergeStateStatus
        )"
        if [[ "$merge_state" == CLEAN ]]; then
            break
        fi
        if [[ "$merge_state" == BEHIND || "$merge_state" == DIRTY ]]; then
            break
        fi
        sleep 5
    done

    if [[ "$merge_state" == BEHIND ]]; then
        fetch_main
        git -C "$feed_worktree" rebase origin/main
        push_feed_branch
        continue
    fi
    if [[ "$merge_state" != CLEAN ]]; then
        echo "error: feed PR is not mergeable: $merge_state" >&2
        exit 1
    fi

    gh pr merge "$pull_request_number" \
        --repo "$github_repository" \
        --squash \
        --delete-branch
    merged=true
    break
done

if [[ "$merged" != true ]]; then
    echo "error: main kept advancing while the feed PR was being validated" >&2
    exit 1
fi

verify_published_feed
echo "Published signed feed through PR #$pull_request_number."
