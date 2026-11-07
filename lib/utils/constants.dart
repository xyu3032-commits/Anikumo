import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:anikumo/request/config/api_endpoints.dart';

class StyleString {
  static const double cardSpace = 8;
  static const double safeSpace = 12;
  static BorderRadius mdRadius = BorderRadius.circular(10);
  static const Radius imgRadius = Radius.circular(14);
  static const double aspectRatio = 16 / 10;

  // Browse-page design tokens (精选/发现). One spacing scale and one
  // radius ladder for all browse surfaces, so new sections line up with
  // the existing pages instead of inventing per-page values.
  static const double pagePadding = 16;
  static const double sectionSpace = 24;
  static const double sectionHeaderSpace = 12;
  static BorderRadius lgRadius = BorderRadius.circular(18);
  static BorderRadius xlRadius = BorderRadius.circular(20);

  // Motion tokens: one duration ladder for entrances and state changes,
  // so animation feels like a single system instead of per-page guesses.
  static const Duration animFast = Duration(milliseconds: 150);
  static const Duration animMedium = Duration(milliseconds: 280);
  static const Duration animSlow = Duration(milliseconds: 420);
}

const String customAppFontFamily = "MI_Sans_Regular";

/// Opts into the newer Material progress indicator appearance while Flutter
/// still exposes the compatibility flag.
const ProgressIndicatorThemeData progressIndicatorTheme2024 =
    // ignore: deprecated_member_use
    ProgressIndicatorThemeData(year2023: false);

/// Opts into the newer Material slider appearance while Flutter still exposes
/// the compatibility flag.
const SliderThemeData sliderTheme2024 = SliderThemeData(
  // ignore: deprecated_member_use
  year2023: false,
  showValueIndicator: ShowValueIndicator.onDrag,
);

const _pageTransitionBuilders = <TargetPlatform, PageTransitionsBuilder>{
  TargetPlatform.android: CupertinoPageTransitionsBuilder(),
  TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
  TargetPlatform.linux: FadeUpwardsPageTransitionsBuilder(),
  TargetPlatform.macOS: CupertinoPageTransitionsBuilder(),
  TargetPlatform.windows: FadeUpwardsPageTransitionsBuilder(),
};

const PageTransitionsTheme pageTransitionsTheme2024 =
    PageTransitionsTheme(builders: _pageTransitionBuilders);

// Applied only to the settings navigator; fullscreen routes use the app theme.
final PageTransitionsTheme settingsPageTransitionsTheme = PageTransitionsTheme(
  builders: {
    ..._pageTransitionBuilders,
    TargetPlatform.linux: const FadeForwardsPageTransitionsBuilder(),
    TargetPlatform.windows: const FadeForwardsPageTransitionsBuilder(),
  },
);

/// Layout breakpoint according to google:
/// https://developer.android.com/develop/ui/compose/layouts/adaptive/use-window-size-classes.
///
/// **It's only a suggestion since not every device meet the breakpoint requirement.
/// You need to build layout with some more judgements.**
///
/// Some example device(portrait) width x height:
///
/// * iPhone SE3: 375 x 667
/// * iPhone 16: 393 x 852
/// * iPad Pro 11-inch: 834 x 1210
/// * HW MATE60 Pro: 387.7 x 836.9
/// * OHOS in floating window: 387.7 x 631.7 or 218.1
class LayoutBreakpoint {
  static const Map<String, double> compact = {'width': 600, 'height': 480};
  static const Map<String, double> medium = {'width': 840, 'height': 900};
}

/// 随机UA列表
const List<String> userAgentsList = [
  'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/141.0.0.0 Safari/537.36',
  'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/136.0.0.0 Safari/537.36',
  'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/134.0.0.0 Safari/537.36',
  'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/141.0.0.0 Safari/537.36 Edg/141.0.0.0',
  'Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:125.0) Gecko/20100101 Firefox/125.0',
  'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.5 Safari/605.1.1',
  'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/16.1 Safari/605.1.15',
  'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/134.0.0.0 Safari/537.36 Edg/134.0.0.0',
  'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/136.0.0.0 Safari/537.36 Edg/136.0.0.0',
];

/// 随机HTTP请求头accept-language字段列表
const List<String> acceptLanguageList = [
  'zh-CN,zh;q=0.9',
  'zh-CN,zh;q=0.9,en;q=0.8,en-GB;q=0.7,en-US;q=0.6',
  'zh-CN,zh-TW;q=0.9,zh;q=0.8,en-US;q=0.7,en;q=0.6',
];

