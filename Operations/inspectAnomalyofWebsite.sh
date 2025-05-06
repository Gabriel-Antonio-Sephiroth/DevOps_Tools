#!/bin/bash
URL_LIST="www.baidu.com [url=http://www.ctnrs.com]www.ctnrs.com[/url]"
for URL in $URL_LIST; do
    FAIL_COUNT=0
    for ((i=1;i&lt;=3;i++)); do
        HTTP_CODE=$(curl -o /dev/null --connect-timeout 3 -s -w "%{http_code}" $URL)
        if [ $HTTP_CODE -eq 200 ]; then
            echo "$URL OK"
            break
        else
            echo "$URL retry $FAIL_COUNT"
            let FAIL_COUNT++
        fi
    done
    if [ $FAIL_COUNT -eq 3 ]; then
        echo "Warning: $URL Access failure!"
    fi
done