#!/bin/bash
erl -name client@292-Linux.domain1.intra -setcookie test +K true +P 2000000 -pa ebin priv -boot start_sasl -config elog.config -s ewsc_app
