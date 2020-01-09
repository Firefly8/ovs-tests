#!/bin/bash
#
# Test add redirect rule from uplink on esw0 to uplink on esw1
# Expect to fail as we don't support this.
#
# Bug SW #2053699: FW accepts unsupported FTE to forward packets from uplink1 to uplink2

my_dir="$(dirname "$0")"
. $my_dir/common.sh


title "Test redirect rule from uplink on esw0 to uplink on esw1"
start_check_syndrome
enable_switchdev_if_no_rep $REP
disable_sriov_port2
enable_sriov_port2
enable_switchdev $NIC2

title "- add redirect rule $NIC2 -> $NIC - expect to fail as we don't support this"
reset_tc $NIC2
tc filter add dev $NIC2 protocol ip ingress prio 1 flower skip_sw action \
    mirred egress redirect dev $NIC && err "Expected to fail"

disable_sriov_port2
check_syndrome

test_done