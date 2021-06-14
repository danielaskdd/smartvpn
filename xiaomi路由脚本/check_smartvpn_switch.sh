#!/bin/sh

. /lib/functions.sh

# 放在crontab中，每分钟检查一次“智能VPN分流”开关，据此去启动或定制softether智能路由服务

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

#

smartvpn_status_get
softether_status_get
# vpn_status_get

echo "vpn_status_get = $smartvpn_status" > /tmp/check_smartvpn_switch.txt
echo "softether_status_get = $softether_status" >> /tmp/check_smartvpn_switch.txt

if [ $smartvpn_status == "on" ];
then
    if [ $softether_status == "start" ];
    then

        config_load "smartvpn"
        config_get smartvpn_cfg_switch vpn switch &>/dev/null;
        echo "smartvpn_cfg_switch = $smartvpn_cfg_switch" >> /tmp/check_smartvpn_switch.txt

        # 根据智能VPN路由开关来控制SoftEther服务的起停
        if [ $smartvpn_cfg_switch == "0" ];
        then
            echo "Stopping softether smartvpn ..." >> /tmp/check_smartvpn_switch.txt
            touch /tmp/vpnserver_stopping
            /etc/init.d/vpnserver stop
        fi
    fi
else
    if [ $softether_status == "stop" ];
    then
        config_load "smartvpn"
        config_get smartvpn_cfg_switch vpn switch &>/dev/null;
        echo "smartvpn_cfg_switch = $smartvpn_cfg_switch" >> /tmp/check_smartvpn_switch.txt

        # 根据智能VPN路由开关来控制SoftEther服务的起停
        if [ $smartvpn_cfg_switch == "1" ];
        then
            # start only when softether service has been started once
            if [ -f /tmp/vpnserver_start_once ]; then
                echo "Starting softether smartvpn ..." >> /tmp/check_smartvpn_switch.txt
                touch /tmp/vpnserver_starting
                /etc/init.d/vpnserver start
            fi
        fi
    fi
fi
