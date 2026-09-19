/// 可以唤起的地图应用。
///
/// 放在模型层：设置项要引用它，而导航服务又要读设置，
/// 留在服务层会让两边互相 import。
enum NavApp {
  amap('高德地图'),
  baidu('百度地图'),
  tencent('腾讯地图'),
  appleMaps('苹果地图'),
  system('系统默认地图');

  const NavApp(this.label);

  final String label;
}
