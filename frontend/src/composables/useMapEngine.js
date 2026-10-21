/**
 * 地图引擎（OpenLayers 版）
 * ==========================
 * 服务端：GeoServer 提供 WMS 出图 / SLD 样式 / CQL 动态过滤 / GetFeatureInfo 查属性
 * 客户端：OpenLayers 负责地图视图、图层开关、交互
 *
 * 三个关键点：
 *   1. 样式定义在服务端 SLD 里，前端通过 STYLES 参数切换
 *   2. 要素过滤用 CQL_FILTER 交给 GeoServer 执行，不用前端过滤
 *   3. WMS 返回的是图片、前端拿不到要素，所以点击查属性要走 GetFeatureInfo
 */
import { shallowRef, watch } from "vue";

import Map from "ol/Map";
import View from "ol/View";
import TileLayer from "ol/layer/Tile";
import XYZ from "ol/source/XYZ";
import TileWMS from "ol/source/TileWMS";
import Overlay from "ol/Overlay";
import { defaults as defaultControls, ScaleLine } from "ol/control";
import { fromLonLat, transformExtent } from "ol/proj";
import "ol/ol.css";

import { ROAD_STYLES, WMS_LAYERS, WMS_URL } from "../config/geoserver";
import {
  DEFAULT_VIEW,
  TIANDITU_SUBDOMAINS,
  tiandituTileUrl,
} from "../config/map";
import { state } from "../state";

/** 道路等级 -> 视图里的 ASCII 码（和数据库视图保持一致） */
const ROAD_CLASS_CODE = {
  高速: "hw",
  快速路: "exp",
  主干道: "art",
  次干道: "sec",
  支路: "brn",
};

/** 图层自上而下的堆叠顺序（后面的画在上面） */
const LAYER_ORDER = [
  "district",
  "road",
  "metro_line",
  "metro_station",
  "bus_route",
  "bus_stop",
  "signal",
  "camera",
  "police",
  "incident",
];

/** 点击查询时的优先级：先给出"更具体"的要素 */
const QUERY_PRIORITY = [
  "incident",
  "police",
  "camera",
  "signal",
  "metro_station",
  "bus_stop",
  "metro_line",
  "bus_route",
  "road",
  "district",
];

