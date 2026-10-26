#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
if rg -n 'HTTPClient|KeyValueStore|FileStore|URLSession|UserDefaults|AppConfig' Sources/ScriptMakerMac/Presentation; then
    echo 'Presentation must use injected domain/settings protocols.' >&2
    exit 1
fi
if rg -n '^import (SwiftUI|AppKit|NewsSearch|TrendingHashtag|KhabarwaaniAgent|AgentAtom|TerminalAgentSession)' Sources/ScriptMakerMac/Domain; then
    echo 'Domain must be independent of UI and provider frameworks.' >&2
    exit 1
fi
if rg -n '\b(GenerateViewModel|PipelineService|OfflineWebClient|NetworkWebClient|AIModelCatalog|mergeClip|SampleData)\b' Sources/ScriptMakerMac; then
    echo 'Removed server/sample architecture must not return.' >&2
    exit 1
fi
if test -d Sources/ScriptMakerMac/Resources/Samples; then
    test -z "$(find Sources/ScriptMakerMac/Resources/Samples -type f -print -quit)"
fi
ruby scripts/check-source-membership.rb
