#!/bin/bash
# 日志格式: $remote_addr - $remote_user [$time_local] "$request" $status $body_bytes_sent "$http_referer" "$http_user_agent" "$http_x_forwarded_for"
LOG_FILE=$1
echo "访问最多的10个IP"
awk '{a[$1]++}END{print "UV:",length(a);for(v in a)print v,a[v]}' $LOG_FILE |sort -k2 -nr |head -10
echo "----------------------"
 
echo "某时间段访问最多的IP"
awk '$4&gt;="[01/Dec/2021:13:20:25" &amp;&amp; $4&lt;="[27/Nov/2021:16:20:49"{a[$1]++}END{for(v in a)print v,a[v]}' $LOG_FILE |sort -k2 -nr|head -10
echo "----------------------"
 
echo "访问最多的10个页面"
awk '{a[$7]++}END{print "PV:",length(a);for(v in a){if(a[v]&gt;10)print v,a[v]}}' $LOG_FILE |sort -k2 -nr
echo "----------------------"
 
echo "访问页面状态码数量"
awk '{a[$7" "$9]++}END{for(v in a){if(a[v]&gt;5)print v,a[v]}}'