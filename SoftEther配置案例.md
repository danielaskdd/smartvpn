#### SoftEther配置案例

##### 目标

* 根据域名白名进行智能路由：不需要加速的域名从原路径访问，需要加速的域名从海外出口访问。
* 对于需要海外加速的域名：部分香港访问比较快的域名经香港出口访问，其余从美国出口访问。
* 通过ssh登录不具有公网ip的路由器

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
	142.250.0.0/16/192.168.30.2		 142.250.0~255.xxx   		  google	
  216.239.32.0/19/192.168.30.2	 216.239.32~63.xxx      youtube
  216.58.192.0/18/192.168.30.2   youtube
  
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
  17.253.0.0/16/192.168.30.2       17.253.0~255.xxx 	  # iclould.com 
  23.220.192.0/18/192.168.30.2
  developer.apple.com
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
```

##### 其它说明

* 因SoftEther启用L2TP服务后会导致小米路由的VPN拨号功能失效，从而无法启用小米路由上的智能路由功能。如确是需要把SoftEther安装在小米路由上，需要废弃小米路由做好的智能路由功能，改为自己编写脚本实现。做法简单描述如下：

```
1. 配置SoftEther，创建虚拟好GZHUB，级联到香港的HKHUB上
2. 把GZHUB桥接到本地网络上（桥接p网卡为tap_gzhub)
3. 把SoftEther开启脚本 vpnserver 拷贝到 /etc/init.d 目录下
4. 把智能路由启动脚本softether_vpn.sh拷贝到/usr/sbib目录，重启路由器即可

说明：
1. softether_vpn.sh可以收工开启和关闭智能路由
2. vpnserver启动脚本有tap网卡的ip和路由设置，需要根据本地网络的ip进行修改方可使用
```

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

