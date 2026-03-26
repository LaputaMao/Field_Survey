import 'dart:async';
import 'dart:io';
import 'package:field_survey/screens/task_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';
import 'package:dotted_border/dotted_border.dart';
import '../widgets/hold_to_complete_button.dart'; // 引入咱们刚写的长按按钮
import 'package:coordtransform/coordtransform.dart' as coordtransform;
import 'package:amap_core/amap_core.dart' as yu hide LatLng, MapOptions;

class HomeScreen extends StatefulWidget {
  @override
  _HomeScreenState createState() => _HomeScreenState();
}

// 1. 新增两个实体类，用于存储解析出的线和点以及它们的 properties（把它放在 _HomeScreenState 类的上面）
class TaskLine {
  final List<LatLng> points;
  final Map<String, dynamic> properties;

  TaskLine({required this.points, required this.properties});
}

class TaskPoint {
  final LatLng location;
  final Map<String, dynamic> properties;

  TaskPoint({required this.location, required this.properties});
}

class _HomeScreenState extends State<HomeScreen> {
  final MapController _mapController = MapController();

  // 右上角打开侧边栏的 Key
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  String _currentTaskTitle = "请从右侧菜单选择任务";

  // 2. 在 _HomeScreenState 内部，新增两个列表存放解析后的数据
  List<TaskLine> _taskLines = [];
  List<TaskPoint> _taskPoints = [];

  // 新增：记录当前用户选中的线路
  TaskLine? _selectedLine;

  // 路线与点位存储
  List<LatLng> _actualRoute = []; // 实际走过的绿色轨迹
  List<Map<String, dynamic>> _actualPoints = []; // 实际打的点

  // 状态控制
  bool _isSurveying = false; // 是否在调查中
  LatLng? _currentLocation; // 手机实时GPS位置
  StreamSubscription<Position>? _positionStream; // 轨迹监听流

  @override
  void initState() {
    super.initState();
    // 页面初始化时，尝试获取一次当前位置并自动跳转
    _initCurrentLocation();
  }

  // ============== 新增逻辑：进入地图自动定位 ==============
  Future<void> _initCurrentLocation() async {
    // 1. 检查手机 GPS 服务是否开启
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      // 如果没开GPS，就保持默认视图(不跳转)
      return;
    }

