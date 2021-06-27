#!/bin/sh

. /lib/functions.sh
. /lib/functions/network.sh


vpn_dev="tap_gzhub"

ipset_name="smartvpn"
ipset_ip_name="smartvpn_ip"
ipset_mark="0x10/0x10"

smartvpn_cfg_type="vpn"
smartvpn_cfg_domainfile="/etc/smartvpn/proxy.txt"

dnsmasq_conf_path="/etc/dnsmasq.d/"
smartdns_conf_path="/etc/smartvpn/"
smartdns_conf_name="smartdns.conf"
smartdns_conf="$smartdns_conf_path/$smartdns_conf_name"

rule_file_ip="/etc/smartvpn/smartvpn_ip.txt"

smartvpn_logger()
{
    logger -s -p alert -t softether_vpn "$1"
}

dnsmasq_restart()
{
    dnamasq_lock="/var/run/samartvpn.dnsmasq.lock"
    trap "lock -u $dnamasq_lock; exit 1" SIGHUP SIGINT SIGTERM
    lock $dnamasq_lock

    # $set_smartvpn_switch_off >/dev/null 2>&1
    # $set_switch_commit >/dev/null 2>&1

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

smartvpn_ipset_create()
{

    ipset list | grep $ipset_name  > /dev/null 2>&1
    if [ $? -ne 0 ]; then
        ipset create $ipset_name  hash:ip > /dev/null 2>&1
        ipset create $ipset_ip_name hash:net > /dev/null 2>&1
    else
        ipset flush $ipset_name
        ipset flush $ipset_ip_name
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
    # rm "/var/etc/dnsmasq.d/$smartdns_conf_name"
    rm "/tmp/etc/dnsmasq.d/$smartdns_conf_name"

    # flush dnsmasq
    dnsmasq_restart

    return
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
    set firewall.smartvpn.path="/usr/sbin/softether_vpn.sh reload"
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

    # 有ipset标记的数据包走vpn路由（ip rule from all fwmark 0x10 lookup vpn）
    ip rule del fwmark $ipset_mark table vpn > /dev/null 2>&1
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
    # if [ "$smartvpn_cfg_devicemac" != "" ]
    # then
    #     for mac in $smartvpn_cfg_devicemac
    #     do
    #         smartvpn_logger "device mac add $mac."
    #         iptables -t mangle -A $smartvpn_device_table  -m mac --mac-source $mac -j RETURN
    #     done

    #     iptables -t mangle -A $smartvpn_device_table -j ACCEPT
    # else
    #     smartvpn_logger "all devices traffic to vpn."
    #     iptables -t mangle -A $smartvpn_device_table -j RETURN
    # fi
   
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
        # wan口DNS不能走vpn通道
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

    ip rule del fwmark $ipset_mark table vpn

    return
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

smartvpn_vpn_route_delete()
{
    # del subnet default routing
    smartvpn_logger "delete $subnet to vpn."
    network_get_subnet subnet lan
    ip rule del from $(fix_subnet $subnet) table vpn

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

smartvpn_enable()
{
    # 根据proxy.txt生成dnsmasq配置
    gensmartdns.sh "$smartvpn_cfg_domainfile" "$smartdns_conf" "$rule_file_ip" "$ipset_name" > /dev/null 2>&1

    smartvpn_ipset_create   # 创建ipset

    [ -f $rule_file_ip ] && {
        smartvpn_logger "add ips to ipset."
        smartvpn_ipset_add_by_file $rule_file_ip
        hostlist_not_null=1
        rm $rule_file_ip
    }

    smartvpn_dns_start               # 重启nsmasq       
    smartvpn_vpn_route_delete        # 删除lan到vpn路由
    smartvpn_vpn_mark_redirect_open  # 添加智能路由标记防火墙规则

    smartvpn_firewall_reload_add     # 防火墙规则重载时要重新设置smartvpn规则（重新拨号会导致防火墙重载）

    ip route flush table cache
}

smartvpn_open()
{
    if [ $vpn_status == "up" ];
    then
        smartvpn_logger "buildin l2tp vpn is up! can not enable smartvpn for softether."
        return 1
    fi


    if [ $smartvpn_cfg_switch != "1" ];
    then
        smartvpn_logger "smartvpn cfg switch is off."
        return 1
    fi

    if [ $smartvpn_status == "on" ];
    then
        smartvpn_logger "already enabled."
        return 0
    fi

    if [ $softether_status == "stop" ];
    then
        smartvpn_logger "softether is stop. restarting..."
        /opt/etc/init.d/S05vpnserver start
    fi


    smartvpn_enable
    
    smartvpn_logger "smartvpn open!"

}

smartvpn_close()
{
    if [ $smartvpn_status == "off" ];
    then
        smartvpn_logger "status already off!"
        return 0
    fi

    if [ $vpn_status == "up" ];
    then
        smartvpn_logger "buildin vpn is up! can not disable smartvpn."
        return 1
    fi

    smartvpn_vpn_mark_redirect_close    # 删除智能路由标记防火墙规则
    smartvpn_vpn_route_add              # 恢复lan到vpn路由
    smartvpn_firewall_reload_delete     # 清除防火墙重载
        
    smartvpn_dns_stop           # 重启nsmasq       
    smartvpn_ipset_delete       # 删除ipset


    smartvpn_logger "smartvpn close!"

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

smartvpn_status_get()
{    
    __tmp="$(ip rule | grep "fwmark 0x10/0x10 lookup vpn" 2>/dev/null)"
    if  [ -n "$__tmp" ]; then
        smartvpn_status="on"
    else
        smartvpn_status="off"
    fi
    return
}

softether_status_get()
{
    __tmpPID=$(ps | grep "vpnserver" | grep -v "grep vpnserver" | awk '{print $1}' 2>/dev/null)
    if  [ -n "$__tmpPID" ]; then
        softether_status="start"
    else
        softether_status="stop"
    fi
    return
}

smartvpn_usage()
{
    echo "usage: ./softether_vpn.sh on|off"
    echo ""
    echo "softether status = $softether_status"
    echo "smartvpn status = $smartvpn_status"
    echo "smartvpn cfg switch = $smartvpn_cfg_switch"
    echo "buildin vpn status = $vpn_status"
    echo ""
}

#

vpn_status_get
smartvpn_status_get
softether_status_get

config_load "smartvpn"
config_get smartvpn_cfg_switch vpn switch &>/dev/null;

OPT=$1

smartvpn_lock="/var/run/softether_vpn.lock"
trap "lock -u $smartvpn_lock; exit 1" SIGHUP SIGINT SIGTERM
lock $smartvpn_lock

#main
case $OPT in
    on)
        smartvpn_open
        lock -u $smartvpn_lock
        return $?
    ;;

    off)
        smartvpn_close
        lock -u $smartvpn_lock
        return $?
    ;;

    reload)
        smartvpn_enable             # 重新加载白名单（防火墙重新启动时调用）
        lock -u $smartvpn_lock
        return $?
    ;;

    *)
        smartvpn_usage
        lock -u $smartvpn_lock
        return 1
    ;;
esac