/// Bangumi API 文档要求的UA格式
Map<String, String> bangumiHTTPHeader = {
  'user-agent': 'anikumo/${ApiEndpoints.version} (Android)',
  'referer': '',
  'content-type': 'application/json'
};

/// 可选硬件解码器
const Map<String, String> hardwareDecodersList = {
  'auto': '启用任意可用解码器',
  'auto-safe': '启用最佳解码器',
  'auto-copy': '启用带拷贝功能的最佳解码器',
  'd3d11va': 'DirectX11 (windows8 及以上)',
  'd3d11va-copy': 'DirectX11 (windows8 及以上) (非直通)',
  'videotoolbox': 'VideoToolbox (macOS / iOS)',
  'videotoolbox-copy': 'VideoToolbox (macOS / iOS) (非直通)',
  'vaapi': 'VAAPI (Linux)',
  'vaapi-copy': 'VAAPI (Linux) (非直通)',
  'nvdec': 'NVDEC (NVIDIA独占)',
  'nvdec-copy': 'NVDEC (NVIDIA独占) (非直通)',
  'drm': 'DRM (Linux)',
  'drm-copy': 'DRM (Linux) (非直通)',
  'vulkan': 'Vulkan (全平台) (实验性)',
  'vulkan-copy': 'Vulkan (全平台) (实验性) (非直通)',
  'dxva2': 'DXVA2 (Windows7 及以上)',
  'dxva2-copy': 'DXVA2 (Windows7 及以上) (非直通)',
  'vdpau': 'VDPAU (Linux)',
  'vdpau-copy': 'VDPAU (Linux) (非直通)',
  'mediacodec': 'MediaCodec (Android)',
  'mediacodec-copy': 'MediaCodec (Android) (非直通)',
  'cuda': 'CUDA (NVIDIA独占) (过时)',
  'cuda-copy': 'CUDA (NVIDIA独占) (过时) (非直通)',
  'crystalhd': 'CrystalHD (全平台) (过时)',
  'rkmpp': 'Rockchip MPP (仅部分Rockchip芯片)',
};

/// Android 可选视频渲染器
const Map<String, String> androidVideoRenderersList = {
  'auto': '自动选择',
  'gpu': '基于 OpenGL, 通用和稳健的选项',
  'gpu-next': '基于 Vulkan, 在新设备上表现最好',
  'mediacodec_embed': '功耗最低，不支持超分辨率',
};

/// 超分辨率滤镜
const List<String> mpvAnime4KShaders = [
  'Anime4K_Clamp_Highlights.glsl',
  'Anime4K_Restore_CNN_VL.glsl',
  'Anime4K_Upscale_CNN_x2_VL.glsl',
  'Anime4K_AutoDownscalePre_x2.glsl',
  'Anime4K_AutoDownscalePre_x4.glsl',
  'Anime4K_Upscale_CNN_x2_M.glsl'
];

/// 超分辨率滤镜 (轻量)
const List<String> mpvAnime4KShadersLite = [
  'Anime4K_Clamp_Highlights.glsl',
  'Anime4K_Restore_CNN_M.glsl',
  'Anime4K_Restore_CNN_S.glsl',
  'Anime4K_Upscale_CNN_x2_M.glsl',
  'Anime4K_AutoDownscalePre_x2.glsl',
  'Anime4K_AutoDownscalePre_x4.glsl',
  'Anime4K_Upscale_CNN_x2_S.glsl'
];

/// 可选播放倍速
const List<double> defaultPlaySpeedList = [
  0.25,
  0.5,
  0.75,
  1.0,
  1.25,
  1.5,
  1.75,
  2.0,
  2.25,
  2.5,
  2.75,
  3.0,
];

/// 距视频结尾在此阈值内视为"已看完"：
/// 保存历史时进度归零，续播起点落在其中时从头播放
const Duration nearEndWatchedThreshold = Duration(seconds: 5);

