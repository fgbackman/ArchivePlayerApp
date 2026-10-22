#!/bin/bash
# Double-click this to build the app and open it.
cd "$(dirname "$0")"
chmod +x build.sh 2>/dev/null
./build.sh && open ArchivePlayer.app
echo
echo "Done. You can close this window."
