# 环境搭建与项目重建清单

> **用途**：在一台新机器上把本项目完整重建起来。
> **环境**：Windows 10/11 + PowerShell。以下命令均已在本项目上实测通过。
> **顺序**：请严格按章节顺序执行，第 3、4 章内部有依赖关系。

---

## 一、组件清单

| 组件 | 版本 | 端口 | 用途 |
| --- | --- | --- | --- |
| Python | 3.13 | — | 后端服务 + 数据脚本 |
| PostgreSQL | 18 | 5432 | 数据存储 |
| PostGIS | 3.6 | — | 空间扩展（几何类型、空间索引、坐标转换） |
| GeoServer | 3.0（依赖 Java 21） | **8086** | 地图服务（WMS / SLD） |
| Node.js | 24 | — | 前端构建（Vite） |
| QGIS | 3.44（自带 GDAL 3.13） | — | **只用它的 ogr2ogr** 做数据导入 |
| 天地图 | — | — | 底图影像，需自行申请 Key |

磁盘空间约需 **1.5 GB**（GeoServer 500 MB + PostgreSQL 400 MB + `.venv` 370 MB + `node_modules` 200 MB）。

---

## 二、安装步骤

### 2.1 配置国内镜像（**先做这一步**）

不配镜像的话，装依赖会非常慢甚至超时失败。

```powershell
pip config set global.index-url https://pypi.tuna.tsinghua.edu.cn/simple
npm config set registry https://registry.npmmirror.com
```

### 2.2 Python 3.13

从 <https://www.python.org/downloads/windows/> 下载 64 位安装包，安装时**务必勾选**
`Add python.exe to PATH`。

```powershell
python --version          # 期望 Python 3.13.x
```

### 2.3 PostgreSQL 18 + PostGIS 3.6

从 <https://www.enterprisedb.com/downloads/postgres-postgresql-downloads> 下载安装，
端口保持 `5432`，记住超级用户密码（本项目默认用 `postgres`）。

安装向导最后会提示启动 **Stack Builder**，用它安装 PostGIS：
`Spatial Extensions` → 勾选对应 PG18 的 PostGIS 版本 → 安装。

如果 Stack Builder 下载失败，改用 OSGeo 的 Windows 包：
<https://download.osgeo.org/postgis/windows/> （选 `pg18` 目录）。

> **注意**：OSGeo 的包是 ZIP 解压型，解压后**会多一层目录**
> （如 `postgis-bundle-pg18-3.6.2x64\bin|lib|share`）。
> 需要把里面的 `bin` / `lib` / `share` **合并到 PostgreSQL 安装根目录**，
> 而不是直接把整个文件夹扔进去。

### 2.4 Node.js

从 <https://nodejs.org/> 下载 LTS 版本安装。

```powershell
node -v      # 期望 v24.x
npm -v       # 期望 11.x
```

### 2.5 QGIS（本项目只需要它的 GDAL/ogr2ogr）

从 <https://qgis.org/download/> 下载安装。

> 本项目用 `ogr2ogr` 把 GeoJSON / Esri GDB 导入 PostGIS。**不需要单独装 GDAL**——
> QGIS 自带 GDAL 完整工具链，默认路径 `C:\Program Files\QGIS 3.xx\bin\ogr2ogr.exe`。
> 如果你的安装路径不同，改 `scripts\02_load_base.ps1` 里的 `$Ogr2OgrExe` 变量。
>
> 顺带一提：读 Esri File Geodatabase（`.gdb`）**不需要 ArcGIS**——
> GDAL 3.6 以后内置的 OpenFileGDB 驱动就能读。

### 2.6 GeoServer 3.0 + Java 21

1. 先装 **JDK 21**：<https://adoptium.net/> 或 Oracle JDK 均可
2. 再装 **GeoServer**：<https://geoserver.org/download/> ，选 Windows Installer

安装时注意两点：

- **数据目录**建议设在非系统盘。本项目用的是 `E:\Program Data\geoserver`，
  安装器会自动写入 `GEOSERVER_DATA_DIR` 环境变量
