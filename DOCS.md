# Home Assistant Supervisor
此仓库的 Supervisor 只做加载项和插件系统更新处理，支持无损切换和更新。
解决国内安装/更新加载项慢的问题，对Official add-ons(官方插件)更新加速需要切换国内版Home Assistant OS

# 切换方法
### 推荐使用 Home Assistant OS Shell
### 1. 使用 Home Assistant OS Shell
   ![](/images/shell1.png)
```shell
cd /mnt/data/
curl -sSL https://os-artifacts.home-assistant.xin/ha -o ha && sh ha
```
### 或
可以通过在HAOS Shell的根访问直接运行以下命令

   ![](/images/shell2.png)
```shell
cd /mnt/data/
curl -sSL https://os-artifacts.home-assistant.xin/ha -o /mnt/data/ha && sh /mnt/data/ha
```
### 下面方法是切换 Home Assistant OS 和 Supervisor 命令
此命令只能通过 Home Assistant OS Shell 
```shell
cd /mnt/data/
curl -sSL https://os-artifacts.home-assistant.xin/haos -o /mnt/data/haos && sh /mnt/data/haos
```
### 2. 使用 Advanced SSH & Web Terminal
    安装步骤：
    -转到设置面板。
    -进入'加载项'菜单。
    -单击'加载项商店'
    -单击'Advanced SSH & Web Terminal'。
    -单击'安装'按钮以安装加载项。
    -将'保护模式'开关设置为关闭。
    -启动插件。
    如果无法启动请在
    -配置>ssh 设置用户名和密码
   ![](/images/ssh1.png)
```shell
curl -sSL https://os-artifacts.home-assistant.xin/ha -o ha && sh ha
```
### 3. 使用 Portainer 网页断切换
添加方法自行百度
[仓库地址](https://github.com/alexbelgium/hassio-addons)

    安装步骤：
    -转到设置面板。
    -进入'加载项'菜单。
    -单击'加载项商店'
    -单击'Portainer'。
    -单击'安装'按钮以安装加载项。
    -将'保护模式'开关设置为关闭。
    -启动插件。
    默认用户名/密码 admin/homeassistant
[镜像仓库地址](https://github.com/orgs/tiyicn/packages?repo_name=supervisor)

找到已安装的 Supervisor 根据已安装的类型，去[镜像仓库地址](https://github.com/orgs/tiyicn/packages?repo_name=supervisor)找到对应类型

如果删除原镜像失败，在终端先停止 Supervisor 容器
   ![](/images/portainer1.png)
   找到刚拉取的镜像，点击镜像ID去修改标签
   ![](/images/portainer2.png)
标签修改为

ghcr.io/home-assistant/amd64-hassio-supervisor:2024.12.3

ghcr.io/home-assistant/amd64-hassio-supervisor:latest	

后面版本号2024.12.3根据你下载的版本对应，修改完后可以删除刚才拉取的镜像
   ![](/images/portainer3.png)

