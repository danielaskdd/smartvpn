#### SoftEther配置案例

##### 目标

* 根据域名白名进行智能路由
* 部分香港访问比较快的域名经香港服务器访问
* 其它域名白名单从美国服务器访问

##### 美国SoftEther配置

* 虚拟Hub：VPN

```
虚拟Hub的SecureNAT配置：
	虚拟主机ip：192.168.30.1/255.255.255.0
	开启虚拟NAT（作为美国互联网出口）
	关闭DHCP
```

##### 香港SoftEther配置

* 虚拟Hub：VPN

```
虚拟Hub的SecureNAT配置：
	虚拟主机ip：192.168.30.2/255.255.255.0
	开启虚拟NAT（作为香港互联网出口） 
	关闭DHCP

级联连接
	与美国个SoftEther服务器的VPN（虚拟Hub）连接
```

* 虚拟Hub：HKHUB

```
虚拟Hub的SecureNAT配置：
	虚拟主机ip：192.168.29.9/255.255.255.0
	关闭虚拟NAT
	开启DHCP，默认网关192.168.29.1，DNS1为8.8.8.8，DNS2为1.1.1.1
```

* 三层交换：HKRT

```
虚拟接口：
	连接HKHUB：192.168.29.1/255.255.255.0
	连接VPN：192.168.30.3/255.255.255.0

路由表：（让经香港访问比较快的ip使用192.168.30.2作为出口）
	设置默认路由为192.168.30.1	
  == 香港出口DNS路由
  1.1.1.0/24/192.168.30.2
  1.0.0.0/24/192.168.30.2

  == GitLab香港路由
  172.65.251.0/24/192.168.30.2	 						gitlab.com

  == Google香港路由
  172.217.160.0/19/192.168.30.2    172.217.160~191.xxx    google
  172.217.0.0/19/192.168.30.2      172.217.0~31.xxx       youtube
  216.58.192.0/19/192.168.30.2     216.58.192~223.xxx     gmail youtube
  216.239.32.0/19/192.168.30.2	 216.239.32~63.xxx      youtube

  == 文学城香港路由
  35.190.0.0/17/192.168.30.2       35.190.0~127.xxx
  35.201.64.0/22/192.168.30.2      35.201.64~67.xxxx

  == Twitter香港路由
  104.16.0.0/19/192.168.30.2       104.16.0~31.xxx
  104.244.40.0/21/192.168.30.2     104.244.40~47.xxx
  108.177.97.0/24/192.168.30.2
  151.101.0.0/16/192.168.30.2
  152.199.32.0/19/192.168.30.2     152.199.32~63.xxx      abs.twimg.com

  == Apple香港路由
  17.91.8.0/21/192.168.30.2        17.91.8~15.xxx
  17.91.64.0/19/192.168.30.2       17.91.64~95.xxx
  17.248.128.0/18/192.168.30.2     17.248.128~191.xxx   #
  17.250.120.0/21/192.168.30.2     17.250.120~127.xxx
  17.253.0.0/16/192.168.30.2       17.253.0~255.xxx 	  # iclould.com developer.apple.com
  23.7.192.0/18/192.168.30.2       23.7.192~255.xxx     #
  23.198.112.0/20/192.168.30.2     23.198.112~127.xxx
  23.198.128.0/20/192.168.30.2     23.198.128~143.xxx
  184.87.132.0/24/192.168.30.2
  185.199.108.0/22/192.168.30.2  185.159.108~111.xxx

  == 其它香港路由(未知域名)
  13.107.246.0/24/192.168.30.2
  64.233.188.0/24/192.168.30.2
  117.18.232.0/24/192.168.30.2
  192.229.237.0/24/192.168.30.2
  101.32.10.0/24/192.168.30.2（香港腾讯云）
  124.156.158.0/24/192.168.30.2（香港腾讯云）
```

##### 内地SoftEther配置（与小米路由在同一个局域网）

* 虚拟Hub：HKHUB

```
关闭虚拟Hub的SecureNAT：
级联连接
	与香港SoftEther服务器的HKHUB（虚拟Hub）连接
```

* IPsec/L2TP配置

```
没有加密的RAW L2TP（小米路由不支持IPsec）
```

##### 小米路由配置

* 添加一个L2TP类型的VPN连接，连接内地SoftEther的HKUB（虚拟Hub）
* 把域名白名单文件proxy.txt拷贝到 /etc/smartvpn目录

* 修改智能路由启动脚本 /usr/sbin/gensmartdns.sh，把从香港访问比较快的域名的DNS改为使用1.1.1.1