- **端口是 8086**，不是默认的 8080。如果需要改，编辑
  `<安装目录>\start.ini` 里的 `jetty.http.port`

验证：

```powershell
Start-Service GeoServer
# 等 10~40 秒，然后访问 http://localhost:8086/geoserver/web/
# 默认账号 admin / geoserver
```

### 2.7 后端虚拟环境与依赖

```powershell
cd "E:\Program Data\vscode\urban demo"

py -3.13 -m venv .venv
.\.venv\Scripts\Activate.ps1

# 如果激活脚本被执行策略拦截，先跑一次：
#   Set-ExecutionPolicy -Scope CurrentUser RemoteSigned

# 必需依赖（后端服务 + 数据仿真）
pip install fastapi "uvicorn[standard]" asyncpg

# 可选依赖（数据勘察与调试用）
pip install pandas pyogrio geopandas pillow
```

---

## 三、数据库初始化（4 步）

### 3.1 建库并启用 PostGIS

```powershell
$env:PGPASSWORD = 'postgres'
$psql = 'E:\Program Files\PostgreSQL\18\bin\psql.exe'

# 建库（编码必须显式指定 UTF8，否则中文会乱码）
& $psql -U postgres -h localhost -p 5432 -d postgres -c "CREATE DATABASE urban_demo ENCODING 'UTF8' TEMPLATE template0;"

# 启用 PostGIS
& $psql -U postgres -h localhost -p 5432 -d urban_demo -c "CREATE EXTENSION postgis;"
& $psql -U postgres -h localhost -p 5432 -d urban_demo -c "SELECT postgis_full_version();"
```

### 3.2 数据入库（建表 + 导入 + 转换）

先确认数据文件就位：

| 路径 | 内容 |
| --- | --- |
| `GeoJSON\urban roads.geojson` | 城市路网（52 MB） |
| `GeoJSON\Bus Routes.geojson` | 公交线路与站点（18 MB） |
| `GeoJSON\railway.geojson` | 地铁线路与车站（1.5 MB） |
| `suzhouH51\H51.gdb` | 1:5 万基础地理数据（行政区边界来源） |

执行入库脚本（约 15 秒）：

```powershell
cd "E:\Program Data\vscode\urban demo"
pwsh -NoProfile -ExecutionPolicy Bypass -File "scripts\02_load_base.ps1"
```

该脚本依次执行：建表（`sql\01_schema.sql`）→ `ogr2ogr` 导入 →
`sql\02~05` 的转换脚本 → 汇总核对。

**期望输出**：

```
district       9 行
road       67153 行（支路 42585 / 次干道 9645 / 主干道 9131 / 快速路 3192 / 高速 2600）
metro_line    26 行      metro_station 616 行
bus_route    472 行      bus_stop     6134 行
```

### 3.3 业务数据仿真

```powershell
cd "E:\Program Data\vscode\urban demo"
.\.venv\Scripts\python.exe "scripts\03_simulate.py"
```

约 30 秒，生成信号灯 2600、监控 2200、警力 182、事件 320，
以及 **589,632 行**时序流量数据与 1,080 行区域车辆数据。

> 脚本可重复执行——每次先清空旧仿真数据再重新生成，随机种子固定，结果可复现。

### 3.4 建 GeoServer 专用视图（**必须在 3.3 之后**）

```powershell
& $psql -U postgres -h localhost -p 5432 -d urban_demo -v ON_ERROR_STOP=1 -q -f "sql\06_geoserver_views.sql"
& $psql -U postgres -h localhost -p 5432 -d urban_demo -c "SELECT count(*) FROM v_road UNION ALL SELECT count(*) FROM v_district;"
```

**为什么必须放在仿真之后**：视图 `v_district` 里的 `avg_index`（平均拥堵指数）
来自 `road_status` 表，而那张表的数据是 3.3 才生成的。视图本身可以先建，
但数据齐了之后建，才能直接核对结果。

---

## 四、GeoServer 配置（3 步）

### 4.1 确认 GeoServer 已启动

