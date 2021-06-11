#!/bin/sh

####################################################################################
#/etc/config/smartvpn example
#
#config global "settings"
#	option disabled "1"
#      	option status "off"
#        option type vpn
#        option domain_file /etc/smartvpn/proxy.txt
#        option proxy_local_port  10080
#        option proxy_remote_ip   54.85.90.122

#mac: devices which transfer through vpn
#notmac: devices which not transfer through vpn
#config device 'device'
#        list mac '34:17:eb:d0:e6:f9'
#        list mac '34:17:eb:d0:e6:a9'
#host: website which transfer through vpn
#nothost: website which not transfer through vpn
#config dest 'dest'
#        list host '.google.com'
#        list notnet '169.254.0.0/16'
#        list notnet '0.0.0.0/8'
#        list notnet '10.0.0.0/8'
#        list notnet '127.0.0.0/8'
#        list notnet '169.254.0.0/16'
#        list notnet '172.16.0.0/12'
#        list notnet '192.168.0.0/16'
#        list notnet '224.0.0.0/4'
#        list notnet '240.0.0.0/4'
####################################################################################

#model=`nvram get model`
#if [ -z "$model" ]; then
#    model=`cat /proc/xiaoqiang/model`
#fi
#if [ "$model" != "R1D" ]; then
#    return 1
#fi

. /lib/functions.sh
. /lib/functions/network.sh

ipset_name="smartvpn"
ipset_ip_name="smartvpn_ip"
ipset_mark="0x10/0x10"

vpn_status="down"
smartvpn_cfg_domain_disabled=1
smartvpn_cfg_status="off"
smartvpn_cfg_type="vpn"
smartvpn_cfg_domainfile=""

dnsmasq_conf_path="/etc/dnsmasq.d/"
smartdns_conf_path="/etc/smartvpn/"
smartdns_conf_name="smartdns.conf"
smartdns_conf="$smartdns_conf_path/$smartdns_conf_name"

rule_file_ip="/etc/smartvpn/smartvpn_ip.txt"

set_smartvpn_cfg_status_on="uci set smartvpn.settings.status=on; uci commit smartvpn;"
set_smartvpn_cfg_status_off="uci set smartvpn.settings.status=off; uci commit smartvpn;"

hostlist_not_null=0

smartvpn_logger()
{
    echo "smartvpn: $1"
    logger -t smartvpn "$1"
}

smartvpn_usage()
{
    echo "usage: ./smartvpn.sh on|off"
    echo "value: on  -- enable smartvpn"
    echo "value: off -- disable smartvpn"
    echo "note:  smartvpn only used when vpn is UP!"
    echo ""
}

dnsmasq_restart()
{
    dnamasq_lock="/var/run/samartvpn.dnsmasq.lock"
    trap "lock -u $dnamasq_lock; exit 1" SIGHUP SIGINT SIGTERM
    lock $dnamasq_lock

    $set_smartvpn_switch_off >/dev/null 2>&1
    $set_switch_commit >/dev/null 2>&1

    process_pid=$(ps | grep "/usr/sbin/dnsmasq" |grep -v "grep /usr/sbin/dnsmasq" | awk '{print $1}' 2>/dev/null)
    process_num=$( echo $process_pid |awk '{print NF}' 2>/dev/null)
    process_pid1=$( echo $process_pid |awk '{ print $1; exit;}' 2>/dev/null)
    process_pid2=$( echo $process_pid |awk '{ print $2; exit;}' 2>/dev/null)

    [ "$process_num" != "2" ] && /etc/init.d/dnsmasq restart

    retry_times=0
    while [ $retry_times -le 2 ]
    do
        let retry_times+=1
        rm /var/etc/dnsmasq.conf

        # remove DNS entry pushed by Softether
        sed -i -e '/nameserver 8.8.8.8/d' /tmp/resolv.conf.auto
        sed -i -e '/nameserver 1.1.1.1/d' /tmp/resolv.conf.auto

        /etc/init.d/dnsmasq restart
        sleep 1

        process_newpid=$(ps | grep "/usr/sbin/dnsmasq" |grep -v "grep /usr/sbin/dnsmasq" | awk '{print $1}' 2>/dev/null)
        process_newnum=$( echo $process_newpid |awk '{print NF}' 2>/dev/null)
        process_newpid1=$( echo $process_newpid |awk '{ print $1; exit;}' 2>/dev/null)
        process_newpid2=$( echo $process_newpid |awk '{ print $2; exit;}' 2>/dev/null)

        echo "old: $process_pid1/$process_pid2 new: $process_newpid1/$process_newpid2"

        [ "$process_pid1" == "$process_newpid1" ] && continue;
        [ "$process_pid1" == "$process_newpid2" ] && continue;
        [ "$process_pid2" == "$process_newpid1" ] && continue;
        [ "$process_pid2" == "$process_newpid2" ] && continue;

        break
    done

    lock -u $dnamasq_lock
}