```
在最后添加下以下语句：(把某些域名改为通过香港DNS访问，以获得香港ip）
    sed -i \
      -e '/server=\/google.com\// s/8.8.8.8/1.1.1.1/' \
      -e '/server=\/googlevideo.com\// s/8.8.8.8/1.1.1.1/' \
      -e '/server=\/youtube.com\// s/8.8.8.8/1.1.1.1/' \
      -e '/server=\/youtu.be\// s/8.8.8.8/1.1.1.1/' \
      -e '/server=\/twimg.com\// s/8.8.8.8/1.1.1.1/' \
      -e '/server=\/twitter.com\// s/8.8.8.8/1.1.1.1/' \
      -e '/server=\/developer.apple.com\// s/8.8.8.8/1.1.1.1/' \
      -e '/server=\/icloud.com\// s/8.8.8.8/1.1.1.1/' \
      $domain_file
```

* 修改智能路由启动脚本 /usr/sbin/smartvpn.sh，把VPN推送过来的DNS从DNS清单中剔除

```
在函数中的 /etc/init.d/dnsmasq restart 命令前插入以下语句：

# remove DNS entry pushed by Softether
sed -i -e '/nameserver 8.8.8.8/d' /tmp/resolv.conf.auto
sed -i -e '/nameserver 1.1.1.1/d' /tmp/resolv.conf.auto

注：启动VPN智能分流后，小米路由的dnsmasq服务会把VPN连接的DNS服务器加入到父DNS清单中，与从宽带供应商中获得DNS一起承担域名解析任务。这是不合理的，因为这会导致不需要走VPN的域名会偶尔会使用VPN的DNS来解析，从而获得该域名的海外ip（如果该域名有为海外加速的话），从而导致网站访问偶尔会变得很慢。
```

* 开放Wan和GZHUB网段访问SSH服务

```
在/etc/config/firewall文件添加一条规则：
config rule                                                                
	option name 'Allow-wan-ssh'                                         
	option src 'wan'                                                    
	option proto 'tcp'                                                  
	option dest_port '22'                                               
	option target 'ACCEPT'	
```

* 让小米路由访问GZHUB网段

```
如果SoftEther与小米路由不是同一台设备，通过VPN连接GZHUB访问SSH服务需要让小米路由能够访问GZHUB网段。修改智能路由启动脚本 /usr/sbin/smartvpn.sh，把HKHUB网段添加到路由表中。
* 在smartvpn_open()中的ip route flush table cache语句前添加一下命令：
	ip route add 192.168.29.0/24 dev l2tp-vpn
* 在smartvpn_close()中的ip route flush table cache语句前添加一下命令：
	ip route del 192.168.29.0/24 dev l2tp-vpn

如果SoftEher安装在小米路由上，则需要通过一下方法直接让小米路由访问GZHUB：
* 配置SoftEther添加本地网桥：GZHUB 桥接 gzhub (gzhub是一个新创建的tap设备）
* 修改SoftEther的启动脚本/opt/etc/init.d/S50vpnserver， 启动后添加
    sleep 5
    ip addr add 192.168.29.3 dev tap_gzhub   # 小米路由通过VPN访问的ip
    ip route add 192.168.29.0/24 dev tap_gzhub
由于小米路由添加与SoftEther的VPN时需要使用192.168.29.3这个ip（不能使用路由器LAN口的ip）
```

##### 其它说明

* SoftEther安装在路由器上时不被路由器本身直接访问到，需要把SoftEther的Hub桥接到路由器上的一个Tap网卡上。SoftEther启动后需要给Tap网卡添加ip，并设置路由。小米路由添加VPN拨号时使用Tap网卡的ip，而不是路由器LAN口上的ip。
* 建议SoftEhter监听端口不要使用安装后的默认配置（避免被攻击或监管机构扫描）
* 小米路R2D可以通过一下方式让/usr/sbin目录变为可以修改

```
mount -o remount, rw /       # 让路由器文件可写
mount -o remount, ro /       # 恢复路由器文件只读
```

* 小米路由R3D/R3P无法简单地把/usr/sbin变为可以修改，需要把该目录拷贝到可以读写的卷中，让后覆盖掉原来的目录

```
拷贝/usr目录到可以读写的卷中
	cp -R -p /usr /userdisk
在 /etc/rc.local的开头中添加一下语句：（启动的时候把/usr目录覆盖为刚刚拷贝的）
	mount -o bind /userdisk/usr /usr
```

