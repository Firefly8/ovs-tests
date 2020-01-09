#!/bin/bash
#
# Test OVS CT TCP with label

my_dir="$(dirname "$0")"
. $my_dir/common.sh

require_module act_ct
echo 1 > /proc/sys/net/netfilter/nf_conntrack_tcp_be_liberal

IP1="7.7.7.1"
IP2="7.7.7.2"

config_sriov 2
enable_switchdev_if_no_rep $REP
require_interfaces REP REP2
unbind_vfs
bind_vfs
reset_tc $REP
reset_tc $REP2

function cleanup() {
    ip netns del ns0 2> /dev/null
    ip netns del ns1 2> /dev/null
    reset_tc $REP
    reset_tc $REP2
}
trap cleanup EXIT

function config_vf() {
    local ns=$1
    local vf=$2
    local rep=$3
    local ip=$4

    echo "[$ns] $vf ($ip) -> $rep"
    ifconfig $rep 0 up
    ip netns add $ns
    ip link set $vf netns $ns
    ip netns exec $ns ifconfig $vf $ip/24 up
}

function reconfig_flows() {
    ovs-ofctl del-flows br-ovs
    ovs-ofctl add-flow br-ovs arp,actions=normal
    ovs-ofctl add-flow br-ovs "table=0, ip,ct_state=-trk actions=ct(table=1)"
    ct_label="0x12345"
    ovs-ofctl add-flow br-ovs "table=1, ip,ct_state=+trk+new actions=ct(commit,exec(set_field:$ct_label->ct_label)),normal"
    ovs-ofctl add-flow br-ovs "table=1, ip,ct_state=+trk+est,ct_label=$ct_label/0xffffffff actions=normal"
}

function run() {
    title "Test OVS CT TCP"
    config_vf ns0 $VF $REP $IP1
    config_vf ns1 $VF2 $REP2 $IP2

    echo "setup ovs"
    start_clean_openvswitch
    ovs-vsctl add-br br-ovs
    ovs-vsctl add-port br-ovs $REP
    ovs-vsctl add-port br-ovs $REP2

    reconfig_flows
    ovs-ofctl dump-flows br-ovs --color

    echo "sniff packets on $REP"
    timeout 5 tcpdump -qnnei $REP -c 10 'tcp' &
    pid1=$!

    t=12
    echo "run traffic for $t seconds"
    ip netns exec ns1 timeout $((t+1)) iperf -s &
    sleep 0.5
    ip netns exec ns0 timeout $((t+1)) iperf -t $t -c $IP2 -P 3 &

    sleep 3
    pidof iperf &>/dev/null || err "iperf failed"

    echo "sniff packets on $REP"
    timeout $t tcpdump -qnnei $REP -c 10 'tcp' &
    pid2=$!

    sleep $t
    killall -9 iperf &>/dev/null
    wait $! 2>/dev/null

    title "test have initial traffic"
    test_have_traffic $pid1
    title "test offloaded traffic"
    test_no_traffic $pid2

    ovs-vsctl del-br br-ovs
}

function test_have_traffic() {
    local pid=$1
    wait $pid
    rc=$?
    if [[ $rc -eq 0 ]]; then
        :
    elif [[ $rc -eq 124 ]]; then
        err "Expected to see packets"
    else
        err "Tcpdump failed"
    fi
}

function test_no_traffic() {
    local pid=$1
    wait $pid
    rc=$?
    if [[ $rc -eq 124 ]]; then
        :
    elif [[ $rc -eq 0 ]]; then
        err "Didn't expect to see packets"
    else
        err "Tcpdump failed"
    fi
}


run
test_done