    // 2. 检查应用是否拥有定位权限
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        return; // 用户拒绝权限，保持默认视图
      }
    }

    try {
      // 3. 获取当前最新的单签位置 (并非持续追踪)
      Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.best,
        timeLimit: Duration(seconds: 5), // 给定一个超时时间，防止卡死
      );

      // 4. 更新坐标并平滑移动地图视角
      if (mounted) {
        setState(() {
          _currentLocation = LatLng(position.latitude, position.longitude);
        });

        // 将地图中心点移动到用户的实际位置，缩放级别设为 16.0
        _mapController.move(_currentLocation!, 16.0);
      }
    } catch (e) {
      debugPrint("初始定位获取失败: $e");
    }
  }

  @override
  void dispose() {
    _positionStream?.cancel();
    super.dispose();
  }

  // --- 新增：GPS(WGS84) 转 高德(GCJ-02) ---
  LatLng _wgsToGcj(LatLng wgs84) {
    // // coordtransform 格式：[lon, lat]
    // // todo 修改成 GCJ02
    // final gcjList = coordtransform.CoordTransform.transformWGS84toGCJ02(
    //   wgs84.longitude,
    //   wgs84.latitude,
    // );
    // return LatLng(gcjList.lat, gcjList.lon); // 转回 LatLng(lat, lon)
    return wgs84;
  }

  // (可选拓展) 高德(GCJ-02) 转 GPS(WGS84)，比如想把地图点击获取的坐标反转存库时用
  LatLng _gcjToWgs(LatLng gcj02) {
    final wgsList = coordtransform.CoordTransform.transformGCJ02toWGS84(
      gcj02.longitude,
      gcj02.latitude,
    );
    return LatLng(wgsList.lat, wgsList.lon);
  }

  // 3. 重写 _loadTaskToMap 方法处理 GeoJSON
  void _loadTaskToMap(Map<String, dynamic> result) {
    final taskInfo = result['task_info'];
    final geojson = result['geojson'];

    List<TaskLine> parsedLines = [];
    List<TaskPoint> parsedPoints = [];
    List<LatLng> allCoordinatesForBounding = []; // 用于计算地图缩放视野

    if (geojson['type'] == 'FeatureCollection' && geojson['features'] != null) {
      for (var feature in geojson['features']) {
        final geometry = feature['geometry'];
        final properties = feature['properties'] ?? {};

        if (geometry['type'] == 'LineString') {
          List<LatLng> lineCoords = [];
          for (var coord in geometry['coordinates']) {
            // GeoJSON 格式是 [Lon, Lat]，所以 coord[1] 是纬度，coord[0] 是经度
            LatLng ll = LatLng(coord[1], coord[0]);
            lineCoords.add(ll);
            allCoordinatesForBounding.add(ll);
          }
          parsedLines.add(TaskLine(points: lineCoords, properties: properties));
        } else if (geometry['type'] == 'Point') {
          var coord = geometry['coordinates'];
          LatLng ll = LatLng(coord[1], coord[0]);
          parsedPoints.add(TaskPoint(location: ll, properties: properties));
          allCoordinatesForBounding.add(ll);
        }
      }
    }

    setState(() {
      _taskLines = parsedLines;
      _taskPoints = parsedPoints;
      _currentTaskTitle = "执行任务: #${taskInfo['id']} (${taskInfo['status']})";
    });

    // 修改：为了在加载任务时精确将画面缩放到包含所有要素，边界计算也应使用 GCJ02
    if (allCoordinatesForBounding.isNotEmpty) {
      // 把所有的 WGS84 临时转成 GCJ 算边界123123
      final gcjBoundsCoordinates = allCoordinatesForBounding
          .map((p) => _wgsToGcj(p))
          .toList();
      final bounds = LatLngBounds.fromPoints(gcjBoundsCoordinates);
      // flutter_map 6.x 控制视角缩放的方法 (增加了一些 Padding 防止点贴在屏幕边缘)
      _mapController.fitCamera(
        CameraFit.bounds(
          bounds: bounds,
          padding: EdgeInsets.all(50.0), // 四周留出 50 像素空隙
        ),
      );
    }
  }

  // 4. 重写显示 Properties 弹窗的方法
  void _showPropertiesSheet(Map<String, dynamic> properties, String type) {
    showModalBottomSheet(
      context: context,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return Padding(
          padding: EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                "[$type] 详情信息",
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              SizedBox(height: 15),
              // 动态遍历 properties 里的所有键值对并展示
              ...properties.entries
                  .map(
                    (entry) => Padding(
                      padding: const EdgeInsets.only(bottom: 8.0),
                      child: Text(
                        "${entry.key}: ${entry.value}",
                        style: TextStyle(fontSize: 16),
                      ),
                    ),
                  )
                  .toList(),
              SizedBox(height: 20),
            ],
          ),
        );
      },
    );
  }

  // ============== 开始调查与结束调查 ==============
  Future<void> _startSurvey() async {
    // 1. 请求定位权限
    LocationPermission permission = await Geolocator.requestPermission();
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text("需要GPS权限才能开始定位打卡")));
      return;
    }

    setState(() {
      _isSurveying = true;
      _actualRoute.clear();
      _actualPoints.clear();
    });

    // 2. 开启位置实时监听
    _positionStream =
        Geolocator.getPositionStream(
          locationSettings: LocationSettings(
            accuracy: LocationAccuracy.best,
            distanceFilter: 2,
          ), // 移动2米更新一次
        ).listen((Position position) {
          setState(() {
            _currentLocation = LatLng(position.latitude, position.longitude);
            _actualRoute.add(_currentLocation!); // 压入绿色轨迹点
            _mapController.move(_currentLocation!, 16.0); // 视角跟随移动
          });
        });
  }

  void _endSurvey() {
    // 停止定位监听，打包数据发送后端，清空地图
    _positionStream?.cancel();

    // TODO: 调用后端接口打发数据
    // api.uploadSurveyResult(route: _actualRoute, points: _actualPoints);

    setState(() {
      _isSurveying = false;
      _actualRoute.clear();
      _actualPoints.clear();
      _currentLocation = null;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('调查已结束，数据已打包上传云端！'),
        backgroundColor: Colors.green,
      ),
    );
  }

  // ============== 打点填表 (底部弹窗) ==============
  void _openSurveyForm({Map<String, dynamic>? existingPoint, int? pointIndex}) {
    if (_currentLocation == null && existingPoint == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text("GPS信号弱，请稍后再试")));
      return;
    }

    // 表单控制器与照片列表
    TextEditingController descController = TextEditingController(
      text: existingPoint?['desc'] ?? '',
    );
    List<String> photos = existingPoint != null
        ? List<String>.from(existingPoint['photos'])
        : [];

    showModalBottomSheet(
      context: context,
      isScrollControlled: true, // 允许弹窗被键盘顶起
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        // 使用 StatefulBuilder 为了在弹窗内刷新照片列表
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setModalState) {
            // 拍照方法
            Future<void> _takePhoto() async {
              final ImagePicker _picker = ImagePicker();
              final XFile? image = await _picker.pickImage(
                source: ImageSource.camera,
              );
              if (image != null) {
                setModalState(() {
                  photos.add(image.path); // 将本地图片路径加入列表
                });
              }
            }

            return Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(context).viewInsets.bottom, // 防止键盘遮挡
                left: 20,
                right: 20,
                top: 20,
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      existingPoint == null ? "新增调查点" : "查看/编辑调查点",
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    SizedBox(height: 10),
                    // 仅显示GPS坐标（防作弊）
                    Text(
                      "打卡坐标：${existingPoint?['location']?.latitude ?? _currentLocation!.latitude}, ${existingPoint?['location']?.longitude ?? _currentLocation!.longitude}",
                      style: TextStyle(color: Colors.grey),
                    ),
                    SizedBox(height: 15),
                    TextField(
                      controller: descController,
                      maxLines: 3,
                      decoration: InputDecoration(
                        labelText: '环境描述与现场情况',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    SizedBox(height: 15),

                    // 照片区域
                    Text("现场照片", style: TextStyle(fontWeight: FontWeight.bold)),
                    SizedBox(height: 10),
                    Container(
                      height: 80,
                      child: ListView(
                        scrollDirection: Axis.horizontal,
                        children: [
                          // 1. 虚线拍照大按钮
                          GestureDetector(
                            onTap: _takePhoto,
                            child: DottedBorder(
                              color: Colors.grey,
                              strokeWidth: 2,
                              dashPattern: [6, 4], // 虚线长度
                              child: Container(
                                width: 80,
                                height: 80,
                                child: Center(
                                  child: Icon(
                                    Icons.add,
                                    size: 40,
                                    color: Colors.grey,
                                  ),
                                ),
                              ),
                            ),
                          ),
                          SizedBox(width: 10),

                          // 2. 已拍好的照片快视图列阵
                          ...photos.asMap().entries.map((entry) {
                            int idx = entry.key;
                            String path = entry.value;
                            return Stack(
                              children: [
                                Container(
                                  margin: EdgeInsets.only(right: 10),
                                  width: 80,
                                  height: 80, // 和虚线框等大
                                  decoration: BoxDecoration(
                                    border: Border.all(
                                      color: Colors.grey.shade300,
                                    ),
                                    image: DecorationImage(
                                      image: FileImage(File(path)),
                                      fit: BoxFit.cover,
                                    ),
                                  ),
                                ),
                                // 右上角的删除小红点
                                Positioned(
                                  top: 0,
                                  right: 10,
                                  child: GestureDetector(
                                    onTap: () {
                                      setModalState(() => photos.removeAt(idx));
                                    },
                                    child: Container(
                                      decoration: BoxDecoration(
                                        color: Colors.red,
                                        shape: BoxShape.circle,
                                      ),
                                      child: Icon(
                                        Icons.close,
                                        size: 18,
                                        color: Colors.white,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            );
                          }).toList(),
                        ],
                      ),
                    ),
                    SizedBox(height: 20),

                    // 底部按钮栏
                    Row(
                      children: [
                        if (existingPoint != null) // 如果是查看模式，允许删除整个点位
                          Expanded(
                            child: OutlinedButton(
                              style: OutlinedButton.styleFrom(
                                foregroundColor: Colors.red,
                              ),
                              onPressed: () {
                                setState(
                                  () => _actualPoints.removeAt(pointIndex!),
                                );
                                Navigator.pop(context);
                              },
                              child: Text('删除打卡点'),
                            ),
                          ),
                        if (existingPoint != null) SizedBox(width: 10),

                        Expanded(
                          flex: 2,
                          child: ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.green,
                            ),
                            onPressed: () {
                              // 保存逻辑
                              final newData = {
                                'location':
                                    existingPoint?['location'] ??
                                    _currentLocation,
                                'desc': descController.text,
                                'photos': photos,
                              };
                              setState(() {
                                if (existingPoint == null) {
                                  _actualPoints.add(newData); // 新增
                                } else {
                                  _actualPoints[pointIndex!] = newData; // 修改
                                }
                              });
                              Navigator.pop(context); // 收起弹窗
                            },
                            child: Text(
                              existingPoint == null ? '保存点位' : '更新保存',
                              style: TextStyle(color: Colors.white),
                            ),
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: 20),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: _scaffoldKey, // 绑定 Key
      appBar: AppBar(
        title: Text(_currentTaskTitle, style: TextStyle(fontSize: 16)),
        backgroundColor: Colors.green,
        // 如果使用了 endDrawer，Flutter 会自动在右上角加上三点（汉堡）图标
        // 我们也可以自定义这个按钮
        actions: [
          IconButton(
            icon: Icon(Icons.more_vert), // 右上角的三个点
            onPressed: () {
              // 划出右侧侧边栏
              _scaffoldKey.currentState?.openEndDrawer();
            },
          ),
        ],
      ),

      // ================= 右侧滑出的侧边栏 =================
      endDrawer: Drawer(
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            DrawerHeader(
              decoration: BoxDecoration(color: Colors.green),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Icon(Icons.account_circle, size: 60, color: Colors.white),
                  SizedBox(height: 10),
                  Text(
                    '野外调查员',
                    style: TextStyle(color: Colors.white, fontSize: 18),
                  ),
                ],
              ),
            ),
            ListTile(
              leading: Icon(Icons.map),
              title: Text('主控地图'),
              onTap: () => Navigator.pop(context), // 点击后收起侧边栏
            ),
            ListTile(
              leading: Icon(Icons.assignment),
              title: Text('我的任务'),
              onTap: () async {
                // 1. 收起侧边栏
                Navigator.pop(context);
                // 2. 跳转到任务页面，并等待其返回结果
                final result = await Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => TaskScreen()),
                );
                // 3. 接收返回的路线数据，绘制在地图上
                if (result != null) {
                  _loadTaskToMap(result);
                }
              },
            ),
            Divider(),
            ListTile(
              leading: Icon(Icons.settings),
              title: Text('离线地图下载'), // 占位
              onTap: () => Navigator.pop(context),
            ),
            ListTile(
              leading: Icon(Icons.logout, color: Colors.red),
              title: Text('退出登录', style: TextStyle(color: Colors.red)),
              onTap: () {
                // TODO: 清除 Token 并退回登录页
              },
            ),
          ],
        ),
      ),

      // ================= 核心：地图引擎部分 =================
      body: Stack(
        children: [
          // 1. 地图层
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              center: LatLng(30.2741, 120.1551), // 默认
              zoom: 15.0,
              // 点击地图空白处，计算距离并选中路线
              onTap: (tapPosition, LatLng clickedLatLngGcj) {
                // 注意：由于底层是高德，点击获取的坐标自带 GCJ-02 偏移！
                TaskLine? closestLine;
                double minDistance = double.infinity;

                for (var taskLine in _taskLines) {
                  for (var wgsPoint in taskLine.points) {
                    // 我们要把后台真实的 WGS84 路线点 转换成 GCJ02 再去比较距离
                    LatLng gcjPoint = _wgsToGcj(wgsPoint);
                    double distance = Distance().as(
                      LengthUnit.Meter,
                      clickedLatLngGcj,
                      gcjPoint,
                    );
                    if (distance < 50 && distance < minDistance) {
                      // 50米容差
                      minDistance = distance;
                      closestLine = taskLine;
                    }
                  }
                }

                setState(() {
                  _selectedLine = closestLine; // 若没点中，就是 null，卡片消失
                });
              },
            ),
            children: [
              //天地图矢量底图 (需把你的tk替换掉末尾的 YOUR_TK)
              TileLayer(
                urlTemplate:
                    'http://t0.tianditu.gov.cn/vec_w/wmts?SERVICE=WMTS&REQUEST=GetTile&VERSION=1.0.0&LAYER=vec&STYLE=default&TILEMATRIXSET=w&FORMAT=tiles&TILEMATRIX={z}&TILEROW={y}&TILECOL={x}&tk=e48048d5cca7c1445e08536185177ba2',
                userAgentPackageName: 'com.LaputaMao.field_survey',
              ),
              //天地图矢量注记图层（文字地名，通常盖在底图上面一层）
              TileLayer(
                urlTemplate:
                    'http://t0.tianditu.gov.cn/cva_w/wmts?SERVICE=WMTS&REQUEST=GetTile&VERSION=1.0.0&LAYER=cva&STYLE=default&TILEMATRIXSET=w&FORMAT=tiles&TILEMATRIX={z}&TILEROW={y}&TILECOL={x}&tk=e48048d5cca7c1445e08536185177ba2',
                backgroundColor: Colors.transparent, // 背景透明，只盖文字
                userAgentPackageName: 'com.LaputaMao.field_survey',
              ),

              // // todo 切换成高德
              // TileLayer(
              //   // 1. 高德卫星纯影像底图图层
              //   urlTemplate:
              //       'https://webst0{s}.is.autonavi.com/appmaptile?style=6&x={x}&y={y}&z={z}&key=2f0fcf7450f5ef55cf109244f76c3235',
              //   subdomains: const ['1', '2', '3', '4'],
              //   userAgentPackageName: 'com.LaputaMao.field_survey',
              // ),
              //
              // TileLayer(
              //   // 2. 高德路网及地名标签图层 (透明背景盖在卫星图上)
              //   urlTemplate:
              //       'https://wprd0{s}.is.autonavi.com/appmaptile?x={x}&y={y}&z={z}&lang=zh_cn&size=1&scl=1&style=8&key=2f0fcf7450f5ef55cf109244f76c3235',
              //   subdomains: const ['1', '2', '3', '4'],
              //   backgroundColor: Colors.transparent, // 必须透明
              //   userAgentPackageName: 'com.LaputaMao.field_survey',
              // ),

              // --------------- 渲染 GeoJSON 的多段线 ---------------
              PolylineLayer(
                polylines: _taskLines.map((taskLine) {
                  bool isSelected = (_selectedLine == taskLine);
                  // 遍历路线，视图层实时 _wgsToGcj 转换
                  final gcjPoints = taskLine.points
                      .map((p) => _wgsToGcj(p))
                      .toList();

                  return Polyline(
                    points: gcjPoints,
                    strokeWidth: isSelected ? 6.0 : 4.0, // 选中加粗
                    color: isSelected
                        ? Colors.yellowAccent
                        : Colors.blueAccent.withOpacity(0.8), // 选中高亮黄
                  );
                }).toList(),
              ),

              // --------------- 渲染 GeoJSON 规划的点位 ---------------
              // MarkerLayer(
              //   markers: _taskPoints.map((taskPoint) {
              //     return Marker(
              //       point: taskPoint.location,
              //       width: 45,
              //       height: 45,
              //       child: GestureDetector(
              //         onTap: () {
              //           // 点击规划点，展示后端派发的 properties
              //           _showPropertiesSheet(taskPoint.properties, "规划调查点");
              //         },
              //         child: const Icon(
              //           Icons.place,
              //           color: Colors.purple,
              //           size: 40,
              //         ),
              //       ),
              //     );
              //   }).toList(),
              // ),

              // ---------------实际行走的绿色轨迹---------------
              PolylineLayer(
                polylines: [
                  Polyline(
                    // 同样，用户的实际轨迹也是 WGS84，渲染到高德图上时要转 GCJ02
                    points: _actualRoute.map((p) => _wgsToGcj(p)).toList(),
                    strokeWidth: 5.0,
                    color: Colors.green,
                  ),
                ],
              ),
              // ---------------实际打卡的点位 (使用显眼的橙色/深绿)---------------
              // MarkerLayer(
              //   markers: _actualPoints.asMap().entries.map((entry) {
              //     int index = entry.key;
              //     Map<String, dynamic> pt = entry.value;
              //     return Marker(
              //       point: pt['location'],
              //       width: 45,
              //       height: 45,
              //       child: GestureDetector(
              //         onTap: () =>
              //             _openSurveyForm(existingPoint: pt, pointIndex: index),
              //         child: const Icon(
              //           Icons.where_to_vote,
              //           color: Colors.orange,
              //           size: 40,
              //         ),
              //       ),
              //     );
              //   }).toList(),
              // ),
              //
              // // 用户实时的当前GPS小蓝点指示
              // if (_currentLocation != null)
              //   MarkerLayer(
              //     markers: [
              //       Marker(
              //         point: _currentLocation!,
              //         width: 20,
              //         height: 20,
              //         child: Container(
              //           decoration: BoxDecoration(
              //             color: Colors.blueAccent,
              //             shape: BoxShape.circle,
              //             border: Border.all(color: Colors.white, width: 2),
              //           ),
              //         ),
              //       ),
              //     ],
              //   ),
              MarkerLayer(
                markers: [
                  // 1. 展现尚未调查的规划打点
                  ..._taskPoints.map(
                    (taskPoint) => Marker(
                      point: _wgsToGcj(taskPoint.location), // 转 GCJ
                      width: 45,
                      height: 45,
                      child: GestureDetector(
                        onTap: () {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text("请选中关联的路线后开始调查")),
                          );
                        },
                        child: Icon(
                          Icons.place,
                          color: Colors.purple,
                          size: 40,
                        ),
                      ),
                    ),
                  ),
                  // 2. 真实打卡点(你在填表存库时存的是WGS84, _actualPoints 内提取 location 转 GCJ)
                  ..._actualPoints.asMap().entries.map(
                    (entry) => Marker(
                      point: _wgsToGcj(entry.value['location']), // 转 GCJ
                      width: 45,
                      height: 45,
                      child: GestureDetector(
                        onTap: () => _openSurveyForm(
                          existingPoint: entry.value,
                          pointIndex: entry.key,
                        ),
                        child: Icon(
                          Icons.where_to_vote,
                          color: Colors.orange,
                          size: 40,
                        ),
                      ),
                    ),
                  ),
                  // 3. 当前实时 GPS 小蓝点
                  if (_currentLocation != null)
                    Marker(
                      point: _wgsToGcj(_currentLocation!), // 转 GCJ
                      width: 20,
                      height: 20,
                      child: Container(
                        decoration: BoxDecoration(
                          color: Colors.blueAccent,
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 2),
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),

          // 右下角的悬浮按钮组
          // Positioned(
          //   bottom: 30,
          //   right: 20,
          //   child: Column(
          //     mainAxisSize: MainAxisSize.min,
          //     crossAxisAlignment: CrossAxisAlignment.end,
          //     children: [
          //       // 解锁的打点按钮（只有surveying为true才显示出橘色打点按钮）
          //       if (_isSurveying) ...[
          //         FloatingActionButton(
          //           heroTag: "mark_btn",
          //           backgroundColor: Colors.orange,
          //           onPressed: () => _openSurveyForm(),
          //           child: Icon(Icons.add_location_alt, size: 30),
          //         ),
          //         SizedBox(height: 20), // 按钮间距
          //       ],
          //
          //       // 核心控制按钮 (未开始: 绿色开始按键; 进行中: 红色长按结束健)
          //       _isSurveying
          //           ? HoldToCompleteButton(onCompleted: _endSurvey) // 调用自定义长按按钮
          //           : FloatingActionButton.extended(
          //               heroTag: "start_btn",
          //               backgroundColor: Colors.green,
          //               onPressed: _startSurvey,
          //               icon: Icon(Icons.play_arrow),
          //               label: Text(
          //                 "开始调查",
          //                 style: TextStyle(fontWeight: FontWeight.bold),
          //               ),
          //             ),
          //     ],
          //   ),
          // ),
          // 2. 顶部悬浮属性卡片（不遮挡和变暗地图）
          if (_selectedLine != null && !_isSurveying)
            Positioned(
              top: 50, // 距离顶部安全区往下一点
              left: 20,
              right: 20,
              child: Card(
                elevation: 8,
                shadowColor: Colors.black45,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(15),
                ),
                child: Padding(
                  padding: EdgeInsets.all(15),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            "已选定路线详情",
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Colors.green[800],
                            ),
                          ),
                          GestureDetector(
                            onTap: () => setState(() => _selectedLine = null),
                            // 右上角关闭按钮
                            child: Icon(Icons.close, color: Colors.grey),
                          ),
                        ],
                      ),
                      Divider(),
                      // 动态展示该线的 properties
                      ..._selectedLine!.properties.entries
                          .map(
                            (entry) => Padding(
                              padding: EdgeInsets.only(bottom: 6.0),
                              child: Text(
                                "${entry.key}: ${entry.value}",
                                style: TextStyle(fontSize: 14),
                              ),
                            ),
                          )
                          .toList(),
                    ],
                  ),
                ),
              ),
            ),

          // 3. 右下角的悬浮按钮组 (修改了“开始按钮”属性)
          Positioned(
            bottom: 30,
            right: 20,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                if (_isSurveying) ...[
                  FloatingActionButton(
                    heroTag: "mark_btn",
                    backgroundColor: Colors.orange,
                    onPressed: () => _openSurveyForm(),
                    child: Icon(Icons.add_location_alt, size: 30),
                  ),
                  SizedBox(height: 20),
                ],

                _isSurveying
                    ? HoldToCompleteButton(onCompleted: _endSurvey)
                    : FloatingActionButton.extended(
                        heroTag: "start_btn",
                        // 若未选择线，按钮置灰
                        backgroundColor: _selectedLine == null
                            ? Colors.grey
                            : Colors.green,
                        onPressed: () {
                          if (_selectedLine == null) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text("请先点击地图选择一条红色的规划路线")),
                            );
                            return; // 拒绝开始
                          }
                          _startSurvey(); // 开始调查
                        },
                        icon: Icon(Icons.play_arrow),
                        label: Text(
                          "开始调查",
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
