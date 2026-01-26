#!/bin/bash
# Analyzes task description and outputs recommended Claude model
# Usage: analyze-complexity.sh "<task description>"

DESCRIPTION="$1"

if [ -z "$DESCRIPTION" ]; then
    echo "Usage: $0 \"<task description>\"" >&2
    exit 1
fi

# Complex keywords -> opus (security, architecture, deep reasoning)
if echo "$DESCRIPTION" | grep -qiE 'security|architecture|algorithm|design pattern|audit|critical|sensitive'; then
    echo "opus"
    exit 0
fi

# Moderate keywords -> sonnet (refactoring, testing, documentation)
if echo "$DESCRIPTION" | grep -qiE 'refactor|test|debug|document|migrate|complex|design|implement.*feature|optimize'; then
    echo "sonnet"
    exit 0
fi

# Word count check - longer descriptions suggest moderate complexity
WORD_COUNT=$(echo "$DESCRIPTION" | wc -w | tr -d ' ')
if [ "$WORD_COUNT" -gt 20 ]; then
    echo "sonnet"
    exit 0
fi

# Default to haiku for simple tasks
echo "haiku"
