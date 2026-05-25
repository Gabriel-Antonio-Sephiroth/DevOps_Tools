# Apache Doris 存算一体集群 - 通过 ansible 剧本自动化部署

> 自动化搭建 Doris 集群环境，案例使用 ansible 剧本部署通过三台实验机搭建一主两从的 Doris 集群，配置如下:
>
> ```markdown
> # 实验机清单
> 控制端：
> master：控制节点
> 	-> 172.25.195.120   # 2cpu,2G内存, ansible控制端
> 被控端Doris一体化节点:
> doris1: 主节点
> 	-> 172.25.195.121	# 8CPU,16G内存
> doris2: 从节点1
> 	-> 172.25.195.122	# 8CPU,16G内存
> doris3: 从节点2
> 	-> 172.25.195.123	# 8CPU,16G内存
> # 系统使用rockylinux10.1，Doris使用4.1.0版本
> ```
> 
>官方文档：
> 
>[Apache Doris 简介 - Apa实时终端输出或历史命令记录che Doris](https://Doris.apache.org/zh-CN/docs/gettingStarted/what-is-apache-Doris)
> 
>参考站内两位大佬案例：
> 
>[Apache Doris 01|集群部署及BE启动遇到问题记录_check fd number failed, error: internal error: fil-CSDN博客](https://blog.csdn.net/longqiancao1/article/details/117665789?utm_medium=distribute.pc_relevant.none-task-blog-2~default~baidujs_utm_term~default-0-117665789-blog-144068911.235^v43^pc_blog_bottom_relevance_base8&spm=1001.2101.3001.4242.1&utm_relevant_index=2)
> 
>[【大数据系列】一、Apache Doris集群部署-CSDN博客](https://blog.csdn.net/qq_54375572/article/details/144068911?ops_request_misc=%7B%22request%5Fid%22%3A%2255418f9168360abcd2d922711c9841be%22%2C%22scm%22%3A%2220140713.130102334.pc%5Fall.%22%7D&request_id=55418f9168360abcd2d922711c9841be&biz_id=0&utm_medium=distribute.pc_search_result.none-task-blog-2~all~first_rank_ecpm_v1~rank_v31_ecpm-4-144068911-null-null.142^v102^pc_search_result_base4&utm_term=DorisFE集群&spm=1018.2226.3001.4187)
> 
>Doris 官方 tar 包下载链接：
> 
>[Apache Doris - Download | Easily deploy Doris anywhere - Apache Doris](https://Doris.apache.org/zh-CN/download)

## **一、概念补充**

Doris 存算一体架构分两种进程：FE 和 BE

​	Frontend (FE)：主要负责接收 用户 SQL 请求 (通过 MySQL 协议)、查询解析和规划、元数据管理以及节点管理

​	Backend (BE)：主要负责执行 数据存储、查询计划分布式计算和结果集生成，数据以片 (Shard) 为单位多副本存储

​	FE 处理复杂逻辑需要多线程等符合 Java 生态而 BE 需要密集的底层操作计算 C++ 更适合所以出现了架构图中既有 Java 又有C++ 的多语言选择，但 FE 是 Java 进程需要 JDK 编译而 BE 是编译好的二进制文件又有 Linux 默认安装的运行库支持，基于此案例部署中只配置 Java 的环境变量。因兼容 MySQL 通信协议，所以支持通过 MySQL 客户端及其各种可视化工具链接 Doris



## 二、系统搭建与环境准备

### 系统规划

| 主机名         | 硬件性能   | 节点功能         | 组件服务          |
| -------------- | ---------- | ---------------- | ----------------- |
| 172.25.195.120 | 2C 2G 40G  | master（控制端） | Frontend, Backend |
| 172.25.195.121 | 8C 16G 40G | slave（被控端）  | Frontend, Backend |
| 172.25.195.122 | 8C 16G 40G | slave（被控端）  | Frontend, Backend |
| 172.25.195.123 | 8C 16G 40G | slave（被控端）  | Frontend, Backend |

创建对应的虚拟机，案例使用阿里云ECS实例以及`Rocky Linux 9.5`镜像资源部署，案例中doris会从官方wget获取，版本为`4.1.0`，使用本地虚拟机需要注意更改ip地址并初始化虚拟机环境

Doris 所有进程依赖 java 根据官方文档说明，以 3.0 版本为界限，低于 3.0 版本使用 JDK1.8，高于 3.0 使用 JDK17。案例使用 4.1.0 版本搭配 JDK17

### 配置 ssh 免密登录

```shell
# 非交互式生成无密码密钥
ssh-keygen -t ed25519 -f ~/.ssh/id_ed25519 -N "" -q
# 传输密钥
for i in 121 122 123; do
    sshpass -p "your_password" ssh-copy-id -o StrictHostKeyChecking=no root@172.25.195.$i
done
```

### 搭建 ansible 节点环境

```shell
## 修改 ansible 全局配置文件
# 创建 ansible 工作目录
mkdir /ansible /ansible/roles /ansible/collections

# ansible.cfg 脚本中需要删除#注释，否则会报错
echo '
[defaults]
inventory = ./inventory               # 指定 inventory 清单路径
roles = ./roles                       # 指定 roles 角色路径
collections = ./collections           # 多个目录之间使用":"冒号分隔
remote_user = root                    # 远程用户，部署时改为实际环境用户名
private_key_file = ~/.ssh/id_ed25519  # 指定生成的 SSH 私钥
host_key_checking = False             # 禁用 SSH 主机密钥验证（类似 StrictHostKeyChecking=no）

[privilege_escalation]
become = True                         # 启用 sudo 提权
become_method = sudo                  # 提权方式
become_user = root                    # 提权用户
become_ask_pass = False               # 是否需要密码
' > /ansible/ansible.cfg

# inventory(部署时修改为实际IP地址)
echo '
[doris]
doris1 ansible_host=172.25.195.121
doris2 ansible_host=172.25.195.122
doris3 ansible_host=172.25.195.123
' > /ansible/inventory

# 测试结果
tree /ansible; ansible doris -m ping
```

> 可能的报错原因如下
>
> ```bash
> # ansible.cfg 文件包含了#注释，因为 ansible 的配置文件解析器有时会对行内注释处理不佳，解决方法是确保#之后紧跟的是英文注释或直接换行
> [root@node091 ansible]# tree /ansible; ansible all -m ping
> tree /ansible; ansible doris -m ping
>  /ansible
>  ├── ansible.cfg
>  ├── collections
> ├── inventory
> ├── roles
> └── test_inventory
> 2 directories, 3 files
> [WARNING]: Unable to parse /ansible/inventory           # 指定 inventory 清单路径 as an inventory source
> [WARNING]: No inventory was parsed, only implicit localhost is available
> [WARNING]: provided hosts list is empty, only localhost is available. Note that the implicit
> localhost does not match 'all'
> [WARNING]: Could not match supplied host pattern, ignoring: doris
> 
> # AppStream 仓库提供了简易版的 ansible-core 但工具少只有70个包左右，要使用 ansible 社区的包需要启用 YUM 的 EPEL 仓库，我使用的阿里云 YUM 仓库镜像所以启用阿里云的 EPEL 仓库
> [root@node091 ansible]# dnf -y install ansible
> 上次元数据过期检查：0:32:44 前，执行于 2025年09月08日 星期一 10时20分55秒。
> 未找到匹配的参数: ansible
> 错误：没有任何匹配: ansible
> [root@node091 ansible]# dnf -y install https://mirrors.aliyun.com/epel/epel-release-latest-9.noarch.rpm
> 
> # python 版本不兼容
> [root@node091 ansible]# ansible doris -m ping
> [WARNING]: Unhandled error in Python interpreter discovery for host node92: unexpected output
> from Python interpreter discovery
> [WARNING]: sftp transfer mechanism failed on [192.168.7.92]. Use ANSIBLE_DEBUG=1 to see
> detailed information
> [WARNING]: scp transfer mechanism failed on [192.168.7.92]. Use ANSIBLE_DEBUG=1 to see
> detailed information
> [WARNING]: Platform unknown on host node92 is using the discovered Python interpreter at
> /usr/bin/python, but future installation of another Python interpreter could change this. See
> https://docs.ansible.com/ansible/2.9/reference_appendices/interpreter_discovery.html for more
> information.
> node92 | FAILED! => {
> "ansible_facts": {
>   "discovered_interpreter_python": "/usr/bin/python"
> }, 
> "changed": false, 
> "module_stderr": "Shared connection to 192.168.7.92 closed.\r\n", 
> "module_stdout": "[setupvars.sh] WARNING: Unsupported Python version 3.6. Please install one of Python 3.7 - 3.11 (64-bit) from https://www.python.org/downloads/\r\n[setupvars.sh] OpenVINO environment initialized\r\n\r\n{\"invocation\": {\"module_args\": {\"data\": \"pong\"}}, \"ping\": \"pong\"}\r\n", 
> "msg": "MODULE FAILURE\nSee stdout/stderr for the exact error", 
> "rc": 0
> }
> 
> #更多信息查看 ansible 详细日志，在 ansible 命令前添加 ANSIBLE_DEBUG=1
> ANSIBLE_DEBUG=1 ansible doris -m ping
> ```
> 

### 安装时间同步角色

```bash
# 安装系统角色
dnf list | grep roles
dnf -y install rhel-system-roles.noarch

# 验证安装
rpm -qa rhel-system-roles
ls /usr/share/ansible/roles

# 拷贝timesync角色(部署时修改为实际 ansible 安装路径)
cp -r /usr/share/ansible/roles/rhel-system-roles.timesync /ansible/roles/timesync  # 这里目标文件名与后续的NTP服务角色名同步

# 必要时查看说明文档
cat /usr/share/ansible/roles/timesync/README.md
```

### 扩展 mysql 模块

```bash
### 如果只安装 core 简易版需要扩展 mysql 模块，如果安装了社区包自带安装 mysql 模块可以跳过这一步
# 在ansible中添加mysql查询功能，添加参数-p指定目录，模块名ansible.community.mysql
ansible-galaxy collection install community.mysql -p /ansible/collections
ansible-galaxy collection list -p /ansible/collections | grep -C 3 community.mysql
# /ansible/collections/ansible_collections
Collection      Version
--------------- -------
community.mysql 4.1.0
```

<img src=".\images\社区mysql模块.png" alt="image-20260525033738031" style="zoom:80%;" />

### 配置集群 NTP 服务

Doris 源数据要求时间精度所有集群所有机器要进行时钟同步，避免因为时钟问题引发的元数据不一致导致服务出现异常

```yaml
vars:  # vars在hosts与tasks之间
  timesync:
    - hostname: 192.168.0.91  # 部署时IP修改为实际环境地址
      iburst: true
roles:
  - timesync  # 这里名称与 上一步安装时间同步角色后拷贝的目标文件名 相同，如果之前修改了名称这里也要同步修改
```



## 三、编写自动化部署剧本

### 剧本头以及变量声明

```yaml
  vars:
    doris_version: "4.1.0" # 声明安装的doris版本，根据实际情况修改
    download_url: "https://download.selectdb.com/apache-doris-{{ doris_version }}-bin-x64.tar.gz" # 指定官方下载地址
    download_dir: "/tmp/doris" # 下载doris临时地址
    tar_name: "apache-doris-{{ doris_version }}-bin-x64.tar.gz"
    unzip_name: "apache-doris-{{ doris_version }}-bin-x64"
    install_dir: "/usr/local" # 解压后的doris目标地址
    doris_name: "doris"
    fe_conf: "fe/conf/fe.conf"
    be_conf: "be/conf/be.conf"
    fe_http_port: 8030           	    # FE httpserver端口
    fe_rpc_port: 9020            	    # FE thriftserver端口
    fe_query_port: 9030          	    # FE mysqlserver端口
    fe_edit_log_port: 9010       	    # FE bdbje通信端口
    be_port: 9060                     # BE thriftserver端口
    be_webserver_port: 8040           # BE httpserver端口
    be_heartbeat_service_port: 9050   # BE 心跳检测端口
    be_brpc_port: 4021                # BE BRPC通信端口
    java_install: "java-17-openjdk-devel" # 声明java安装版本，按实际需求更改
    priority_networks: "172.25.195.0/24" # 指定网络环境，按实际需求更改
```



### 关闭 SWAP 分区

交换分区有两种关闭尽量使用热更新关闭方式，分别是修改 fstab 文件另一种是使用 swapoff 命令，前者重启生效后者临时生效

所以只检测 fstab 文件中 swap 是否被注释，通过标准输出不为空则注释包含 swap 的行确保分区在系统重启后不会自动启用，不论结果如何最后都使用 swapoff 命令关闭交换分区

>交换分区作为操作系统重要的一部分使用它的服务器基数绝对不少，我不明白为什么 Doris 要舍去它。查找攻略后个人觉得符合逻辑的原因：
>
>​	1. SWAP 分区主要的功能在于为内存提供临时存储空间，当系统访问这些数据时会将交换分区的数据再加载到内存中，而问题就在从硬盘到内存的读取效率上即便是ddr5的固态这两者差异也非常大，分布式 Doris 不同于 MySQL 对延迟容忍度较高，所以 **I/O 延迟**是导致问题的根本原因。比如查询时某个内存页数据暂存到 SWAP 分区或节点查询响应变慢拖累整个分布式查询，那效率会从亚毫秒级退化到百毫秒甚至秒级进而引发副本同步超时、查询超时、节点假死等状态，严重甚至会导致雪崩效应
>
>​	2. BE进程的高内存特性，BE（Backend）节点本身就是一个内存密集型进程，需要加载大量数据到内存中进行计算，因此很容易导致内存溢出进而成为OOM Killer的“目标”。，两者资源同时用尽后内核的 OOM Killer 机制会选择高消耗影响小的目标打分后杀死高分进程释放内存，那 BE 进程被杀死可能会导致数据副本丢失、查询失败等问题，甚至集群不可用。所以需要独占物理内存，对扩容、优化等及时响应

```yaml
# 检查fstab文件中是否包含交换分区
- name: check if swap is configured in fstab
  shell: grep -v "^#" /etc/fstab | grep -i swap || true	# 过滤注释并查找包含swap的行，只要输出结果不在乎返回码所以强制返回0
  register: swap_in_fstab # 将 shell 命令输出结果(stdout、stderr 和 rc 返回码)保存到变量中
  changed_when: false # 设置显式声明，防止因为返回码等导致ansible误判

- name: comment out swap in fstab
  replace:
    path: /etc/fstab
    regexp: '^([^#].*swap.*)'
    replace: '# \1'
  when: swap_in_fstab.stdout != ""  # 变量的标准输出不为空，说明 shell 命令的执行结果包含交换分区

- name: turn off swap (always execute)
  command: swapoff -a # 无论是否fstab中是否含有SWAP，都执行一边关闭交换分区
  ignore_errors: yes # 即使失败也不会中止任务
```

### 安装 JDK 配置环境变量

必须安装devel，如果只安装openjdk后续启动服务时会报错，因为openjdk只包含jre，devel内包含了jdk。修改 `/etc/profile` 文件**不会立即生效**需要手动启动 source，在安装前先检查是否安装，若安装跳过直接设置环境变量

> 注意：最高只能安装java17，java21以上版本太高启动doris会报错

```yaml
# 执行前检查一遍是否已经安装
- name: Check if java is installed
  command: java --version
  register: java_check

# 根据检查结果决定是否安装，根据实际需求在开头设置好变量到底是17还是1.8
- name: install jdk
  yum:
    name: {{ java_install }}
    state: present
  when: java_check.rc != 0

# 
- name: set JAVA_HOME env
  block:
    - name: Get node for JAVA_HOME path
      shell: dirname $(dirname $(readlink -f $(which java)))
      register: java_home_path
      changed_when: false

    - name: set JAVA_HOME into /etc/profile
      lineinfile:
        path: /etc/profile
        line: 'export JAVA_HOME={{ java_home_path.stdout }}'
        insertafter: EOF
        state: present

    - name: set JAVA_HOME into PATH
      lineinfile:
        path: /etc/profile
        line: 'export PATH=$JAVA_HOME/bin:$PATH'
        insertafter: EOF
        state: present
```

### 安装PyMySQL包

由于doris使用mysql通讯协议，并且ansible是由python编写的，所以需要安装Python的MySQL库才能正常运行

```yaml
- name: Install PyMySQL on target hosts
  yum:
    name: python3-PyMySQL
    state: present
```

### 关闭系统透明大页

```yaml
- name: Configure Transparent Huge Pages settings
  blockinfile:  # 文件不存在默认不会自动创建，需要添加参数
    path: /etc/rc.d/rc.local
    block: |
      echo madvise > /sys/kernel/mm/transparent_hugepage/enabled
      echo madvise > /sys/kernel/mm/transparent_hugepage/defrag
    marker: "# {mark} ANSIBLE MANAGED BLOCK - THP CONFIG"  # 自定义marker标记，避免命令重复插入
    insertafter: EOF  # 匹配行之后嵌入位置，EOF末尾嵌入
    create: yes  # 如果文件不存在自动创建
    mode: '0755'  # 同时设置权限（Ansible 2.3+ 支持）
- name: Enable rc-local service
  systemd:
    name: rc-local
    enabled: yes
    state: started
```

### 修改系统内核参数配置

>虚拟内存与交换分区的区别：
>没有交换分区时系统仍可以使用虚拟内存，虚拟内存是一种概念、机制，而交换分区是实现方式之一，两者是概念与实现的从属关系
>
>​	1. 交换分区本质是物理内存在物理硬盘的扩展，其核心作用是扩展内存以减缓压力，内核将不活跃的堆、栈内存页等移动到交换分区(物理硬盘)但频繁的交换导致性能下降不符合doris设计初衷
>
>​	2. 虚拟内存是一种抽象机制，使用分页或分段技术将物理内存和硬盘空间结合，为进程虚拟连续的内存空间，避免直接访问物理内存，仅将需要的代码数据加载到物理内存而其余数据保存在硬盘，这期间有特殊的保护机制防止进程越界访问

```yaml
# 配置内核变量参数
- name: Configure vm.max_map_count
  lineinfile:  # 官方文档中要求虚拟内存区域至少为 2000000
    path: /etc/sysctl.conf
    line: "vm.max_map_count = 2000000"
    regexp: "^\\s*vm\\.max_map_count"  # 指定正则，匹配是否已存在，存在则替换否则文件末尾追加，其中"\\s"表示任意空白字符(制表符、空格等)>=0

- name: Configure tcp_abort_on_overflow
  lineinfile:  # 确保网络连接溢出时自动重置新连接
    path: /etc/sysctl.conf
    line: "net.ipv4.tcp_abort_on_overflow = 1"
    regexp: "^\\s*net\\.ipv4\\.tcp_abort_on_overflow"

# 重载内核配置
- name: apply settings
  command: sysctl -p  # 立刻生效
```

### 确保 CPU 不使用省电模式（可省略跳过）

```yaml
- name: set CPU to performance mode if supported
  shell: |
    if [ -d /sys/devices/system/cpu/cpu0/cpufreq ]; then
      echo performance | tee /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor
      echo "CPU governor set to performance"
    else
      echo "CPUFreq not supported on this system, skipping"
      exit 0
    fi
  args:
    executable: /bin/bash
  register: governor_set
  changed_when: "'performance' in governor_set.stdout"
```

### 增加系统最大文件句柄数

```yaml
- name: Configure nofile limits
  blockinfile:
    path: /etc/security/limits.conf
    marker: "# {mark} ANSIBLE MANAGED BLOCK - FILE HANDLE LIMITS"
    block: |
      * soft nofile 1000000
      * hard nofile 1000000
    insertafter: EOF
```

### 检查端口占用情况

只有在首次安装时检查端口占用情况，防止安装失败重复执行时有未暂停的服务占用端口

```yaml
# 统一端口冲突检查（仅首次安装时）
- name: Check all Doris port conflicts
  wait_for:
    port: "{{ item }}"
    host: "{{ ansible_host }}"
    state: absent
    timeout: 5
  loop:
    - "{{ fe_http_port }}"
    - "{{ fe_rpc_port }}"
    - "{{ fe_query_port }}"
    - "{{ fe_edit_log_port }}"
    - "{{ be_port }}"
    - "{{ be_webserver_port }}"
    - "{{ be_heartbeat_service_port }}"
    - "{{ be_brpc_port }}"
  register: port_check_results
  ignore_errors: true
  changed_when: false
  when: not doris_exist.stat.exists

# 提示报错细节
- name: Fail if any Doris port is in use
  fail:
    msg: |
      Port conflict detected on {{ ansible_host }}:
      {% for result in port_check_results.results %}
      {% if result is failed %}
      - Port {{ result.item }} is already in use
      {% endif %}
      {% endfor %}
  when: not doris_exist.stat.exists and (port_check_results.results | select('failed') | list | length > 0)

```

### 安装并部署Doris集群

在部署的过程中 Doris 解包后默认会在根目录下附带 meta 目录用于存储集群元数据，本次部署不采用软连接直接使用附带目录对元数据路径不作修改。官方文档中不建议在生产环境中将元数据路径放在根目录下最重要的原因可能是 **I/O竞争** ，因为根目录通常与操作系统、或其它应用共享硬盘，元数据高频读写（如DDL操作、事务日志同步）会导致硬盘 I/O 争用，影响集群稳定性

直接通过get_url模块获取官方发布的 tar 包，通过被控节点各自下载并解压

> 注意：如果是内网环境通过配置proxy才能访问外网时，ansible的get_url会超时，因为没有走proxy代理，需要手动执行wget走proxy代理下载；或者修改剧本从主控节点上获取doris再分发给各个节点

```yaml
# 检查tar包是否存在，避免二次执行时重复下载
- name: check if tar_pkg of doris is exist
  stat:
    path: "{{ download_dir }}/{{ tar_name }}"
  register: tar_exist

# 检查解压后的doris文件是否存在，避免二次执行时重复解压
- name: check if unzip of doris is exist
  stat:
    path: "{{ install_dir }}/{{ doris_name }}/{{ fe_conf }}"
  register: doris_exist

# 若tar包不存在并且doris目录不存在时，下载doris，避免二次执行重复下载
- name: download Apache Doris
  get_url:
    url: "{{ download_url }}"
    dest: "{{ download_dir }}/{{ tar_name }}"
    mode: '0644'
    timeout: 300
  register: download_result
  when: not tar_exist.stat.exists and not doris_exist.stat.exists # 确保执行失败后复用剧本时不用重复下载

# 若doris文件检测步骤为真，执行解压，避免二次执行时重复解压
- name: use tar module to unzip
  ansible.builtin.unarchive:
    src: "{{ download_dir }}/{{ tar_name }}"
    dest: "{{ install_dir }}"
    remote_src: yes
    owner: "{{ ansible_user | default('root') }}"
    group: "{{ ansible_user | default('root') }}"
    mode: '0755'
    creates: "{{ install_dir }}/{{ doris_name }}" # 如果doris目录存在跳过解压
  register: unzip_result
  when: not doris_exist.stat.exists # 解压时文件不存在

# 若doris文件检测步骤为真并且解压流程未跳过，说明解压成功，开始重命名文件
- name: rename unzip dir to doris
  shell: |
    mv -f {{ install_dir }}/{{ unzip_name }} {{ install_dir }}/{{ doris_name }}
  register: rename_result
  when: not doris_exist.stat.exists and unzip_result is not skipped # 确保解压成功

- name: set dir permissions
  file:
    path: "{{ install_dir }}/{{ doris_name }}"
    owner: "{{ ansible_user | default('root') }}"
    group: "{{ ansible_user | default('root') }}"
    mode: '0755'
    recurse: no
  when: not doris_exist.stat.exists and rename_result is not skipped and rename_result.rc == 0 # 确保重命名成功
```

> ### 传输、解压和删除 tar 包
>
> 若确实无法实时获取到doris官方tar包，需要提前准备好tar包并分发给各个节点
>
> `synchronize` 传输模块，**并行**向所有目标主机传输文件，在行为上不同于 copy、file，当被控端目标路径不存在会报错，并且基于 `rsync` 协议实现高效的**增量文件同步**更适合传输大型文件，如`"/path/not/exist" failed: No such file or directory`
>
> `unarchive` 解压模块，在每台主机任务**串行**，但不同主机之间**并行**，模块本身会返回成功或失败，也不需要额外的失败检查
>
> 每台机器的解压是独立的，Ansible 会并行等待所有主机完成。所以当前这一步的逻辑为：首先检查被控端是否含有tar包，如果256码值一样跳过传输文件直接解压，如果码值不一样覆盖传输；反之没有tar包查看关键主程序是否存在，存在跳过解压步骤执行后续任务，不存在执行传输并解压，如果解压失败ansible会报错停止不执行后续删除tar包任务，如果解压成功删除tar包
>
> ```yaml
> # 在剧本头部vars中添加一个路径变量
> src_dir: "/ansible/package"
> 
> # 检测被控端 tar 包是否存在(防止脚本失败后二次执行重复传输)
> - name: check if tar package already exists on target
>   stat:
>     path: "{{ download_dir }}/{{ tar_name }}"
>   register: tar_exists # tar 包是否存在
> 
> # 如果 tar 包已存在，则执行 block 块验证 sha256 值
> - name: verify tar package checksum if exists
>   block:
>     - name: get sha256 checksum of existing tar
>       shell: sha256sum "{{ download_dir }}/{{ tar_name }}" | awk '{print $1}' # 获取文件的sha256值
>       register: existing_sha256 # 存储文件的sha256值
>       changed_when: false
>     - name: validate checksum
>       fail:
>         msg: "Existing tar package checksum does not match expected value"
>       when: existing_sha256.stdout != expected_sha256 # 对比文件sha256值
>   when: tar_exists.stat.exists
> 
> # 如果 tar 包不存在或者存在但哈希码不同，执行传输 tar 包，否则跳过该模块
> - name: copy tar package (only if not exists or checksum mismatch)
>   block:
>     - name: copy tar package from control node
>       synchronize:
>         src: "{{ src_dir }}/{{ tar_name }}"
>         dest: "{{ download_dir }}/{{ tar_name }}"
>         # 以下为可选参数
>         mode: push                   # 默认就是push模式 (从控制节点推送到目标主机)
>         rsync_opts:                  # 自定义rsync参数
>           - "--chmod=644"            # 设置文件权限为644
>           - "--times"                # 保留文件时间戳
>       delegate_to: localhost         # 显式声明同步方向 (可省略)
>   when: not tar_exists.stat.exists or (tar_exists.stat.exists and existing_sha256.stdout != expected_sha256)
> 
> # 校验 tar 包，该模块执行条件与 synchronize 模块一致，确保不会重复校验降低效率
> - name: verify tar package checksum after copy
>   block:
>     - name: get sha256 checksum of copied tar
>       shell: sha256sum "{{ download_dir }}/{{ tar_name }}" | awk '{print $1}'
>       register: copied_sha256
>       changed_when: false
>     - name: validate checksum
>       fail:
>         msg: "Copied tar package checksum does not match expected value"
>       when: copied_sha256.stdout != expected_sha256
>   when: not tar_exists.stat.exists or (tar_exists.stat.exists and existing_sha256.stdout != expected_sha256)
> 
> # 检查关键文件是否存在
> - name: Verify extracted files
>   stat:
>     path: "{{ install_dir }}/{{ doris_name }}/fe/bin/start_fe.sh"    # 检查关键文件如果存在跳过解压
>   register: extracted_files
> 
> # 关键文件不存在，解压 tar 包
> - name: unarchive tar package (if not already extracted)
>   unarchive:
>     src: "{{ download_dir }}/{{ tar_name }}"
>     dest: "{{ install_dir }}"
>     remote_src: yes
>     #extra_opts: "--strip-components=1"                              # 解压时去掉 tar 包中的第一层目录
>     creates: "{{ install_dir }}/{{ doris_name }}/fe/bin/start_fe.sh" # 解压后一定存在的文件
>   when: not extracted_files.stat.exists
>   register: unarchive_task                                           # 同步执行
> ```

### 备份并修改 FE 和 BE 进程的配置文件

```yaml
# 备份配置文件
- name: Backup FE config
  copy:
    src: "{{ install_dir }}/{{ doris_name }}/{{ fe_conf }}"
    dest: "{{ install_dir }}/{{ doris_name }}/{{ fe_conf }}.backup"
    remote_src: yes

- name: Backup BE config
  copy:
    src: "{{ install_dir }}/{{ doris_name }}/{{ be_conf }}"
    dest: "{{ install_dir }}/{{ doris_name }}/{{ be_conf }}.backup"
    remote_src: yes

# 修改 FE 配置
- name: Modify FE config
  blockinfile:
    path: "{{ install_dir }}/{{ doris_name }}/{{ fe_conf }}"
    marker: "# {mark} ANSIBLE MANAGED BLOCK - FE CONFIG"
    block: |
      cluster_id = -1
      priority_networks = {{ priority_networks }}
      JAVA_HOME = {{ java_home_path.stdout }}

# 修改 BE 配置
- name: Modify BE config
  blockinfile:
    path: "{{ install_dir }}/{{ doris_name }}/{{ be_conf }}"
    marker: "# {mark} ANSIBLE MANAGED BLOCK - BE CONFIG"
    block: |
      brpc_port = {{ be_brpc_port }}
      priority_networks = {{ priority_networks }}

# 清理旧数据（首次部署或需要重建时设为 true）
- name: Clean old data
  block:
    - name: Clean FE metadata
      file:
        path: "{{ install_dir }}/{{ doris_name }}/fe/doris-meta"
        state: absent
    - name: Clean BE storage
      file:
        path: "{{ install_dir }}/{{ doris_name }}/be/storage"
        state: absent
    - name: Recreate FE metadata directory
      file:
        path: "{{ install_dir }}/{{ doris_name }}/fe/doris-meta"
        state: directory
        owner: "{{ ansible_user | default('root') }}"
        group: "{{ ansible_user | default('root') }}"
        mode: '0755'
    - name: Recreate BE storage directory
      file:
        path: "{{ install_dir }}/{{ doris_name }}/be/storage"
        state: directory
        owner: "{{ ansible_user | default('root') }}"
        group: "{{ ansible_user | default('root') }}"
        mode: '0755'
    - name: Clean FE PID
      file:
        path: "{{ install_dir }}/{{ doris_name }}/fe/bin/fe.pid"
        state: absent
    - name: Clean BE PID
      file:
        path: "{{ install_dir }}/{{ doris_name }}/be/bin/be.pid"
        state: absent
   when: clean_doris_data | default(false) | bool
```

### 启动Doris服务

Apache Doris 集群对于存算一体架构（Combined Backend）要求每个节点同时运行 FE 和 BE 服务，具体部署以及启动顺序的标准流程：

1. 启动MasterFE服务
2. 在Master节点注册Slave节点的FE服务
3. 启动SlaveFE服务，通过helper参数指向Master节点
4. 启动所有节点BE服务
5. 连接MySQL通讯协议将所有节点的BE服务注册集群
6. 验证集群结果

#### 启动MasterFE服务

```yaml
## 启动MasterFE服务
# 检查FE服务是否启动
- name: Check if FE is already running
  shell: |
    FE_PID_FILE="{{ install_dir }}/{{ doris_name }}/fe/bin/fe.pid"
    if [ -f "$FE_PID_FILE" ]; then
      PID=$(cat "$FE_PID_FILE")
      if kill -0 "$PID" 2>/dev/null; then
        echo "running"
      else
        rm -f "$FE_PID_FILE"
        echo "not_running"
      fi
    else
      echo "not_running"
    fi
  register: fe_running
  changed_when: false

# 启动MasterFE服务
- name: Start Master FE service
  shell: |
    source /etc/profile
    unset http_proxy
    unset https_proxy
    cd {{ install_dir }}/{{ doris_name }}/fe/bin
    ./start_fe.sh --daemon
  args:
    executable: /bin/bash
  when: fe_running.stdout == "not_running"

# 等待服务启动
- name: Wait for Master FE query port to be ready
  wait_for:
    port: "{{ fe_query_port }}"
    host: "{{ ansible_host }}"
    timeout: 120
    delay: 5

# 检测服务启动后web返回状态
- name: Verify Master FE HTTP API is available
  uri:
    url: "http://{{ ansible_host }}:{{ fe_http_port }}/api/bootstrap"
    method: GET
    status_code: 200
  register: fe_bootstrap
  retries: 12
  delay: 10
  until: fe_bootstrap.status == 200

- name: Master FE started successfully
  debug:
    msg: "Master FE is running on {{ ansible_host }}"
```

#### 注册SlaveFE服务

```yaml
## 注册SlaveFE服务
# 在Master节点执行从节点的FE服务注册步骤，需要提前在vars中添加mysql模块的参数，比如用户名密码
- name: "Register Slave FE: {{ item }}"
  community.mysql.mysql_query:
    login_host: "{{ ansible_host }}"
    login_user: "{{ mysql_user }}"
    login_password: "{{ mysql_password }}"
    login_port: "{{ fe_query_port }}"
    query: "ALTER SYSTEM ADD FOLLOWER '{{ item }}:{{ fe_edit_log_port }}'"
  loop: "{{ groups['doris'][1:] | map('extract', hostvars, 'ansible_host') | list }}"
  register: add_follower_result
  failed_when:
    - add_follower_result is failed
    - "'already' not in (add_follower_result.msg | default('') | string)"
```

#### 启动SlaveFE服务

```yaml
## 启动SlaveFE服务
# 检查FE服务是否启动
- name: Check if FE is already running
  shell: |
    FE_PID_FILE="{{ install_dir }}/{{ doris_name }}/fe/bin/fe.pid"
    if [ -f "$FE_PID_FILE" ]; then
      PID=$(cat "$FE_PID_FILE")
      if kill -0 "$PID" 2>/dev/null; then
        echo "running"
      else
        rm -f "$FE_PID_FILE"
        echo "not_running"
      fi
    else
      echo "not_running"
    fi
  register: fe_running
  changed_when: false

# 启动SlaveFE服务
- name: Start Slave FE service
  shell: |
    source /etc/profile
    unset http_proxy
    unset https_proxy
    cd {{ install_dir }}/{{ doris_name }}/fe/bin
    ./start_fe.sh --helper {{ master_fe_host }}:{{ fe_edit_log_port }} --daemon
  args:
    executable: /bin/bash
  when: fe_running.stdout == "not_running"

# 等待服务启动
- name: Wait for Slave FE query port to be ready
  wait_for:
    port: "{{ fe_query_port }}"
    host: "{{ ansible_host }}"
    timeout: 120
    delay: 5

- name: Slave FE started successfully
  debug:
    msg: "Slave FE is running on {{ ansible_host }}"
```

#### 验证FE集群启动状态

```yaml
- name: Query FE cluster status
  community.mysql.mysql_query:
    login_host: "{{ ansible_host }}"
    login_user: "{{ mysql_user }}"
    login_password: "{{ mysql_password }}"
    login_port: "{{ fe_query_port }}"
    query: "SHOW PROC '/frontends'"
  register: fe_status
  retries: 10
  delay: 15
  until: fe_status.query_result is defined

- name: Print FE cluster status
  debug:
    msg: |
      FE Node: {{ item.Host }}
        Role: {{ item.Role }}
        IsMaster: {{ item.IsMaster }}
        Alive: {{ item.Alive }}
        EditLogPort: {{ item.EditLogPort }}
  loop: "{{ fe_status.query_result[0] }}"
  when: fe_status.query_result is defined

- name: Verify all FE nodes are alive
  assert:
    that:
      - item.Alive == "true"
    fail_msg: "FE node {{ item.Host }} is NOT alive!"
    success_msg: "FE node {{ item.Host }} is alive (Role={{ item.Role }}, IsMaster={{ item.IsMaster }})"
  loop: "{{ fe_status.query_result[0] }}"
  when: fe_status.query_result is defined

- name: Verify FE node count
  assert:
    that:
      - (fe_status.query_result[0] | length) == (expected_fe_count | int)
    fail_msg: |
      FE count mismatch! Expected: {{ expected_fe_count }}, Actual: {{ fe_status.query_result[0] | length }}
    success_msg: "All {{ expected_fe_count }} FE nodes joined the cluster"
```

#### 启动BE服务

```yaml
## 启动BE服务
# 检查BE服务是否已经启动
- name: Check if BE is already running
  shell: |
    BE_PID_FILE="{{ install_dir }}/{{ doris_name }}/be/bin/be.pid"
    if [ -f "$BE_PID_FILE" ]; then
      PID=$(cat "$BE_PID_FILE")
      if kill -0 "$PID" 2>/dev/null; then
        echo "running"
      else
        rm -f "$BE_PID_FILE"
        echo "not_running"
      fi
    else
      echo "not_running"
    fi
  register: be_running
  changed_when: false

# 启动所有节点BE服务
- name: Start BE service
  shell: |
    source /etc/profile
    unset http_proxy
    unset https_proxy
    cd {{ install_dir }}/{{ doris_name }}/be/bin
    ./start_be.sh --daemon
  args:
    executable: /bin/bash
  when: be_running.stdout == "not_running"

# 等待服务启动
- name: Wait for BE heartbeat port to be ready
  wait_for:
    port: "{{ be_heartbeat_service_port }}"
    host: "{{ ansible_host }}"
    timeout: 120
    delay: 5
  when: be_running.stdout == "not_running"

- name: BE started successfully
  debug:
    msg: "BE is running on {{ ansible_host }}"
```

#### 注册BE服务

```yaml
# 每个 BE 节点单独执行一条 ALTER SYSTEM ADD BACKEND
- name: Add BE to cluster
  community.mysql.mysql_query:
    login_host: "{{ ansible_host }}"
    login_user: "{{ mysql_user }}"
    login_password: "{{ mysql_password }}"
    login_port: "{{ fe_query_port }}"
    query: "ALTER SYSTEM ADD BACKEND '{{ item }}:{{ be_heartbeat_service_port }}'"
  loop: "{{ groups['doris'] | map('extract', hostvars, 'ansible_host') | list }}"
  register: add_backend_result
  # 如果 BE 已注册会返回错误，忽略此情况
  failed_when:
    - add_backend_result is failed
    - "'already' not in (add_backend_result.msg | default('') | string)"

# 等待BE服务的心跳检测
- name: Wait for all BE nodes to report heartbeat
  pause:
    seconds: 10
```



## 四、启动自动化剧本部署集群服务

执行剧本启动集群服务

```bash
ansible-playbook doris.yaml
```

![doris执行成功](.\images\doris执行成功.png)

查看执行结果，通过mysql通讯协议来链接集群查看状态

>注意：节点系统并没有安装mysql，doris只是保留了mysql通讯协议，链接集群需要指定端口9030而并非3306

```mysql
# 案例的doris集群没有密码，默认root用户名
mysql -h172.25.195.121 -P9030 -uroot
# 查看FE集群状态
> show proc "/frontends" \G;
# 查看BE集群状态
> show proc "/backends" \G;
```

<img src=".\images\fe_修改.png" alt="e63485f6a626611b8a495e1679046a96" style="zoom:80%;" />

<img src=".\images\be.png" alt="be" style="zoom:80%;" />

访问web端查看集群状态

![web](.\images\web.jpg)



## 五、完整剧本yml文件

案例中完整剧本yml文件上传至github：https://github.com/Gabriel-Antonio-Sephiroth/DevOps_Tools/blob/2d7333147f68deb7e1d00883287dec1d2ad2b259/Ansible_Tools/Doris/doris.yaml