smartvpn_dns_start()
{
    # move dnsmasq conf
    if [ -f $smartdns_conf ]; then
        mv  $smartdns_conf $dnsmasq_conf_path
    fi

    # flush dnsmasq
    dnsmasq_restart

    return
}

smartvpn_dns_stop()
{
    # del smartvpn dnsmasq conf
    rm "$dnsmasq_conf_path/$smartdns_conf_name"
    rm "/var/etc/dnsmasq.d/$smartdns_conf_name"
    rm "/tmp/etc/dnsmasq.d/$smartdns_conf_name"

    # flush dnsmasq
    dnsmasq_restart

    return
}

smartvpn_ipset_create()
{

    ipset list | grep $ipset_name  > /dev/null 2>&1
    if [ $? -ne 0 ]; then
        ipset create $ipset_name  hash:ip > /dev/null 2>&1
        ipset create $ipset_ip_name hash:net > /dev/null 2>&1
    fi
}

smartvpn_ipset_add_by_file()
{
    local _ipfile=$1

    [ -f $_ipfile ] || return

    ipset create $ipset_ip_name hash:net > /dev/null 2>&1

    smartvpn_logger "add ip to ipset $ipset_ip_name."
    cat $_ipfile | while read line
    do
        ipset add $ipset_ip_name $line
    done

}

smartvpn_ipset_delete()
{
    ipset flush $ipset_name
    ipset flush $ipset_ip_name

    ipset destroy $ipset_name # maybe failed, but doesn't matter
    ipset destroy $ipset_ip_name # maybe failed, but doesn't matter

    return
}


smartvpn_vpn_route_delete()
{
    # del subnet default routing
    network_get_subnet subnet lan
    ip rule del from $(fix_subnet $subnet) table vpn
    smartvpn_logger "delete $subnet to vpn."	

    return 0
}

smartvpn_vpn_route_add()
{
    # after smartvpn is off, add wan route if vpn is still up
    if [ $vpn_status == "up" ]; then

        network_get_subnet subnet lan
	        smartvpn_logger "add $subnet to vpn."
        ip rule del from $(fix_subnet $subnet) table vpn
        ip rule add from $(fix_subnet $subnet) table vpn
    fi

    return 0
}

smartvpn_wandns2vpn_remove()
{
    network_get_dnsserver dnsservers wan
    for dnsserver in $dnsservers; do
        smartvpn_logger "wan dns del $dnsserver to vpn"
        ip rule del to $dnsserver table vpn
    done
}

smartvpn_firewall_reload_add()
{
uci -q batch <<-EOF >/dev/null
    set firewall.smartvpn=include
    set firewall.smartvpn.path="/lib/firewall.sysapi.loader smartvpn"
    set firewall.smartvpn.reload=1
    commit firewall
EOF
    return 0
}

smartvpn_firewall_reload_delete()
{
uci -q batch <<-EOF >/dev/null
    delete firewall.smartvpn
    commit firewall
EOF
    return 0
}

