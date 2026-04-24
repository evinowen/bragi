#!/bin/bash
set -euo pipefail

export INDEXERS_JSON="$(echo '__INDEXERS_B64__' | base64 -d)"
export SABNZBD_MAX_DOWNLOAD_SPEED="__SABNZBD_MAX_SPEED__"

cd /root
git clone https://github.com/evinowen/bragi.git
cd bragi
chmod +x install.sh

expect - << 'EXPECT'
set timeout 1200
log_user 1

spawn bash /root/bragi/install.sh

expect {
    -re {Server host:} {
        send "__USENET_HOST__\r"
        exp_continue
    }
    -re {Usenet username:} {
        send "__USENET_USER__\r"
        exp_continue
    }
    -re {Usenet password:} {
        send "__USENET_PASS__\r"
        exp_continue
    }
    -re {Enable SSL\? \[Y/n\]:} {
        send "__SSL_RESPONSE__\r"
        exp_continue
    }
    -re {Install all services\? \[A/c\]:} {
        if {"__DISABLED_SERVICES__" ne ""} {
            send "c\r"
        } else {
            send "a\r"
        }
        exp_continue
    }
    -re {Install (\w+)\? \[Y/n\]:} {
        set service $expect_out(1,string)
        set disabled {__DISABLED_SERVICES__}
        if {$disabled ne "" && [lsearch -exact [split $disabled] $service] >= 0} {
            send "n\r"
        } else {
            send "y\r"
        }
        exp_continue
    }
    -re {Choose configuration mode \[s/i\]:} {
        send "s\r"
        exp_continue
    }
    -re {Base directory \[/media/television\]:} {
        send "\r"
        exp_continue
    }
    -re {Base directory \[/media/movies\]:} {
        send "\r"
        exp_continue
    }
    -re {Would you like to create these directories\? \[y/N\]:} {
        send "y\r"
        exp_continue
    }
    eof
}

set wait_result [wait]
set exit_code [lindex $wait_result 3]
exit $exit_code
EXPECT