const String danmakuOnSvg = '''
    <svg xmlns=\"http://www.w3.org/2000/svg\" data-pointer=\"none\" viewBox=\"0 0 24 24\"><path fill=\"#FFFFFF\" fill-rule=\"evenodd\" d=\"M5.6 6.9 L7.4 3.4 L9.8 6.9 Z M14.2 6.9 L16.6 3.4 L18.4 6.9 Z M6.5 6.5 h11 a3.5 3.5 0 0 1 3.5 3.5 v5.5 a3.5 3.5 0 0 1 -3.5 3.5 h-6.2 L7 21.6 v-2.6 h-.5 a3.5 3.5 0 0 1 -3.5 -3.5 V10 a3.5 3.5 0 0 1 3.5 -3.5 z M7.15 9.3 h6.699999999999999 a0.95 0.95 0 0 1 0.95 0.95 v0.0 a0.95 0.95 0 0 1 -0.95 0.95 h-6.699999999999999 a0.95 0.95 0 0 1 -0.95 -0.95 v-0.0 a0.95 0.95 0 0 1 0.95 -0.95 z M7.15 12.4 h9.7 a0.95 0.95 0 0 1 0.95 0.95 v0.0 a0.95 0.95 0 0 1 -0.95 0.95 h-9.7 a0.95 0.95 0 0 1 -0.95 -0.95 v-0.0 a0.95 0.95 0 0 1 0.95 -0.95 z M7.15 15.5 h3.5000000000000004 a0.95 0.95 0 0 1 0.95 0.95 v0.0 a0.95 0.95 0 0 1 -0.95 0.95 h-3.5000000000000004 a0.95 0.95 0 0 1 -0.95 -0.95 v-0.0 a0.95 0.95 0 0 1 0.95 -0.95 z\"/><path fill=\"#00AEEC\" d=\"M13.400000000000002 17.9 a4.7 4.7 0 1 0 9.4 0 a4.7 4.7 0 1 0 -9.4 0 z\"/><path fill=\"none\" stroke=\"#FFFFFF\" stroke-width=\"1.7\" stroke-linecap=\"round\" stroke-linejoin=\"round\" d=\"M15.900000000000002 17.9 l1.9 1.9 l3.4 -3.6\"/></svg>
    ''';

/// 可选播放器日志等级
/// LogLevel 0: 错误 1: 警告 2: 简略 3: 详细 4: 调试（隐藏） 5: 全部（隐藏）
const Map<int, String> playerLogLevelMap = {
  0: "错误",
  1: "警告",
  2: "简略",
  3: "详细",
  // 以下两个级别被MPV官方支持，但是输出内容过于冗长，暂时隐藏
  // 4: "调试",
  // 5: "全部",
};

final List<String> defaultAnimeTags = const [
  '日常',
  '原创',
  '校园',
  '搞笑',
  '奇幻',
  '百合',
  '恋爱',
  '悬疑',
  '热血',
  '后宫',
  '机战',
  '轻改',
  '偶像',
  '治愈',
  '异世界',
];

// 播放器默认快捷键
final Map<String, List<String>> defaultShortcuts = const {
  'playorpause': [' '],
  'forward': ['Arrow Right'],
  'rewind': ['Arrow Left'],
  'next': ['N'],
  'prev': ['P'],
  'volumeup': ['Arrow Up'],
  'volumedown': ['Arrow Down'],
  'togglemute': ['M'],
  'fullscreen': ['F'],
  'exitfullscreen': ['Escape'],
  'toggledanmaku': ['D'],
  'screenshot': ['S'],
  'skip': ['K'],
  'speed1': ['1'],
  'speed2': ['2'],
  'speed3': ['3'],
  'speedup': ['X'],
  'speeddown': ['Z'],
};

// 键位别名
final Map<String, String> keyAliases = {
  ' ': '空格',
  'Arrow Up': '↑',
  'Arrow Down': '↓',
  'Arrow Left': '←',
  'Arrow Right': '→',
  'Enter': '回车',
  'Tab': 'Tab',
  'Escape': 'Esc',
  'Backspace': '退格',
};

//功能中文名对应
final Map<String, String> shortcutsChineseName = {
  'playorpause': '播放 / 暂停',
  'forward': '快进 / 长按倍速',
  'rewind': '快退',
  'next': '下一集',
  'prev': '上一集',
  'volumeup': '音量加',
  'volumedown': '音量减',
  'togglemute': '静音',
  'fullscreen': '全屏',
  'exitfullscreen': '退出全屏',
  'toggledanmaku': '弹幕开关',
  'screenshot': '截图',
  'skip': '跳过',
  'speed1': '倍速：1x',
  'speed2': '倍速：2x',
  'speed3': '倍速：3x',
  'speedup': '倍速加',
  'speeddown': '倍速减',
};
