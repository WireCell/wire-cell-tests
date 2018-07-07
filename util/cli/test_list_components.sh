#!/bin/bash

gotn=$(wire-cell -p WireCellPgraph -p WireCellTbb -p WireCellSio \
                 -p WireCellSigProc -p WireCellGen -p WireCellApps \
                 -a ConfigDumper|jq '.[].type' | wc -l)
wantn=59
if [[ $gotn < $wantn ]] ; then
    echo "Only got too few components: $gotn, expect at least $wantn.  Something is wrong"
    exit 1
fi

wire-cell -p WireCellPgraph -p WireCellTbb -p WireCellSio \
            -p WireCellSigProc -p WireCellGen -p WireCellApps \
            -a ConfigDumper|jq '.[].type'|sort | tr -d '"'

echo "got $gotn components, expected at least $wantn"
