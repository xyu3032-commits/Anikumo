class MenuRouteItem {
  const MenuRouteItem({required this.path});

  final String path;
}

class MenuRoute {
  const MenuRoute(this.menuList);

  final List<MenuRouteItem> menuList;

  String getPath(int index) => menuList[index].path;

  int indexForPath(String path) {
    final index = menuList.indexWhere(
      (item) =>
          path == '/tab${item.path}' ||
          path == '/tab${item.path}/' ||
          path.startsWith('/tab${item.path}/'),
    );
    return index < 0 ? 0 : index;
  }
}

const MenuRoute menu = MenuRoute([
  MenuRouteItem(path: '/popular'),
  MenuRouteItem(path: '/featured'),
  MenuRouteItem(path: '/discover'),
  // Batch 37 grew the shell to 8 tabs; batch 55 moved
  // 工具箱 into Settings, leaving 7.
  MenuRouteItem(path: '/moments'),
  MenuRouteItem(path: '/timeline'),
  MenuRouteItem(path: '/collect'),
  MenuRouteItem(path: '/my'),
]);