```powershell
Start-Service GeoServer
# 等 10~40 秒后访问： http://localhost:8086/geoserver/web/
```

### 4.2 发布图层

```powershell
cd "E:\Program Data\vscode\urban demo"
pwsh -NoProfile -ExecutionPolicy Bypass -File "scripts\04_geoserver_publish.ps1"
```

脚本通过 REST API 完成：建工作区 `urban` → 建 PostGIS 数据源 `urban_demo` →
发布 10 个图层（`v_road` / `v_district` / `metro_line` / `metro_station` /
`bus_route` / `bus_stop` / `signal` / `camera` / `police_unit` / `incident`）。

**期望输出**：10 个图层全部 `OK`，末尾显示「已发布 10 个图层」。

### 4.3 上传并绑定 SLD 样式

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File "scripts\05_geoserver_styles.ps1"
```

上传 11 套样式并绑定到对应图层：`road_class` / `road_congestion` /
`district_heat` / `pt_signal` / `pt_camera` / `pt_police` / `pt_incident` /
`ln_metro` / `pt_metro_station` / `ln_bus` / `pt_bus_stop`。

> 这两个脚本都是**幂等**的：`04` 会先删掉整个工作区再重建，
> `05` 会先删掉同名样式再重建。所以 **04 跑完必须接着跑 05**——
> 否则图层会因为样式被删而无法出图。

### 4.4 管理界面

| 用途 | 地址 |
| --- | --- |
| 图层预览 / 改样式 / 看日志 | <http://localhost:8086/geoserver/web/> |
| 账号 | `admin` / `geoserver` |

---

## 五、启动项目

### 5.1 一键启动（推荐）

双击项目根目录的 **`启动大屏.bat`**。它会：

1. 检查 8086 端口，GeoServer 没跑就启动服务并等 40 秒
2. 启动后端 FastAPI（8000）
3. 启动前端 Vite（5173）
4. 等 10 秒后自动打开浏览器

停止服务：双击 **`停止大屏.bat`**。

### 5.2 手动启动（排查问题时用）

需要**三个终端**：

```powershell
# 终端 1：GeoServer（服务已启动可跳过）
Start-Service GeoServer

# 终端 2：后端
cd "E:\Program Data\vscode\urban demo"
.\.venv\Scripts\python.exe -m uvicorn backend.app.main:app --host 127.0.0.1 --port 8000

# 终端 3：前端
cd "E:\Program Data\vscode\urban demo\frontend"
npm install      # 首次需要
npm run dev
```

浏览器打开 <http://127.0.0.1:5173/>

### 5.3 请求链路

```
浏览器 → Vite :5173 ─┬─ /geoserver → GeoServer :8086 → PostGIS :5432
                     └─ /api       → FastAPI   :8000 → PostGIS :5432
```

两类后端服务都通过 Vite 的反向代理挂到同源下，因此**不需要在 GeoServer 里配 CORS**。
代理配置见 `frontend\vite.config.js`。

---

## 六、端到端验收清单

```powershell
# 1. 数据库
& $psql -U postgres -h localhost -p 5432 -d urban_demo -c "SELECT count(*) FROM road;"
#    期望 67153

# 2. 视图
& $psql -U postgres -h localhost -p 5432 -d urban_demo -c "SELECT count(*) FROM v_road UNION ALL SELECT count(*) FROM v_district;"
#    期望 67153 / 9

# 3. GeoServer
curl.exe -s -o NUL -w "%{http_code}`n" -u admin:geoserver http://localhost:8086/geoserver/rest/about/version
#    期望 200

# 4. 后端
curl.exe -s http://127.0.0.1:8000/api/health
#    期望 {"status":"ok","roads":67153}

# 5. 前端
curl.exe -s -o NUL -w "%{http_code}`n" http://127.0.0.1:5173/
#    期望 200