export function useMapEngine() {
  const map = shallowRef(null);
  const sources = {};
  const layers = {};
  let overlay = null;
  let ready = false;

  // ------------------------------------------------------------
  //  底图：天地图影像 + 注记
  // ------------------------------------------------------------
  function makeBasemap() {
    // XYZ 的 url 模板只支持单域名，这里用 tileUrlFunction 做 8 个子域轮询
    const tdtSource = (name) =>
      new XYZ({
        maxZoom: 18,
        tileUrlFunction: (coord) => {
          const [z, x, y] = coord;
          const sub =
            TIANDITU_SUBDOMAINS[Math.abs(x + y) % TIANDITU_SUBDOMAINS.length];
          return tiandituTileUrl(name, sub)
            .replace("{z}", z)
            .replace("{y}", y)
            .replace("{x}", x);
        },
      });
    return [
      new TileLayer({
        source: tdtSource("img"),
        properties: { name: "天地图影像" },
      }),
      new TileLayer({
        source: tdtSource("cia"),
        properties: { name: "天地图注记" },
      }),
    ];
  }

  // ------------------------------------------------------------
  //  WMS 图层
  // ------------------------------------------------------------
  function makeWmsLayer(key) {
    const cfg = WMS_LAYERS[key];
    const src = new TileWMS({
      url: WMS_URL,
      params: {
        LAYERS: cfg.name,
        STYLES: cfg.style,
        TILED: true,
        VERSION: "1.1.1",
        FORMAT: "image/png",
        TRANSPARENT: true,
      },
      serverType: "geoserver",
      // 显式声明数据坐标系，省掉 OL 自动请求 GetCapabilities 的过程
      projection: "EPSG:4326",
      transition: 0,
    });
    sources[key] = src;
    const lyr = new TileLayer({ source: src, visible: !!state.visible[key] });
    layers[key] = lyr;
    return lyr;
  }

  // ------------------------------------------------------------
  //  交互：点击查属性
  // ------------------------------------------------------------
  function gfiUrl(queryLayers, pixel, size, extent4326) {
    const p = new URLSearchParams({
      SERVICE: "WMS",
      VERSION: "1.1.1",
      REQUEST: "GetFeatureInfo",
      LAYERS: queryLayers.join(","),
      QUERY_LAYERS: queryLayers.join(","),
      STYLES: "",
      BBOX: extent4326.join(","),
      WIDTH: String(size[0]),
      HEIGHT: String(size[1]),
      SRS: "EPSG:4326",
      X: String(Math.round(pixel[0])),
      Y: String(Math.round(pixel[1])),
      INFO_FORMAT: "application/json",
      FEATURE_COUNT: "20",
    });
    return `${WMS_URL}?${p.toString()}`;
  }

  function layerKeyOfFeatureId(id) {
    // GeoServer 返回的 id 形如 "v_road.fid-xxx"
    const prefix = String(id || "").split(".")[0];
    return Object.keys(WMS_LAYERS).find((k) =>
      WMS_LAYERS[k].name.endsWith(prefix),
    );
  }

  function popupHtml(key, p) {
    const rows = [];
    let title = WMS_LAYERS[key]?.title || "要素信息";

    if (key === "road") {
      title = p.name || p.ref || "未命名道路";
      rows.push(
        ["等级", p.road_class],
        ["编号", p.ref],
        ["车道数", p.lanes],
        ["拥堵状态", p.congestion_level],
        ["拥堵指数", p.congestion],
        ["平均车速", p.speed_kmh != null ? `${p.speed_kmh} km/h` : ""],
      );
    } else if (key === "district") {
      title = p.name || "行政区";
      rows.push(
        ["区划代码", p.pac],
        ["面积", p.area_km2 != null ? `${p.area_km2} km²` : ""],
        ["路网里程", p.road_km != null ? `${p.road_km} km` : ""],
        ["事故数", p.incident_cnt],
        ["信号灯", p.signal_cnt],
        ["平均拥堵指数", p.avg_index],
      );
    } else if (key === "signal") {
      title = p.name || "交通信号灯";
      rows.push(["编号", p.code], ["状态", p.status]);
    } else if (key === "camera") {
      title = p.name || "监控设备";
      rows.push(["编号", p.code], ["类型", p.kind], ["状态", p.status]);
    } else if (key === "police") {
      title = p.name || "警力";
      rows.push(
        ["编号", p.code],
        ["类型", p.kind],
        ["状态", p.status],
        ["警员数", p.officer_cnt],
      );
    } else if (key === "incident") {
      title = p.kind || "事件";
      rows.push(
        ["编号", p.code],
        ["等级", p.level],
        ["状态", p.status],
        ["路段", p.road_name],
        ["发生时间", p.occurred_at],
      );
    } else if (key === "metro_line") {
      title = p.name || "地铁线路";
      rows.push(
        ["线路", p.line_no],
        [
          "里程",
          p.length_m != null ? `${(p.length_m / 1000).toFixed(1)} km` : "",
        ],
      );
    } else if (key === "metro_station") {
      title = p.name || "地铁车站";
    } else if (key === "bus_route") {
      title = p.name || "公交线路";
      rows.push(
        ["线路号", p.ref],
        ["运营单位", p.operator],
        ["所属网络", p.network],
      );
    } else if (key === "bus_stop") {
      title = p.name || "公交站点";
    }

    const body = rows
      .filter((r) => r[1] !== undefined && r[1] !== null && r[1] !== "")
      .map((r) => `<div class="pr"><span>${r[0]}</span><b>${r[1]}</b></div>`)
      .join("");
    return `<div class="map-popup"><div class="pt">${title}</div>${body}</div>`;
  }

  async function handleClick(evt) {
    if (!map.value) return;
    const keys = QUERY_PRIORITY.filter(
      (k) => state.visible[k] && WMS_LAYERS[k]?.query,
    );
    if (!keys.length) return;

    const view = map.value.getView();
    const size = map.value.getSize();
    const extent4326 = transformExtent(
      view.calculateExtent(size),
      view.getProjection(),
      "EPSG:4326",
    );
    const queryNames = keys.map((k) => WMS_LAYERS[k].name);

    try {
      const res = await fetch(gfiUrl(queryNames, evt.pixel, size, extent4326));
      if (!res.ok) return;
      const fc = await res.json();
      const feats = fc.features || [];
      if (!feats.length) {
        overlay?.setPosition(undefined);
        return;
      }
      // 按优先级挑第一个命中的要素
      let chosen = null;
      for (const k of QUERY_PRIORITY) {
        chosen = feats.find((f) => layerKeyOfFeatureId(f.id) === k);
        if (chosen) break;
      }
      chosen = chosen || feats[0];
      const key = layerKeyOfFeatureId(chosen.id) || "road";

      if (overlay) {
        overlay.getElement().innerHTML = popupHtml(
          key,
          chosen.properties || {},
        );
        overlay.setPosition(evt.coordinate);
      }

      // 点行政区顺带缩放到该区
      if (key === "district") {
        const pac = chosen.properties?.pac;
        const d = state.districts.find((x) => String(x.pac) === String(pac));
        if (d) {
          state.selectedDistrict = d;
          fitDistrict(d);
        }
      }
    } catch (e) {
      console.error("[map] GetFeatureInfo 失败:", e);
    }
  }

  // ------------------------------------------------------------
  //  动态过滤
  // ------------------------------------------------------------
  /** 道路：切换样式（等级 / 拥堵）+ 只看某个等级 */
  function applyRoadStyleAndFilter() {
    const src = sources.road;
    if (!src) return;
    const style =
      state.roadColorBy === "congestion"
        ? ROAD_STYLES.congestion
        : ROAD_STYLES.class;
    const code = state.focusClass ? ROAD_CLASS_CODE[state.focusClass] : null;
    src.updateParams({
      STYLES: style,
      // CQL_FILTER 传空串等价于不过滤（已实测 111,193 像素与无过滤完全一致）
      CQL_FILTER: code ? `road_class_code='${code}'` : "",
    });
  }

  /** 地铁：按线路号过滤；一条都没开时用永假条件让它全部不显示 */
  function applyMetroFilter() {
    const src = sources.metro_line;
    if (!src) return;
    const entries = Object.entries(state.metroLines || {});
    if (!entries.length) {
      src.updateParams({ CQL_FILTER: "" });
      return;
    }
    const on = entries.filter(([, v]) => v).map(([k]) => k);
    const cql = on.length
      ? `line_no IN (${on.map((n) => `'${n}'`).join(",")})`
      : "1=0";
    src.updateParams({ CQL_FILTER: cql });
  }

  function applyVisibility() {
    if (!ready) return;
    Object.keys(layers).forEach((k) => {
      layers[k].setVisible(!!state.visible[k]);
    });
    // 有可查询图层时提示用户"可点击"
    const clickable = QUERY_PRIORITY.some(
      (k) => state.visible[k] && WMS_LAYERS[k]?.query,
    );
    const el = map.value?.getTargetElement();
    if (el) el.style.cursor = clickable ? "pointer" : "";
  }

  function fitDistrict(d) {
    if (!map.value || !d) return;
    const view = map.value.getView();
    // 注意：后端返回的行政区范围是 EPSG:4326（经纬度），
    // 而 view.fit() 需要的是**当前视图投影**下的坐标（默认 EPSG:3857，单位米）。
    // 直接传经纬度会被当成"120 米 × 31 米"的小方块，地图会飞到大西洋原点附近。
    const extent = transformExtent(
      [d.xmin, d.ymin, d.xmax, d.ymax],
      "EPSG:4326",
      view.getProjection(),
    );
    view.fit(extent, {
      padding: [70, 70, 70, 70],
      duration: 900,
      maxZoom: 13.5,
    });
  }

  function resetView() {
    state.focusClass = null;
    map.value?.getView().animate({
      center: fromLonLat(DEFAULT_VIEW.center),
      zoom: DEFAULT_VIEW.zoom,
      duration: 900,
    });
  }

  // ------------------------------------------------------------
  //  初始化
  // ------------------------------------------------------------
  function init(container) {
    const popupEl = document.createElement("div");
    popupEl.className = "ol-popup-box";
    overlay = new Overlay({
      element: popupEl,
      offset: [0, -14],
      positioning: "bottom-center",
      autoPan: { animation: { duration: 250 } },
    });

    map.value = new Map({
      target: container,
      layers: [...makeBasemap(), ...LAYER_ORDER.map(makeWmsLayer)],
      overlays: [overlay],
      controls: defaultControls({ attribution: false, rotate: false }).extend([
        new ScaleLine({ units: "metric", maxWidth: 120 }),
      ]),
      view: new View({
        center: fromLonLat(DEFAULT_VIEW.center),
        zoom: DEFAULT_VIEW.zoom,
        minZoom: DEFAULT_VIEW.minZoom,
        maxZoom: DEFAULT_VIEW.maxZoom,
      }),
    });

    map.value.on("singleclick", handleClick);

    ready = true;
    applyVisibility();
    applyRoadStyleAndFilter();
    applyMetroFilter();
    state.mapLoaded = true;

    // 初始化清单，便于排查
    console.info("[map] OpenLayers 初始化完成", {
      底图: "天地图影像 + 注记",
      服务: WMS_URL,
      图层: LAYER_ORDER.map((k) => WMS_LAYERS[k].name),
    });
    return map.value;
  }

  // ---------- 状态监听 ----------
  watch(() => ({ ...state.visible }), applyVisibility, { deep: true });
  watch(() => [state.roadColorBy, state.focusClass], applyRoadStyleAndFilter);
  watch(() => ({ ...state.metroLines }), applyMetroFilter, { deep: true });

  return { init, fitDistrict, resetView };
}
