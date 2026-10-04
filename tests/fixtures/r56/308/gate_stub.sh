#!/bin/sh
tree=$1
case "${GATE56_STUB:-same}:$tree" in
    same:*head) echo 'RESULT case=x pack=layered ticks=3 worst_ms=4 cpu_s=2 sha=12345678 valid=ok' ;;
    same:*) echo 'RESULT case=x pack=layered ticks=3 worst_ms=4 cpu_s=2.5 sha=12345678 valid=ok' ;;
    slow:*head) echo 'RESULT case=x pack=layered ticks=3 worst_ms=4 cpu_s=4 sha=87654321 valid=ok' ;;
    slow:*) echo 'RESULT case=x pack=layered ticks=3 worst_ms=4 cpu_s=2 sha=12345678 valid=ok' ;;
    sameslow:*head) echo 'RESULT case=x pack=layered ticks=3 worst_ms=4 cpu_s=9 sha=12345678 valid=ok' ;;
    sameslow:*) echo 'RESULT case=x pack=layered ticks=3 worst_ms=4 cpu_s=2 sha=12345678 valid=ok' ;;
esac
