#!/usr/bin/env bash
exec bash "$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/hunt-check.sh" hunt-uncertain