smartvpn_device_table="smartvpn_device"
smartvpn_mark_table="smartvpn_mark"
smartvpn_vpn_mark_redirect_open()
{

    ip rule add fwmark $ipset_mark table vpn

    #allowmacs="$(uci get smartvpn.device.mac 2>/dev/null)"
    #notnets="$(uci get smartvpn.dest.notnet 2>/dev/null)"

    iptables -t mangle -F $smartvpn_device_table 2>/dev/null
    iptables -t mangle -X $smartvpn_device_table 2>/dev/null
    iptables -t mangle -N $smartvpn_device_table 2>/dev/null

    iptables -t mangle -F $smartvpn_mark_table 2>/dev/null
    iptables -t mangle -X $smartvpn_mark_table 2>/dev/null
    iptables -t mangle -N $smartvpn_mark_table 2>/dev/null

    #which dest not transfer through VPN
    #if [ "$smartvpn_cfg_hostnotnet" != "" ]
    #then
    #    for notnet in $smartvpn_cfg_hostnotnet
    #    do
    #        smartvpn_logger "locat net add $notnet."
    #        iptables -t nat -A $smartvpn_mark_table -d $notnet -j ACCEPT
    #    done
    #fi

    #allowmacs not NULL
    if [ "$smartvpn_cfg_devicemac" != "" ]
    then
        for mac in $smartvpn_cfg_devicemac
        do
            smartvpn_logger "device mac add $mac."
            iptables -t mangle -A $smartvpn_device_table  -m mac --mac-source $mac -j RETURN
        done

        iptables -t mangle -A $smartvpn_device_table -j ACCEPT
    else
        smartvpn_logger "all devices traffic to vpn."
        iptables -t mangle -A $smartvpn_device_table -j RETURN
    fi
   
    smartvpn_logger "$dnsmasq_conf_path/$smartdns_conf_name hostlist_not_null $hostlist_not_null."
    #dns mark not NULL
    [ -s $dnsmasq_conf_path/$smartdns_conf_name ] && {
        hostlist_not_null=1
    }
    smartvpn_logger "hostlist_not_null $hostlist_not_null."

    if [ "$hostlist_not_null" != "1" ]
    then
        smartvpn_logger "add all host mark $ipset_mark to vpn."
        iptables -t mangle -A $smartvpn_mark_table -j MARK --set-mark $ipset_mark
    else
        smartvpn_wandns2vpn_remove
        smartvpn_logger "add ipset $ipset_name + $ipset_ip_name to vpn."
        iptables -t mangle -A $smartvpn_mark_table -m set --match-set $ipset_name  dst -j MARK --set-mark $ipset_mark
        iptables -t mangle -A $smartvpn_mark_table -m set --match-set $ipset_ip_name  dst -j MARK --set-mark $ipset_mark
    fi

    iptables -t mangle -A PREROUTING -j smartvpn_device
    iptables -t mangle -A PREROUTING -j smartvpn_mark

    return
}

smartvpn_vpn_mark_redirect_close()
{
    iptables -t mangle -D PREROUTING -j smartvpn_device
    iptables -t mangle -D PREROUTING -j smartvpn_mark

    iptables -t mangle -F $smartvpn_device_table
    iptables -t mangle -X $smartvpn_device_table

    iptables -t mangle -F $smartvpn_mark_table
    iptables -t mangle -X $smartvpn_mark_table

    #iptables -t mangle -D $smartvpn_mark_table -m set --match-set $ipset_name  dst -j MARK --set-mark $ipset_mark

    ip rule del fwmark $ipset_mark table vpn > /dev/null 2>&1


    return
}

vpn_status_get()
{
    network_is_up vpn
    if [ $? -eq 0 ]; then
        vpn_status="up"
    else
        vpn_status="down"
    fi
    return
}

#config remote "vpn"
#	option disabled "1"
#      	option status "off"
#       option domain_file /etc/smartvpn/vpn.txt
#       option type vpn

smartvpn_config_get()
{
    config_load "smartvpn"

    config_get smartvpn_cfg_domain_switch vpn switch &>/dev/null;

    config_get smartvpn_cfg_domain_disabled vpn disabled &>/dev/null;

    config_get smartvpn_cfg_status vpn status &>/dev/null;

    config_get smartvpn_cfg_type vpn type &>/dev/null;

    config_get smartvpn_cfg_domainfile vpn domain_file &>/dev/null;

    config_get smartvpn_cfg_devicemac device  mac &>/dev/null

    config_get smartvpn_cfg_devicedisabled device  disabled &>/dev/null

    config_get smartvpn_cfg_hostnotnet dest notnet &>/dev/null

    if [ -z $smartvpn_cfg_domain_disabled ];
    then
        smartvpn_cfg_domain_disabled="0"
    fi

    if [ -z $smartvpn_cfg_status ];
    then
        smartvpn_cfg_status="off"
    fi

    if [ $smartvpn_cfg_type != "vpn" ]
    then
        return 1
    fi

    return 0
}