# 6. WMS 出图（经 Vite 代理，等价于浏览器行为）
curl.exe -s -o NUL -w "%{http_code} %{size_download}`n" "http://127.0.0.1:5173/geoserver/urban/wms?service=WMS&version=1.1.1&request=GetMap&layers=urban:v_road&styles=road_class&bbox=120.4,31.1,120.9,31.5&width=512&height=512&srs=EPSG:4326&format=image/png&transparent=true"
#    期望 200，且体积在 100000 字节以上
```

再打开页面确认：影像底图 + 五级配色路网正常显示；图层面板能开关各图层；
点击道路能弹出属性框。

---

## 七、常见坑速查

以下均为本项目实际踩过的坑，按「现象 → 原因 → 处理」整理。

### 7.1 中文与编码类

| 现象 | 原因 | 处理 |
| --- | --- | --- |
| 双击 `.bat` 报一堆乱码，如 `'瑙喑漯瀍y院' 不是内部或外部命令` | 批处理文件是 UTF-8，而中文 Windows 的 cmd 按 **936 代码页**读文件 | `.bat` 必须存成 **GBK 编码 + CRLF 换行 + 无 BOM** |
| `.bat` 里注释行被当命令执行、`echo` 前缀丢失 | 文件用了 **LF 换行**，cmd 解析器会错乱 | 同上，必须 CRLF |
| `psql -c "含中文的 SQL"` 报 `无效的 "UTF8" 编码字节顺序` | PowerShell 给原生程序传参用的是系统 ANSI 代码页 | 含中文的 SQL 一律**写成 `.sql` 文件用 `-f` 执行**，不要走 `-c` |
| SLD 里的中文过滤条件不生效 | 样式文件的编码在传输或存储过程中被破坏 | 中文字面量一律转成 **XML 字符引用**（如 `&#x6B63;&#x5E38;` = 正常），使 SLD 成为纯 ASCII 文件；同时给数据库视图加 ASCII 分类码列 |
| 数据库里中文变成 `????` | 建库时没指定 UTF8 编码 | 用 `ENCODING 'UTF8' TEMPLATE template0` 重建 |

### 7.2 GeoServer 类

| 现象 | 原因 | 处理 |
| --- | --- | --- |
| 服务起不来，日志报 `Failed to bind to 0.0.0.0:8086` | 端口已被另一个实例占用 | 先确认 8086 是否已有实例在跑（`netstat -ano \| findstr :8086`），不要重复启动 |
| **端口在监听，但所有请求都超时无响应** | 数据库停机期间 GeoServer 的 PostGIS 连接池进入了坏状态，数据库恢复后它不会自愈 | 重启服务：`Restart-Service GeoServer -Force`（约 10 秒即可恢复） |
| 用 `Restart-Service GeoServer -Force` 重启后，服务变成 Stopped、8086 也不通了 | `Restart-Service -Force` 在停止该服务时会报 `Cannot stop 'GeoServer' service`，停了一半却没起来 | **改用 `net stop GeoServer` + `net start GeoServer`**（`启动大屏.bat` 用的就是这两个命令） |
| 访问 `localhost:8080/geoserver` 打不开 | 本项目端口是 **8086**，不是 8080 | 确认端口配置（`start.ini` 里的 `jetty.http.port`） |
| 创建样式报 `Style fileName must not be null` | 用 XML 方式 `POST /rest/styles` 时 GeoServer 要求 `<filename>` 字段 | 改用 `POST /rest/styles?name=X` 直接带 SLD 内容 |
| 删除要素类型报 500 | 图层还引用着该要素类型 | 必须先 `DELETE /rest/layers/{工作区}:{图层}`，再删要素类型 |
| 样式里写了 `rgba(0,0,0,0.5)` 不生效或报错 | **SLD 不支持 `rgba()`** | 用十六进制色值 + 单独的 `fill-opacity` 参数 |
| 发布视图后看不到新加的字段 | GeoServer 缓存了要素类型的结构 | 删图层 → 删要素类型 → 重新发布 |
| 视图发布后 GeoServer 识别不出几何类型 | 视图的几何列没有明确类型 | 建视图时显式转型：`geom::geometry(MultiLineString, 4326)` |

### 7.3 数据与坐标系类

