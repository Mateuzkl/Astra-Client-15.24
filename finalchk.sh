#!/bin/bash
L=/mnt/c/Users/joaoc/KoliseuOT/AstraClient/astraclient.log
echo "exceptions:      $(grep -cE 'parse message exception' "$L")"
echo "decompress-fail: $(grep -cE 'invalid size of decompressed|failed to decompress' "$L")"
echo "no-thing:        $(grep -cE 'no thing at pos' "$L")"
echo "trailing-cd:     $(grep -cE 'cross-packet split' "$L")"
echo "tokformat-err:   $(grep -cE 'tokformat' "$L")"
echo "magicshield-err: $(grep -cE 'getMagicShield|useMagicShield' "$L")"
echo "blessing-err:    $(grep -cE 'getBlessingStatus' "$L")"
echo "cyclopedia-err:  $(grep -cE 'setCyclopediaMarketList' "$L")"
echo "reached world:   $(grep -cE 'SpriteSheetLoader: parsed' "$L")"