smartvpn_flush()
{

    if [ $smartvpn_cfg_domain_disabled -ne 0 ]
    then
        smartvpn_logger "smartvpn not enabled."
        return 1
    fi

    if [  $smartvpn_cfg_type != "vpn" ]
    then
        smartvpn_logger "smartvpn not in vpn."
        return 1
    fi

    if [ $smartvpn_cfg_status != "on" ];
    then
        smartvpn_logger "smartvpn not run."
        return 1
    fi

    smartvpn_vpn_mark_redirect_close

    smartvpn_vpn_mark_redirect_open

    return 0;
}

smartvpn_set_off()
{
    uci set smartvpn.vpn.status=off
    uci commit smartvpn
}

smartvpn_set_on()
{
    uci set smartvpn.vpn.status=on
    uci commit smartvpn
}

smartvpn_open()
{
    if [ $smartvpn_cfg_status == "on" ];
    then
        smartvpn_logger "already enabled."
        return 1
    fi

    if [  $vpn_status != "up" ];
    then
        smartvpn_logger "vpn_status($vpn_status) is down, return."
        return 1
    fi

    [ $smartvpn_cfg_domain_disabled == "1" ] && smartvpn_cfg_domainfile=""

    if [ -s $smartvpn_cfg_domainfile  -a $smartvpn_cfg_type == "vpn" ]
    then
        smartvpn_logger "translet domain to ipset."
        gensmartdns.sh "$smartvpn_cfg_domainfile" "$smartdns_conf" "$rule_file_ip" "$ipset_name"
    fi

    [ $smartvpn_cfg_devicedisabled == "1" ] && smartvpn_cfg_devicemac=""

    ### enable smartvpn
    smartvpn_ipset_create

    [ -f $rule_file_ip ] && {
        smartvpn_logger "add ips to ipset."
        smartvpn_ipset_add_by_file $rule_file_ip
        hostlist_not_null=1
        rm $rule_file_ip
    }

    smartvpn_dns_start
    smartvpn_vpn_route_delete
    smartvpn_vpn_mark_redirect_open
    smartvpn_firewall_reload_add

    # 通过vpn访问路由器上的端口（通过vpn访问ssh端口）
    ip route add 192.168.30.0/24 dev l2tp-vpn
    ip route add 192.168.29.0/24 dev l2tp-vpn

    ip route flush table cache

    smartvpn_logger "status set on."

    smartvpn_set_on

    smartvpn_logger "smartvpn open!"

    return
}

smartvpn_close()
{
    if [ $smartvpn_cfg_status == "off" ];
    then
        smartvpn_logger "status already off!"
        return 0
    fi

    smartvpn_vpn_mark_redirect_close
    smartvpn_vpn_route_add
    smartvpn_firewall_reload_delete

    smartvpn_dns_stop

    smartvpn_ipset_delete

    # 通过vpn访问路由器上的端口（通过vpn访问ssh端口）
    ip route del 192.168.30.0/24 dev l2tp-vpn
    ip route del 192.168.29.0/24 dev l2tp-vpn

    ip route flush table cache

    smartvpn_set_off
    smartvpn_logger "status set off."

    smartvpn_logger "smartvpn close!"

    return
}

vpn_status_get

smartvpn_config_get || return 1

OPT=$1

[ "$smartvpn_cfg_domain_switch" != "1" ] && return 1;

smartvpn_lock="/var/run/samartvpn.lock"
trap "lock -u $smartvpn_lock; exit 1" SIGHUP SIGINT SIGTERM
lock $smartvpn_lock
#main
case $OPT in
    on)
        smartvpn_close
        smartvpn_cfg_status=off
        smartvpn_open
        lock -u $smartvpn_lock
        return $?
    ;;

    flush)
        smartvpn_close
        smartvpn_cfg_status=off
        smartvpn_open
        lock -u $smartvpn_lock
        return $?
    ;;
    off)
        smartvpn_close
        lock -u $smartvpn_lock
        return $?
    ;;

    *)
        smartvpn_usage
        lock -u $smartvpn_lock
        return 1
    ;;
esac

