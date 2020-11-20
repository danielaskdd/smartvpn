小米路由VPN智能分流配置
---

以下是**小米路由器2(1TB 硬盘版)**VPN智能分流的配置分享。家庭或公司科学上网需要用到VPN智能分流，仅让需要通过加速的外网流量走VPN通道，其余访问都还是继续走正常通道。小米路由的智能VPN分流可以按服务地址来选择哪些流量是从VPN出去的。其余的就按正常方式访问。只能分流依赖于一个需要分流的白名单。这里有一个实用的白名单，名单很长，不可能手工通过路由器的设置界面录入。因此需要开启路由器的开发模式，开启路由器上的ssh功能。开启ssh功能的方法网上有，这里就不赘述了。

#### 使用方法

proxy.txt 包含了一些需要分流的常用地址。你可以根据自己的需要添加一些自己需要的域名。开启小米路由的开发者模式，通过ssh访问小米路由。开启方法在小米官方有教程。把proxy.txt文件放在路由器的 /etc/smartvpn目录下，然后在路由器Web管理界面的“高级设置/VPN”中就可以看到这个清单了。此时断开VPN后从新链接就可以用了。

#### 国内个别网站访问偶尔会变慢

启动VPN智能分流后，小米路由的dnsmasq服务会把VPN连接的DNS服务器加入到父DNS清单中，与从宽带供应商中获得DNS一起承担域名解析任务。这是不合理的，因为这会导致不需要走VPN的域名会偶尔会使用VPN的DNS来解析，从而获得该域名的海外ip（如果该域名有为海外加速的话），从而导致网站访问偶尔会变得很慢。解决的方案是修改智能VPN的启动脚本，把海外DNS从配置中剔除。具体做法如下：

* 修改文件之前需要把磁盘挂载城可读写

```
mount -o remount, rw /   
```

* 修改 /usr/sbin/smartvpn.sh文件中的 dnsmasq_restart()函数，在函数中的 /etc/init.d/dnsmasq restart 命令前插入以下语句（把8.8.8.8换成VPN供应商返回DNS的ip地址）：

```
# remove DNS entry pushed by Softether
sed -i -e '/nameserver 8.8.8.8/d' /tmp/resolv.conf.auto
```

* 修改完成后需要回复磁盘为只读

```
mount -o remount, ro /
```

#### 如何确保正确访问谷歌DNS

小米路由默认通过8.8.8.8这个DNS解析白名单中的域名。如果您的DNS供应在VPN拨通之后想您推送的DNS中包括这个域名就还好，小米路由能够访问到没有经过污染的DNS，否则需要在白名单中强行添加一条ip设置，让小米路由能够访问到干净的8.8.8.8DNS：

```
# 以下设置在proxy.txt文件中已经包含，不要自己删除掉即可
8.8.0.0/16
```

#### 如何选择VPN供应商的问题

小米路支持接入的VPN仅支持PPP和L2TP两种，且L2TP还不支持共享密钥。这样的VPN供应商是不可能存活的。有需求的网友需要自己搭建VPN服务。在此建议自己在海外购买服务器来搭建，每月的运行成本也就100元左右。搭建服务器的时候注意，不能从大陆直接拨海外的VPN，这样你海外的服务器很快就会被封。解决的方案就是把VPN入口放在大陆，然后通过SoftEther与海外链接。由于国内访问海外自己购买的服务器是很难确保稳定的。理想的解决方案是在香港购买一台国内知名云服务商的服务器，让后通过绕道香港这个服务器再访问海外自己的服务器。绕道的方案当然也是通过万能的SoftEther了。国内知名云服务商的服务器是不能做VPN的，这个你懂的。当然，如果你是SoftEther的高手，还对个别最为常用且有对香港用户进行加速的网站走捷径，流量直接就从香港服务器短路出去了。当然这样的网站不能太多，否则就会被云服务器供应商发现了。只能说到这里了。

