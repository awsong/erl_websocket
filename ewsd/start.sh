#!/bin/bash
erl -name server@291-Linux +K true +P 2000000 -pa ebin priv -boot start_sasl -s ewsd_app