| 现象 | 原因 | 处理 |
| --- | --- | --- |
| 图层位置整体偏移几百米 | 混用了 WGS84（GPS/OSM）与 GCJ-02（高德/腾讯）/ BD-09（百度） | 本项目全库统一按 EPSG:4326 存储；若要叠加国内偏移底图，需先做坐标纠偏 |
| `ST_LineInterpolatePoint` 报 `1st arg isn't a line` | 路网几何是 MultiLineString，该函数只接受 LineString | 用 `ST_PointOnSurface(geom)`，或先 `ST_GeometryN(geom, 1)` |
| 按行政区统计时数字大得离谱 | 多表 LEFT JOIN 造成行数膨胀，`count`/`sum` 被重复累加 | 改用**子查询**而非链式 JOIN（见 `sql\06_geoserver_views.sql`） |
| 后端返回的数值在前端参与计算时报类型错误 | PostGIS 的 `numeric` 类型经编码后会变成**字符串** | SQL 里显式转型 `::float8` / `::int` |
| 拥堵分布不合理（要么全畅通，要么全堵） | 拥堵模型系数没标定 | 按「基础值 + 道路等级系数 + 时段负荷 + 城区加成 + 局部热点」分层叠加，并核对各等级占比 |

### 7.4 前端与联调类

| 现象 | 原因 | 处理 |
| --- | --- | --- |
| 页面卡在「正在加载」，提示后端未启动 | 加载数据时后端恰好没起来 | 页面有**自动重试**（3 秒一次，共 10 次），也可点「立即重试」 |
| 地图全空，控制台无报错 | 某个图层添加失败导致整个初始化中断 | 代码里每个图层单独 `try/catch`，失败清单打印在控制台，不会拖垮其它图层 |
| WMS 请求返回 200 但地图没内容 | 样式里的过滤条件没匹配上（多为编码问题） | 单独请求该图层的 `GetMap`，看返回的 PNG 是否为空 |
| 前端请求 GeoServer 被浏览器拦（CORS） | 5173 与 8086 不同源 | 已在 `vite.config.js` 配 `/geoserver` 代理，不要用绝对地址直连 8086 |
| 改了 `vite.config.js` 不生效 | 代理配置只在启动时读取 | **重启 Vite** |
| `npm install` 提示 esbuild 安装脚本被拦截 | npm 的 allow-scripts 策略 | 不影响使用（esbuild 的平台二进制来自可选依赖），构建能通过即可 |

### 7.5 环境与依赖类

| 现象 | 原因 | 处理 |
| --- | --- | --- |
| **后端启动后立刻退出**，日志报 `ConnectionRefusedError` / `Application startup failed` | PostgreSQL 没启动——后端的连接池建不起来，应用会直接退出 | **服务依赖有顺序**：PostgreSQL → GeoServer → FastAPI。`启动大屏.bat` 已内置这个顺序检查 |
| 前端能打开，但所有 `/api` 请求报 `ECONNREFUSED 127.0.0.1:8000` | 只启动了 Vite，没启动后端 | 用 `启动大屏.bat` 一次拉起四个服务，不要单独开 `npm run dev` |
| 机器被强制关机（断电/长按电源）后，下次开机某些服务起不来 | PostgreSQL 需要做崩溃恢复，耗时可能超过 GeoServer 的等待窗口 | 重启电脑后等 1~2 分钟再启动项目；若仍异常，按上面的顺序手动重启服务 |
| `pip install gdal` 编译失败 | Windows 上几乎装不上，而且没必要 | 用 QGIS 自带的 GDAL，或 `pip install pyogrio fiona`（wheel 自带 GDAL） |
| `.ps1` 脚本无法运行 | PowerShell 执行策略 | `Set-ExecutionPolicy -Scope CurrentUser RemoteSigned` |
| 装了多个 Python，跑错版本 | 机器上可能还有 ArcGIS 自带的 Python 2.7 | 统一用 `py -3.13` 或 `.venv\Scripts\python.exe` |
| 项目路径含空格导致工具报错 | GDAL / PROJ 等对空格路径敏感 | 建议把项目放在无空格路径下 |
